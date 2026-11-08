# frozen_string_literal: true

module Enjine
  # A state change about to happen (CR 614.1). Mutations are proposed first, passed
  # through replacement effects, then executed, so "enters tapped", "if it would die,
  # exile it instead" and damage prevention can modify them before they occur.
  #
  # kind: "zone_change" | "damage" | "life" | "draw" | "counters"
  # data: plain Hash describing the change
  # applied: ids of replacement effects already applied (each applies once, CR 614.5)
  Proposal = Struct.new(:kind, :data, :applied)

  # The replacement-effect pass (CR 614-616).
  #
  # Today it applies the rules' own entering modifications from card types (e.g. a
  # planeswalker enters with loyalty counters, CR 306.5b). Replacement effects from
  # card abilities plug in here: each yields a candidate with an id and #apply!(proposal);
  # when two or more apply to one proposal, the affected player chooses the order (CR 616.1),
  # which will be asked through a frame (see Enjine::Frames).
  module Replacements
    module_function

    def apply(engine, proposal)
      entering!(engine, proposal) if proposal.kind == "zone_change" && proposal.data["to"] == :battlefield
      proposal
    end

    # CR 614.12-style status the permanent enters with, from its card types.
    def entering!(engine, proposal)
      obj = engine.object(proposal.data["object"])
      engine.chars(obj).types.each do |type|
        mod = Enjine.registry.fetch(:type, type)
        mod.entering(engine.definition(obj), proposal.data["enters"]) if mod.respond_to?(:entering)
      end
    end
  end
end
