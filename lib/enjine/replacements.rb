# frozen_string_literal: true

module Enjine
  # A state change about to happen (CR 614.1). Mutations are proposed first, passed
  # through replacement effects, then executed, so "enters tapped", "if it would die,
  # exile it instead" and damage prevention can modify them before they occur.
  #
  # kind: "zone_change" | "damage" | "life" | "draw" | "counters" | "untap" | "create_token"
  # data: plain Hash describing the change; a replacement that stops the change entirely
  #       ("instead remove a stun counter") sets data["cancelled"] = true
  # applied: ids of replacement effects already applied (each applies once, CR 614.5)
  Proposal = Struct.new(:kind, :data, :applied)

  # The replacement-effect pass (CR 614-616).
  #
  # Applies, in order: the entering permanent's own self-replacement effects and the rules' own
  # entering modifications from card types (e.g. a planeswalker enters with loyalty counters,
  # CR 306.5b, 616.1a), entering replacements of permanents already on the battlefield (extra
  # counters on permanents entering under their controller's control, CR 614.1c, 614.12), and the
  # effects of counters on the affected permanent (stun and shield counters, CR 122.1c-d).
  #
  # CR 616.1 lets the affected player (or the affected object's controller) choose the order when
  # several effects apply. The engine applies them in the order that player would always choose:
  # effects that let a permanent stay ("instead remove all +1/+1 counters", a shield counter) before
  # effects that send it elsewhere ("exile it instead"), "+1 counter" bonuses before doubling, and
  # "enters untapped" after every "enters tapped". No pair implemented so far has two orders that
  # each benefit that player, so no decision is asked; a frame will when one does.
  module Replacements
    module_function

    def apply(engine, proposal)
      engine.cast_replacements!(proposal) if proposal.kind == "zone_change" # beam me up, cast riders (Permissions)
      case proposal.kind
      when "zone_change" then zone_change!(engine, proposal)
      when "counters" then putting_counters!(engine, proposal)
      when "draw" then drawing!(engine, proposal)
      when "damage" then preventing!(engine, proposal)
      when "create_token" then creating_token!(engine, proposal)
      end
      Mechanics::Counters.replace!(engine, proposal) unless proposal.data["cancelled"]
      dying!(engine, proposal) if proposal.kind == "zone_change" && !proposal.data["cancelled"]
      proposal
    end

    def zone_change!(engine, proposal)
      return entering!(engine, proposal) if proposal.data["to"] == :battlefield

      destroying!(engine, proposal)
    end

    # The first applicable ability of a battlefield permanent controlled by `player` that responds to
    # `hook` and hasn't modified this event yet (CR 614.5). It is marked as applied.
    def next_controlled(engine, proposal, hook, player)
      found = battlefield_abilities(engine, hook).find do |source, _|
        source.controller == player && !proposal.applied.include?("#{source.id}:#{hook}")
      end
      proposal.applied << "#{found[0].id}:#{hook}" if found
      found
    end

    # "If you would draw a card, draw two cards instead" (CR 614.11). Only one applies to this event;
    # the others apply to each of the draws it becomes (Engine#draw!).
    def drawing!(engine, proposal)
      _, ability = next_controlled(engine, proposal, :replace_draw, proposal.data["player"])
      proposal.data["count"] = ability.amount if ability
    end

    # "If one or more tokens would be created under your control, that many [tokens] are created
    # instead" (CR 614.1a, 111.1).
    def creating_token!(engine, proposal)
      _, ability = next_controlled(engine, proposal, :token_definition, proposal.data["player"])
      proposal.data["token"] = ability.token_definition.id if ability
    end

    # CR 615.1: "prevent all damage that would be dealt to you this turn".
    def preventing!(engine, proposal)
      proposal.data["amount"] = 0 if engine.damage_prevented?(proposal.data["target"])
    end

    # CR 701.8a, 704.5g-h: destroying a permanent, by an effect or for lethal damage / deathtouch.
    DESTROY_REASONS = %w[destroy sba_lethal_damage sba_deathtouch].freeze

    # "If [a permanent] would be destroyed, instead ..." (CR 614.8-style destruction replacements).
    def destroying!(engine, proposal)
      return unless DESTROY_REASONS.include?(proposal.data["reason"])

      obj = engine.object(proposal.data["object"]) # destroyed: on the battlefield (CR 701.8a)
      battlefield_abilities(engine, :replace_destroy).each do |source, ability|
        next if proposal.applied.include?("#{source.id}:replace_destroy") || !ability.replaces?(engine, obj, source)

        proposal.applied << "#{source.id}:replace_destroy"
        proposal.data["cancelled"] = true
        return ability.replace_destroy(engine, obj)
      end
    end

    # "If it would die this turn, exile it instead" (CR 614.1a, 700.4).
    def dying!(engine, proposal)
      data = proposal.data
      return unless data["to"] == :graveyard && engine.state.battlefield.include?(data["object"])
      return unless engine.state.effects.any? { it["kind"] == "exile_if_dies" && it["affected"].include?(data["object"]) }

      data["to"] = :exile
    end

    # Bonus counters from "until end of turn, ... that many plus one of each of those kinds" effects of
    # the permanent's controller (CR 614.1a).
    def counter_bonus(engine, controller)
      engine.state.effects.sum { it["kind"] == "counter_bonus" && it["controller"] == controller ? it["amount"] : 0 }
    end

    # [[source permanent, ability]] for abilities of permanents on the battlefield that respond to `hook`.
    def battlefield_abilities(engine, hook)
      engine.state.battlefield.flat_map do |id|
        source = engine.object(id)
        engine.chars(source).abilities.filter_map { [source, it.ability] if it.ability.respond_to?(hook) }
      end
    end

    # "Put twice that many counters instead" (CR 614.1a) on counters put on a permanent.
    def putting_counters!(engine, proposal)
      obj = engine.object(proposal.data["object"])
      facts = Mechanics::Filters::Facts.new(chars: engine.chars(obj), counters: obj.counters,
                                            token: engine.token?(obj))
      proposal.data["amount"] += counter_bonus(engine, obj.controller) # "that many plus one" first (CR 616.1)
      battlefield_abilities(engine, :doubles?).each do |source, ability|
        next unless ability.doubles?(source, proposal.data["player"], obj.controller, proposal.data["counter"], facts)

        proposal.data["amount"] *= 2
      end
    end

    # CR 614.12-style status the permanent enters with.
    def entering!(engine, proposal)
      obj = engine.object(proposal.data["object"])
      enters = proposal.data["enters"]
      # Self-replacement effects of the entering permanent (CR 614.12: as it would exist on the battlefield,
      # with the face it enters with up, CR 712.9).
      face = engine.entering_face(obj, enters)
      (face || engine.definition(obj)).ability_instances.each do |inst|
        inst.ability.modify_entering(enters) if inst.ability.respond_to?(:modify_entering)
        if inst.ability.respond_to?(:modify_entering_for) # a condition checked for its controller (CR 614.1c)
          inst.ability.modify_entering_for(engine, proposal.data["controller"] || obj.owner, obj.id, enters)
        end
      end
      (face ? face.types : engine.chars(obj).types).each do |type|
        mod = Enjine.registry.fetch(:type, type)
        mod.entering(face || engine.definition(obj), enters) if mod.respond_to?(:entering)
      end
      others_entering!(engine, obj, proposal)
    end

    # Entering replacements of permanents already on the battlefield (CR 614.1c, 614.12).
    def others_entering!(engine, obj, proposal)
      controller = proposal.data["controller"] || obj.owner
      facts = Mechanics::Filters::Facts.new(chars: engine.chars(obj), counters: {}, token: engine.token?(obj))
      enters = proposal.data["enters"]
      battlefield_abilities(engine, :modify_other_entering).each do |source, ability|
        ability.modify_other_entering(enters) if source.id != obj.id && ability.affects_entering?(source, controller, facts)
      end
      # Counters it enters with are put on it by its controller (CR 122.6, 122.6a).
      bonus = counter_bonus(engine, controller)
      enters["counters"].transform_values! { it + bonus } if bonus.positive?
      battlefield_abilities(engine, :doubles?).each do |source, ability|
        enters["counters"].each_key do |kind|
          enters["counters"][kind] *= 2 if ability.doubles?(source, controller, controller, kind, facts)
        end
      end
      engine.chars(obj).subtypes.each do |sub| # e.g. a Saga enters with a lore counter (CR 715.3a)
        mod = Enjine.registry.fetch(:subtype, sub)
        mod.entering(engine.definition(obj), proposal.data["enters"]) if mod.respond_to?(:entering)
      end
      entering_status!(engine, obj, controller, facts, enters)
    end

    # "Lands you control enter untapped" overrides every "enters tapped" (applied last, CR 616.1), and
    # "would enter while you control an attacking creature: instead it enters tapped and attacking".
    def entering_status!(engine, obj, controller, facts, enters)
      battlefield_abilities(engine, :enters_attacking?).each do |source, ability|
        next unless source.id != obj.id && ability.enters_attacking?(engine, source, controller, facts)

        enters["tapped"] = true
        enters["attacking"] = true
      end
      battlefield_abilities(engine, :enters_untapped?).each do |source, ability|
        enters["tapped"] = false if ability.enters_untapped?(source, controller, facts)
      end
    end
  end
end
