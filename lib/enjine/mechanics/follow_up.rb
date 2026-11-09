# frozen_string_literal: true

module Enjine
  module Mechanics
    # Effects that happen right after a replacement or prevention effect applies: "prevent that damage and
    # put that many +1/+1 counters on him" (CR 615.5), "instead exile it and you gain 2 life" (CR 614.1a), and
    # "exile it instead. When you do, ..." (a reflexive_trigger among them, CR 603.12). A `then` list of
    # effects that need no choice. They see {"triggering": "amount"} (the damage prevented), "object" (the
    # damage source, or the card exiled instead) and "player" (that object's controller).
    #
    # The FollowUp is one of its card's nested effects, so CardDefinition#ability finds its effects by `ref`;
    # a replacement names it in the event it modifies ("follow_ups") and the engine runs it once the event
    # is done (Engine::FollowUps).
    class FollowUp
      Effects = Data.define(:effects) # what CardDefinition#ability(ref) returns

      attr_reader :ref, :delayed_ability

      def self.build(params, errors, path)
        raw = Mechanics.fetch_param(params, :then)
        return nil if raw.nil?

        effects = Abilities::StackAbility.parse_effects({ "then" => raw }, errors, path, 0, key: :then)
        errors << "#{path}.then: needs at least one effect" if raw.is_a?(Array) && raw.empty?
        new("then:#{path}", effects)
      end

      def initialize(ref, effects)
        @ref = ref
        @delayed_ability = Effects.new(effects: effects)
        freeze
      end

      def effects = delayed_ability.effects
      def nested_effects = effects
      def try_effects = []
      def to_s = effects.join(", ")

      # The entry a replacement adds to the event's "follow_ups": what runs it later, as plain data.
      def entry(card, controller, source, facts)
        { "card" => card, "ref" => ref, "controller" => controller,
          "source" => source, "facts" => facts.compact }
      end
    end
  end
end
