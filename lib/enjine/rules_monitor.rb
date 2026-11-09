# frozen_string_literal: true

module Enjine
  # An independent rules checker for fuzzing. It watches a game's events and state
  # and re-derives, from the raw data and the rules, what must be true after each
  # decision, without calling the engine's own rules code. Any mismatch is a
  # finding: the engine did something the rules don't allow.
  #
  #   monitor = RulesMonitor.new(game)
  #   game.submit(option); monitor.check!(entry)   # or use Fuzz.run(..., monitor: true)
  #   monitor.findings  # => [] when everything matched
  #   monitor.stats     # mechanics observed, e.g. {"counters_added" => 12, ...}
  class RulesMonitor
    Finding = Data.define(:rule, :message, :turn, :step, :seq)

    attr_reader :findings, :stats

    def initialize(game)
      @game = game
      @findings = []
      @stats = Hash.new(0)
      @lands_this_turn = Hash.new(0)
      @loyalty_activations = Hash.new(0)
    end

    def state = @game.state
    def catalog = @game.catalog

    # Checks one history entry (one decision and everything it caused).
    def check!(entry)
      @entry = entry
      entry.events.each { observe(it) }
      check_state!
      @findings
    end

    private

    def finding(rule, message)
      @findings << Finding.new(rule: rule, message: message, turn: state.turn, step: state.step&.to_s, seq: @entry&.seq)
    end

    def defn(card) = catalog.fetch(card)

    # ---- per-event checks -------------------------------------------------------

    def observe(event)
      @stats[event.type] += 1
      case event
      when Events::TurnBegan then turn_began!
      when Events::StepBegan then step_began!(event)
      when Events::ZoneChanged then zone_changed!(event)
      when Events::SpellCast then spell_cast!(event)
      when Events::AbilityActivated then ability_activated!(event)
      when Events::AttackerDeclared then attacker_declared!(event)
      when Events::BlockerDeclared then blocker_declared!(event)
      when Events::CountersChanged then @stats["counters_#{event.counter}"] += event.to - event.from
      end
    end

    def turn_began!
      @lands_this_turn.clear
      @loyalty_activations.clear
      # CR 514.2: after cleanup no damage is marked and no "until end of turn" effect remains.
      state.battlefield.each do |id|
        finding("514.2", "#{id} still has #{state.objects[id].damage} damage at the start of a turn") if state.objects[id].damage.positive?
      end
      return if state.turn == 1 || state.effects.none? { it["duration"] == "end_of_turn" }

      finding("514.2", "an until-end-of-turn effect survived cleanup")
    end

    def step_began!(_event)
      # CR 500.5 (2026-11-06): mana pools, restricted mana included, empty between steps.
      state.players.each do |pl|
        next if pl.mana_pool.values.all?(&:zero?) && pl.restricted_mana.empty?

        finding("500.4", "#{pl.name}'s mana pool isn't empty at #{state.step}")
      end
    end

    def zone_changed!(event)
      land_played!(event) if event.reason == "play_land"
      return unless event.reason == "resolve" && event.to == "graveyard" && defn(event.card).permanent?

      finding("608.3", "permanent spell #{event.card} went to the graveyard on resolution")
    end

    # CR 305.1-305.2: whoever plays the land controls it (an exiled card of an opponent's may be played).
    def land_played!(event)
      land = state.objects[event.new_id]
      player = land ? state.players[land.controller].name : event.owner
      @lands_this_turn[player] += 1
      finding("305.2", "#{player} played #{@lands_this_turn[player]} lands this turn") if @lands_this_turn[player] > 1
      active = state.players[state.active].name
      finding("305.1", "#{player} played a land on #{active}'s turn") if player != active
    end

    # CR 307.1 / 301.1 etc.: sorcery-speed spells only in your main phase with an empty stack.
    def spell_cast!(event)
      card = defn(event.card)
      @stats["cast:#{event.card}"] += 1
      return if card.instant_speed? || event.during_resolution # CR 608.2g: timing doesn't apply

      caster = event.player
      # Triggered abilities put on the stack later in the same decision (e.g. "whenever you cast") don't count.
      stack = state.stack - @entry.events.grep(Events::TriggerPutOnStack).map(&:object)
      unless state.players[state.active].name == caster && %i[precombat_main postcombat_main].include?(state.step) &&
             stack.size == 1
        finding("307.1", "#{caster} cast sorcery-speed #{event.card} at #{state.step} (stack #{stack.size})")
      end
    end

    # Printed keywords plus those of station symbols with enough charge counters (CR 722.2a), recomputed
    # from the raw counters, and keywords granted until end of turn.
    def keyword?(obj, keyword)
      card = defn(obj.card)
      return true if card.keyword?(keyword)

      charge = obj.counters.fetch("charge", 0)
      stationed = card.ability_instances.any? do |inst|
        inst.ability.kind == :station_symbol && charge >= inst.ability.threshold && inst.ability.keywords.include?(keyword)
      end
      return true if stationed || attached_grants(obj.id).any? { it["keywords"].include?(keyword.to_s) }

      granted = state.effects.any? do |e|
        e["kind"] == "grant" && e["affected"].include?(obj.id) && e["keywords"].include?(keyword.to_s)
      end
      granted || static_keyword?(obj, keyword)
    end

    def ability_activated!(event)
      source = defn(event.card)
      ability = source.ability(event.ability)
      return unless ability&.kind == :loyalty

      @loyalty_activations[event.source] += 1
      if @loyalty_activations[event.source] > 1
        finding("606.3",
                "#{event.source} activated #{@loyalty_activations[event.source]} loyalty abilities this turn")
      end
      changes = @entry.events.grep(Events::CountersChanged).select { it.object == event.source && it.counter == "loyalty" }
      paid = changes.sum { it.to - it.from }
      return unless paid != ability.loyalty_cost && state.objects.key?(event.source) && changes.any?

      finding("606.4",
              "#{event.source} loyalty changed by #{paid}, cost was #{ability.loyalty_cost}")
    end

    # CR 302.6 / 508.1a: attackers were untapped and not summoning sick (or have haste).
    def attacker_declared!(event)
      obj = state.objects[event.object]
      return unless obj

      active_turn = state.turn
      sick = obj.controlled_since.nil? || obj.controlled_since >= active_turn
      finding("302.6", "summoning-sick #{event.object} attacked") if sick && !keyword?(obj, :haste)
      return unless keyword?(obj, :defender) && !keyword?(obj, :attacks_despite_defender)

      finding("702.3b", "#{event.object} has defender but attacked")
    end

    # A keyword from an applying static ability of a permanent (CR 604.2), matched on printed types.
    def static_keyword?(obj, keyword)
      engine = @game.instance_variable_get(:@engine)
      card = defn(obj.card)
      facts = Mechanics::Filters::Facts.new(chars: card.printed_characteristics, counters: obj.counters, token: card.token?)
      state.battlefield.any? do |id|
        source = state.objects[id]
        defn(source.card).abilities.any? do |ability|
          ability.kind == :static && ability.keywords.include?(keyword) && ability.affects?(obj, source, facts) &&
            ability.active?(engine, source)
        end
      end
    end

    # CR 702.9b: a creature with flying can be blocked only by creatures with flying or reach.
    def blocker_declared!(event)
      blocker = state.objects[event.object]
      attacker = state.objects[event.attacker]
      return unless blocker && attacker && keyword?(attacker, :flying)
      return if keyword?(blocker, :flying) || keyword?(blocker, :reach)

      finding("702.9b", "#{event.object} without flying or reach blocked flying #{event.attacker}")
    end

    # ---- state checks after each decision ------------------------------------------

    def check_state!
      check_power_toughness!
      check_damage_life!
      check_sba! if @game.pending_decision&.kind == "priority"
      check_hand_size!
    end

    # CR 613.4, recomputed independently: printed (or a 7b setting effect) + counters + active pump effects
    # + static ability bonuses. Characteristic-defining power/toughness (7a) is left to the engine's specs.
    def check_power_toughness!
      view = @game.view_for(:observer)["battlefield"].to_h { [it["id"], it] }
      statics = static_pumps
      state.battlefield.each do |id|
        obj = state.objects[id]
        card = defn(obj.card)
        next unless card.creature? && !card.defined_pt?

        net = obj.counters.fetch("+1/+1", 0) - obj.counters.fetch("-1/-1", 0)
        pumps = state.effects.select { it["kind"] == "pump" && it["affected"].include?(id) } + attached_grants(id) +
                static_bonuses(obj, card, statics)
        base = base_power_toughness(id, card)
        expected = [base[0] + net + pumps.sum { it["power"] }, base[1] + net + pumps.sum { it["toughness"] }]
        actual = view.fetch(id).values_at("power", "toughness")
        finding("613.4c", "#{id} is #{actual.join("/")}, expected #{expected.join("/")}") if actual != expected
      end
    end

    # CR 613.4b: the latest setting effect, else as printed.
    def base_power_toughness(id, card)
      setting = state.effects.select { it["kind"] == "base_power_toughness" && it["affected"].include?(id) }.last
      setting ? setting.values_at("power", "toughness") : [card.power, card.toughness]
    end

    # Static abilities printed on permanents that give a bonus to more than the attached permanent and
    # apply now: [[source object, ability, [power, toughness]], ...]. Conditions and amounts are the
    # primitives' own; which creatures get the bonus is decided here from printed types and raw counters.
    def static_pumps
      engine = @game.instance_variable_get(:@engine)
      state.battlefield.flat_map do |id|
        source = state.objects[id]
        defn(source.card).abilities.filter_map do |ability|
          next unless ability.kind == :static && ability.pump? && !ability.attached? && ability.active?(engine, source)

          [source, ability, ability.bonus(engine, source)]
        end
      end
    end

    def static_bonuses(obj, card, statics)
      facts = Mechanics::Filters::Facts.new(chars: card.printed_characteristics, counters: obj.counters, token: card.token?)
      statics.filter_map do |source, ability, (power, toughness)|
        { "power" => power, "toughness" => toughness } if ability.affects?(obj, source, facts)
      end
    end

    # Printed keyword, or granted by an Aura/Equipment attached to it (CR 301.5f, 303.4m).
    # "Equipped/enchanted creature gets/has ..." of every permanent attached to `id`, read from
    # the raw card data: [{"power" => n, "toughness" => n, "keywords" => [...]}].
    def attached_grants(id)
      state.battlefield.filter_map { state.objects[it] if state.objects[it].attached_to == id }.flat_map do |att|
        Array(defn(att.card).to_h["abilities"]).filter_map do |entry|
          static = entry["static"]
          next unless static.is_a?(Hash) && static["affects"] == "attached"

          pump = static.fetch("pump", {})
          { "power" => pump.fetch("power", 0), "toughness" => pump.fetch("toughness", 0),
            "keywords" => Array(static["keywords"]).map { it.downcase.tr(" -", "__") } }
        end
      end
    end

    # CR 120.3a: damage to a player causes that much life loss.
    def check_damage_life!
      events = @entry.events
      events.grep(Events::DamageDealt).each do |dmg|
        next unless dmg.target.start_with?("player:")

        @stats["damage_to_players"] += dmg.amount
        name = dmg.target.delete_prefix("player:")
        losses = events.grep(Events::LifeChanged).select { it.player == name && it.to < it.from }.sum { it.from - it.to }
        finding("120.3a", "#{name} took #{dmg.amount} damage but lost #{losses} life") if losses < dmg.amount
      end
    end

    # CR 704.5f/g/i: no creature with lethal damage or 0 toughness, no planeswalker with 0 loyalty, when a player has priority.
    def check_sba!
      view = @game.view_for(:observer)["battlefield"]
      view.each do |perm|
        lethal = perm.key?("toughness") && perm["damage"].positive? && perm["damage"] >= perm["toughness"] &&
                 !indestructible?(state.objects[perm["id"]]) # CR 702.12b: lethal damage doesn't destroy it
        if perm.key?("toughness") && (perm["toughness"] <= 0 || lethal)
          finding("704.5g", "#{perm["id"]} survived with #{perm["damage"]} damage and toughness #{perm["toughness"]}")
        end
        finding("704.5i", "#{perm["id"]} survived with 0 loyalty") if perm.key?("loyalty") && perm["loyalty"] <= 0
      end
    end

    def indestructible?(obj) = keyword?(obj, :indestructible)

    # CR 514.1: after cleanup the active player has at most seven cards (checked at the next turn's priority).
    # The player whose turn ended is the one active before (an extra turn may follow its own, CR 500.7).
    def check_hand_size!
      previous_name = @active_name
      @active_name = state.players[state.active].name if state.active
      return unless previous_name && @entry.events.any?(Events::TurnBegan)

      previous = state.players.find { it.name == previous_name }
      return if no_max_hand_size?(previous_name)

      finding("514.1", "#{previous.name} ended their turn with #{previous.hand.size} cards") if previous.hand.size > 7
    end

    # CR 402.2: an effect or a permanent's ability may give a player no maximum hand size.
    def no_max_hand_size?(name)
      ref = "player:#{name}"
      return true if state.effects.any? { it["rule"] == "no_max_hand_size" && it["affected"].include?(ref) }

      index = state.players.index { it.name == name }
      state.battlefield.any? do |id|
        obj = state.objects[id]
        defn(obj.card).abilities.any? do |ability|
          ability.kind == :player_rule && ability.rule == "no_max_hand_size" && ability.applies_to?(index, obj.controller)
        end
      end
    end
  end
end
