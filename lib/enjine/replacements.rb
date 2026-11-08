# frozen_string_literal: true

module Enjine
  # A state change about to happen (CR 614.1). Mutations are proposed first, passed
  # through replacement effects, then executed, so "enters tapped", "if it would die,
  # exile it instead" and damage prevention can modify them before they occur.
  #
  # kind: "zone_change" | "damage" | "life" | "draw" | "counters" | "untap"
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
  # When two or more effects could be ordered differently, the affected player will choose the
  # order (CR 616.1) through a frame (see Enjine::Frames).
  module Replacements
    module_function

    def apply(engine, proposal)
      entering!(engine, proposal) if proposal.kind == "zone_change" && proposal.data["to"] == :battlefield
      putting_counters!(engine, proposal) if proposal.kind == "counters"
      Mechanics::Counters.replace!(engine, proposal)
      proposal
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
                                            token: engine.catalog.fetch(obj.card).token?)
      battlefield_abilities(engine, :doubles?).each do |source, ability|
        next unless ability.doubles?(source, proposal.data["player"], obj.controller, proposal.data["counter"], facts)

        proposal.data["amount"] *= 2
      end
    end

    # CR 614.12-style status the permanent enters with.
    def entering!(engine, proposal)
      obj = engine.object(proposal.data["object"])
      enters = proposal.data["enters"]
      # Self-replacement effects of the entering permanent (CR 614.12: as it would exist on the battlefield).
      engine.definition(obj).ability_instances.each do |inst|
        inst.ability.modify_entering(enters) if inst.ability.respond_to?(:modify_entering)
      end
      engine.chars(obj).types.each do |type|
        mod = Enjine.registry.fetch(:type, type)
        mod.entering(engine.definition(obj), enters) if mod.respond_to?(:entering)
      end
      others_entering!(engine, obj, proposal)
    end

    # Entering replacements of permanents already on the battlefield (CR 614.1c, 614.12).
    def others_entering!(engine, obj, proposal)
      controller = proposal.data["controller"] || obj.owner
      defn = engine.definition(obj)
      facts = Mechanics::Filters::Facts.new(chars: defn.printed_characteristics, counters: {}, token: defn.token?)
      enters = proposal.data["enters"]
      battlefield_abilities(engine, :modify_other_entering).each do |source, ability|
        ability.modify_other_entering(enters) if source.id != obj.id && ability.affects_entering?(source, controller, facts)
      end
      # Counters it enters with are put on it by its controller (CR 122.6, 122.6a).
      battlefield_abilities(engine, :doubles?).each do |source, ability|
        enters["counters"].each_key do |kind|
          enters["counters"][kind] *= 2 if ability.doubles?(source, controller, controller, kind, facts)
        end
      end
    end
  end
end
