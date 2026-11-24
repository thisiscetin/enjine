# frozen_string_literal: true

module Enjine
  module Decisions
    # CR 616.1: the affected player orders the replacement and prevention effects that apply to one damage event
    # (`hit`: "source>recipient"), asked only when orders lead to different results; one choice per result.
    class DamageOrder < Base
      def self.doc
        "Order the effects that apply to damage dealt to you or a permanent you control (CR 616.1): submit one of " \
          '`{type: "order", order: [effect keys], steps: [labels], amount: final damage}` exactly as listed.'
      end

      def self.options(_engine, pending) = pending["choices"].map { it.transform_keys(&:to_sym) }
      def self.submit(engine, pending, option) = engine.damage_order_answer!(pending, option)
    end
    register("damage_order", DamageOrder)
  end
end
