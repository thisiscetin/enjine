# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # A choice between costs: "behold a Goblin or pay {2}", "sacrifice an artifact or discard a nonland card"
      # (CR 118.3, 601.2b). Which one will be paid is announced while casting or activating, before X and the
      # total cost (CR 601.2b, 601.2f, 602.2b): the `choose_cost_option` decision. From then on the chosen cost
      # stands in its place. While resolving (`pay`, ward) the payer chooses as they pay (CR 118.12).
      class OneOf < Primitive
        primitive :cost, :one_of,
                  description: "Pay one of the listed costs (two or more), chosen as the spell or ability is cast or " \
                               "activated (the `choose_cost_option` decision) or, for `pay` and ward, as it is paid. " \
                               "A cost that can't be paid can't be chosen.",
                  rules: %w[118.3 601.2b 601.2f 602.2b 118.12],
                  params: { "(list)" => "two or more costs" },
                  example: { "one_of" => [{ "behold" => { "card" => { "subtypes" => ["goblin"] } } }, { "mana" => "{2}" }] }

        attr_reader :options

        def self.scalar_params? = true

        def self.build(params, errors, path, **)
          unless params.is_a?(Array) && params.size >= 2
            errors << "#{path}: must be a list of at least two costs"
            return new([])
          end
          options = params.each_with_index.filter_map { |c, i| Mechanics.build_entry(:cost, c, errors, "#{path}[#{i}]") }
          errors << "#{path}: a one_of can't contain another one_of" if options.any?(OneOf)
          new(options)
        end

        def initialize(options)
          super()
          @options = options.freeze
          freeze
        end

        def mana? = false

        # Some option could be paid (a mana option is checked against the total cost by the engine).
        def payable?(engine, object) = options.any? { it.mana? || it.payable?(engine, object) }
        # Each option as text: "Behold a Goblin", "Pay {2}".
        def option_texts = options.map { it.mana? ? "Pay #{it}" : it.to_s }
        def to_s = option_texts.each_with_index.map { |text, i| i.zero? ? text : text.sub(/\A\w/, &:downcase) }.join(" or ")
      end
    end
  end
end
