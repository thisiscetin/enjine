# frozen_string_literal: true

module Enjine
  module Decisions
    # A choice an effect asks for while it resolves (scry, surveil, discard, ...). The pending
    # decision carries a human-readable `prompt` and the exact `choices`.
    class EffectChoice < Base
      def self.doc
        "A choice made while an effect resolves (scry, surveil, discard...): submit one of the " \
          "`choices` exactly as listed; `prompt` describes it."
      end

      def self.options(_engine, pending) = pending["choices"].map { it.transform_keys(&:to_sym) }
      def self.submit(engine, _pending, option) = engine.effect_answer!(option)

      # Which library card went where is hidden from other players; discards are public anyway.
      def self.redact(option, viewer_is_decider) = viewer_is_decider ? option : option.except(:object)
    end
    register("effect_choice", EffectChoice)
  end
end
