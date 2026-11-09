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
    UNLOCKABLE = %i[station_symbol max_speed].freeze # abilities whose own abilities apply only once unlocked
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

    # A permanent's printed abilities, the abilities of its unlocked symbols in their place.
    def abilities_of(obj)
      defn(obj.card).abilities.reject { UNLOCKABLE.include?(it.kind) } + unlocked(obj).flat_map(&:nested_abilities)
    end

    # Its station symbols it has enough charge counters for (CR 722.2a), recomputed from the raw counters, and
    # its max speed abilities while its controller's speed is 4 (CR 702.178a, 702.179e), and its class level
    # bars up to its level (CR 717.2a).
    def unlocked(obj)
      charge = obj.counters.fetch("charge", 0)
      fast = state.players[obj.controller].speed == 4
      level = obj.memory.fetch("class_level", 1) # CR 717.2a, 717.2d
      defn(obj.card).abilities.select do |ability|
        case ability.kind
        when :station_symbol then charge >= ability.threshold
        when :max_speed then fast
        else ability.is_a?(Mechanics::Abilities::ClassLevel) && level >= ability.level
        end
      end
    end

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
      # CR 500.5: mana pools, restricted mana included, empty between steps.
      state.players.each do |pl|
        # CR 702.189a: "until end of combat" mana is still there as each combat step begins
        next if pl.mana_pool.values.all?(&:zero?) && pl.restricted_mana.all? { Engine::ManaSources.mana_held?(it, state.step) }

        finding("500.5", "#{pl.name}'s mana pool isn't empty at #{state.step}")
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
      allowed = 1 + additional_land_plays(state.players.index { it.name == player })
      finding("305.2", "#{player} played #{@lands_this_turn[player]} lands this turn") if @lands_this_turn[player] > allowed
      active = state.players[state.active].name
      finding("305.1", "#{player} played a land on #{active}'s turn") if player != active
    end

    # CR 305.2: "you may play an additional land" abilities of the player's permanents, from the raw card data
    # and from resolved effects that granted them (Effects::Become).
    def additional_land_plays(index)
      state.battlefield.sum do |id|
        obj = state.objects[id]
        next 0 unless obj.controller == index

        printed = defn(obj.card).abilities.count { it.kind == :additional_land_plays }
        granted = state.effects.select { it["kind"] == "abilities" && it["affected"].include?(id) }.sum do |effect|
          defn(effect["card"]).effect_granted(effect["ref"]).count { it.ability.kind == :additional_land_plays }
        end
        printed + granted
      end
    end

    # CR 307.1 / 301.1 etc.: sorcery-speed spells only in your main phase with an empty stack.
    def spell_cast!(event)
      card = defn(event.card)
      @stats["cast:#{event.card}"] += 1
      return if card.instant_speed? || event.during_resolution # CR 608.2g: timing doesn't apply

      caster = event.player
      return if sneaked?(event, caster)

      # The stack was empty as casting began (CR 601.2a) when the spell is at its bottom; what went on it since
      # ("whenever you cast" triggers, even one still waiting for its targets, CR 603.3d) doesn't count.
      unless state.players[state.active].name == caster && %i[precombat_main postcombat_main].include?(state.step) &&
             state.stack.last == event.object
        finding("307.1", "#{caster} cast sorcery-speed #{event.card} at #{state.step} (stack #{state.stack.size})")
      end
    end

    # CR 702.190a: a spell cast for its sneak cost, at instant speed during its caster's declare blockers step.
    def sneaked?(event, caster)
      state.objects[event.object]&.memory&.[]("cast_with") == "sneak" && state.step == :declare_blockers &&
        state.players[state.active].name == caster
    end

    # Printed keywords plus those of unlocked symbols, keywords granted and those of statics. A permanent that
    # loses all abilities (CR 613.1f) has only the keywords granted to it (timestamps are the engine's specs').
    def keyword?(obj, keyword)
      return granted_keywords(obj.id).include?(keyword.to_sym) if stripped?(obj)

      defn(obj.card).keyword?(keyword) || unlocked(obj).any? { it.keywords.include?(keyword) } ||
        granted_keywords(obj.id).include?(keyword.to_sym) || static_keyword?(obj, keyword)
    end

    # Whether an effect or an applying static ability makes it lose all abilities (CR 613.1f).
    def stripped?(obj)
      return true if state.effects.any? { it["kind"] == "lose_abilities" && it["affected"].include?(obj.id) }

      applying_statics(obj).any?(&:loses_abilities?)
    end

    # The static abilities of permanents on the battlefield that apply to `obj` now, matched on printed types.
    def applying_statics(obj)
      engine = @game.instance_variable_get(:@engine)
      facts = facts(obj, defn(obj.card))
      state.battlefield.flat_map do |id|
        source = state.objects[id]
        abilities_of(source).select do |ability|
          ability.kind == :static && ability.affects?(obj, source, facts) && ability.active?(engine, source)
        end
      end
    end

    # Keywords granted until end of turn or by an attached Aura or Equipment (CR 301.5f, 303.4m).
    def granted_keywords(id)
      until_eot = state.effects.select { it["kind"] == "grant" && it["affected"].include?(id) }.flat_map { it["keywords"] }
      (until_eot + attached_grants(id).flat_map { it["keywords"] }).map(&:to_sym)
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
    def static_keyword?(obj, keyword) = applying_statics(obj).any? { it.keywords.include?(keyword) }

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
      return if state.battlefield.any? { stripped?(state.objects[it]) } # CR 613.1f, 613.8a: the engine's specs

      view = @game.view_for(:observer)["battlefield"].to_h { [it["id"], it] }
      statics = static_pumps
      state.battlefield.each do |id|
        obj = state.objects[id]
        card = defn(obj.card)
        next unless recomputable?(obj, card)

        net = obj.counters.fetch("+1/+1", 0) - obj.counters.fetch("-1/-1", 0)
        pumps = state.effects.select { it["kind"] == "pump" && it["affected"].include?(id) } + attached_grants(id) +
                static_bonuses(obj, card, statics)
        base = base_power_toughness(id, card)
        expected = [base[0] + net + pumps.sum { it["power"] }, base[1] + net + pumps.sum { it["toughness"] }]
        actual = view.fetch(id).values_at("power", "toughness")
        finding("613.4c", "#{id} is #{actual.join("/")}, expected #{expected.join("/")}") if actual != expected
      end
    end

    # A creature whose power/toughness isn't characteristic-defining (7a) or set by a static ability (7b).
    def recomputable?(obj, card) = card.creature? && !card.defined_pt? && applying_statics(obj).none?(&:base_power_toughness)

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
        abilities_of(source).filter_map do |ability|
          next unless ability.kind == :static && ability.pump? && !ability.attached? && ability.active?(engine, source)

          [source, ability, ability.bonus(engine, source)]
        end
      end
    end

    def static_bonuses(obj, card, statics)
      facts = facts(obj, card)
      statics.filter_map do |source, ability, (power, toughness)|
        { "power" => power, "toughness" => toughness } if ability.affects?(obj, source, facts)
      end
    end

    # What statics match a permanent on: its printed characteristics, every creature type for a changeling
    # (CR 702.73a) and the keywords it was granted (a bonus to creatures "with flying", CR 702.1).
    def facts(obj, card)
      chars = Mechanics::Keywords::Changeling.apply(card.printed_characteristics)
      chars = chars.with(keywords: chars.keywords | granted_keywords(obj.id))
      Mechanics::Filters::Facts.new(chars: chars, counters: obj.counters, token: card.token?)
    end

    # "Equipped/enchanted creature gets/has ..." of every permanent attached to `id` whose condition holds
    # ("during your turn", CR 604.2): [{"power" => n, "toughness" => n, "keywords" => [...]}].
    def attached_grants(id)
      engine = @game.instance_variable_get(:@engine)
      state.battlefield.filter_map { state.objects[it] if state.objects[it].attached_to == id }.flat_map do |att|
        abilities_of(att).filter_map do |ability|
          next unless ability.kind == :static && ability.attached? && ability.active?(engine, att)

          power, toughness = ability.bonus(engine, att)
          { "power" => power, "toughness" => toughness, "keywords" => ability.keywords }
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
