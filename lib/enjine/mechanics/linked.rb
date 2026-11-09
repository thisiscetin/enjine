# frozen_string_literal: true

module Enjine
  module Mechanics
    # Linked abilities (CR 607.2a, 406.6): cards an ability of a source exiled are kept in the source's
    # memory, so another ability of the same object can name "the cards exiled with it". A source that
    # changes zones is a new object (CR 400.7) with no memory, so the link ends with it. Also the last
    # known controller of objects a resolving effect moved (CR 608.2h), for {"controller_of": selector}.
    module Linked
      EXILED = "exiled_with"
      UNTIL_LEAVES = "until_leaves"
      LKI = "lki"

      # Cards still in exile that an ability of `source` exiled (CR 607.2a). Once the source has left the
      # battlefield, its triggered ability remembers them ("when this leaves, return the exiled card").
      def self.exiled_with(engine, source, ctx = nil)
        obj = engine.state.objects[source]
        ids = obj ? obj.memory[EXILED] : ctx && engine.state.objects[ctx.object]&.memory&.dig("source_lki", EXILED)
        Array(ids).select { engine.state.exile.include?(it) }
      end

      # Called by a resolving effect before it moves an object: who controlled it (CR 608.2h), kept on the
      # resolving spell or ability. Only a permanent has a controller other than its owner.
      def self.remember!(engine, ctx, id)
        obj = engine.object(id)
        (engine.object(ctx.object).memory[LKI] ||= {})[id] = obj.controller if obj.zone == :battlefield
      end

      # An amount whose {"count": selector} may name earlier effects' results ("up to that many").
      def self.amount(raw, errors, path, targets_count, results_count)
        return Amount.build(raw, errors, path, targets_count: targets_count) unless raw.is_a?(Hash) && raw.keys.map(&:to_s) == ["count"]

        Amount.new("count", Selector.build(raw.values.first, errors, "#{path}.count", targets_count: targets_count,
                                                                                      results_count: results_count))
      end
    end

    class Condition
      # Whether the referenced objects (e.g. the cards exiled with a source, CR 607.2a) have at least one
      # card type in common. No objects share nothing.
      class ShareCardType
        def self.build(data, errors, path, targets_count)
          Mechanics.check_keys(data, %w[share_card_type], errors, path)
          new(Selector.build(data["share_card_type"], errors, "#{path}.share_card_type", targets_count: targets_count))
        end

        def initialize(selector)
          @selector = selector
          freeze
        end

        def true?(engine, ctx)
          objects = @selector.resolve(engine, ctx).filter_map { engine.state.objects[it] }
          !objects.empty? && !objects.map { engine.chars(it).types }.reduce(:&).empty?
        end

        def to_s = "#{@selector} share a card type"
      end
    end
  end
end
