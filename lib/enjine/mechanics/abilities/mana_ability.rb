# frozen_string_literal: true

module Enjine
  module Mechanics
    # "Spend this mana only to cast [quality] spells or activate abilities of [quality] sources" (CR 106.6):
    # a restriction on mana, kept with that mana in the pool. Data:
    #   {"spells": card spec, "abilities": card spec}   at least one; "card" matches every spell or source
    # The spec is matched against the spell being cast or the source of the ability being activated. Mana
    # paid for a cost while a spell or ability resolves (CR 118.12) is neither, so restricted mana can't pay it.
    class SpendOnly
      KEYS = %w[spells abilities].freeze

      attr_reader :data

      def self.build(data, errors, path)
        unless data.is_a?(Hash) && !data.empty? && (data.keys.map(&:to_s) - KEYS).empty?
          errors << "#{path}: must be {\"spells\": card spec, \"abilities\": card spec} (at least one)"
          return nil
        end
        data = data.transform_keys(&:to_s)
        specs = data.to_h { |key, spec| [key, CardSpec.build(spec, errors, "#{path}.#{key}")] }
        new(data, specs)
      end

      # The restriction kept on pool mana (plain data, CR 106.6), rebuilt once per distinct data.
      def self.from_data(data)
        (@cache ||= {})[data] ||= build(data, [], "spend_only")
      end

      def initialize(data, specs)
        @data = Snapshot.deep_copy(data).freeze
        @specs = specs.freeze
        freeze
      end

      # `purpose`: {"spell" => id} for a spell being cast, {"ability" => source id} for an ability being
      # activated, nil for anything else.
      def allows?(engine, purpose)
        return false if purpose.nil?

        spec = purpose.key?("spell") ? @specs["spells"] : @specs["abilities"]
        ref = purpose["spell"] || purpose["ability"]
        obj = ref.is_a?(GameObject) ? ref : engine.state.objects[ref] # a card outside the game is its stand-in
        !spec.nil? && !obj.nil? && spec.match?(engine, obj)
      end

      def to_s
        parts = []
        parts << "cast #{@specs["spells"]} spells" if @specs["spells"]
        parts << "activate abilities of #{@specs["abilities"]}s" if @specs["abilities"]
        "spend this mana only to #{parts.join(" or ")}"
      end
    end

    module Abilities
      # Activated mana ability (CR 605). Resolves immediately, never uses the stack. It adds the fixed
      # mana in `produce` (`amount` times), or `amount` mana of colors chosen as it is activated
      # (CR 605.3b, 106.1a): all of one color (`color: "any_one"`) or each separately (`"any"`).
      class ManaAbility < Primitive
        COLORS = Mana::COLORS.map(&:to_s).freeze
        CHOICES = %w[any_one any].freeze

        primitive :ability, :mana,
                  description: "An activated mana ability: pay the cost, add the mana to your mana pool " \
                               "immediately. It does not use the stack and can be activated whenever you " \
                               "have priority. `produce`: the fixed mana (`amount` times). Or `color`: " \
                               "`amount` mana (default 1) of one color you choose as you activate it " \
                               "(`\"any_one\"`) or in any combination of colors (`\"any\"`); `colors` limits " \
                               "the choice. `spend_only` restricts how the mana can be spent.",
                  rules: %w[605.1a 605.3a 605.3b 106.1a 106.4 106.6],
                  params: { "cost" => "list of costs (e.g. [\"tap\"])",
                            "produce" => "mana symbols added, e.g. \"{G}\" or \"{C}{C}\"",
                            "amount" => "amount (default 1; with produce: how many times)",
                            "color" => CHOICES.join(" | "), "colors" => "list of colors to choose from (default all five)",
                            "spend_only" => "{\"spells\": card spec, \"abilities\": card spec}" },
                  example: { "mana" => { "cost" => ["tap"], "produce" => "{C}" } }

        attr_reader :costs, :produce, :color, :colors, :amount, :spend_only

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost produce amount color colors spend_only], errors, path)
          costs = build_costs(Mechanics.fetch_param(params, :cost), errors, path)
          raw = Mechanics.fetch_param(params, :produce)
          color = Mechanics.fetch_param(params, :color)
          errors << "#{path}: needs exactly one of produce, color" unless raw.nil? ^ color.nil?
          produce = raw && Mana.parse_produce(raw, errors, "#{path}.produce")
          errors << "#{path}.color: must be one of #{CHOICES.join(", ")}" if color && !CHOICES.include?(color)
          raw_amount = Mechanics.fetch_param(params, :amount)
          amount = raw_amount.nil? ? nil : Amount.build(raw_amount, errors, "#{path}.amount", targets_count: 0)
          raw_spend = Mechanics.fetch_param(params, :spend_only)
          spend_only = raw_spend.nil? ? nil : SpendOnly.build(raw_spend, errors, "#{path}.spend_only")
          new(costs.compact.freeze, produce, color: color, colors: build_colors(params, color, errors, path),
                                             amount: amount, spend_only: spend_only)
        end

        def self.build_costs(raw, errors, path)
          return raw.each_with_index.map { |c, i| Mechanics.build_entry(:cost, c, errors, "#{path}.cost[#{i}]") } if
            raw.is_a?(Array) && !raw.empty?

          errors << "#{path}.cost: must be a non-empty list"
          []
        end

        def self.build_colors(params, color, errors, path)
          raw = Mechanics.fetch_param(params, :colors)
          return COLORS if raw.nil?
          return raw.map(&:to_s).freeze if color && raw.is_a?(Array) && raw.size >= 2 && (raw - COLORS).empty? && raw.uniq == raw

          errors << "#{path}.colors: must list two or more colors (W U B R G), with color"
          COLORS
        end

        def initialize(costs, produce, color: nil, colors: COLORS, amount: nil, spend_only: nil)
          super()
          @costs = costs
          @produce = produce
          @color = color
          @colors = colors
          @amount = amount
          @spend_only = spend_only
          list = costs.select(&:mana?).map(&:mana_cost)
          @mana_cost = list.empty? ? nil : Mana.sum_costs(list)
          freeze
        end

        def mana_ability? = true
        def try_effects = []
        def kind = :mana
        def allowed_types = nil

        # A mana cost ("{1}, {T}: Add …") is paid from the mana already in the pool (CR 605.3a, 601.2g-h).
        def activatable?(engine, object)
          costs.all? { |c| c.payable?(engine, object) } && (mana_cost.nil? || engine.pool_covers?(object.controller, mana_cost))
        end

        # The sum of its mana costs, or nil.
        attr_reader :mana_cost

        # Whether the mana is chosen as it's activated (so each activation option names it).
        def choice? = !color.nil?

        # How much mana (or how many times `produce`) one activation adds now.
        def count(engine, object)
          return 1 if amount.nil?

          [amount.value(engine, EffectContext.new(object.controller, object.id, nil, [])), 0].max
        end

        # Every mana an activation could add now, each as a list of pool types (CR 605.3b). One entry
        # without a choice; with `any_one` one per color; with `any` one per combination of colors.
        def outcomes(engine, object)
          n = count(engine, object)
          return [(produce || []) * n] unless choice?
          return [[]] if n.zero?

          picks = colors.map(&:to_sym)
          return picks.map { [it] * n } if color == "any_one"

          picks.repeated_combination(n).map(&:freeze)
        end

        def to_s
          what = if produce then "Add #{produce.map { "{#{it}}" }.join}#{" #{amount} times" if amount}"
                 else "Add #{amount || 1} mana of #{color == "any_one" ? "any one color" : "any combination of colors"}" \
                   "#{" (#{colors.join("/")})" unless colors == COLORS}"
                 end
          "#{costs.join(", ")}: #{what}.#{" #{spend_only.to_s.capitalize}." if spend_only}"
        end
      end
    end
  end
end
