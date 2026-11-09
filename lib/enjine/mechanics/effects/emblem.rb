# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "You get an emblem with '...'" (CR 114.1-114.4): each referenced player gets an emblem in the command
      # zone with the `abilities`. They are part of this card's data, referenced "<this effect's ref>:<j>"
      # (CardDefinition#effect_granted), and work from the command zone for the rest of the game (Engine::Emblems).
      class CreateEmblem < Effect
        KINDS = %i[triggered static player_rule].freeze

        primitive :effect, :create_emblem,
                  description: "Each referenced player (default you) gets an emblem with the `abilities` (triggered, " \
                               "static or player_rule abilities). An emblem is in the command zone for the rest of the " \
                               "game; its abilities work there, and \"this emblem\" is the source of what they do.",
                  rules: %w[114.1 114.2 114.3 114.4 113.6p],
                  params: { "abilities" => "list of triggered, static or player_rule abilities", "to" => "selector" },
                  example: { "create_emblem" => { "abilities" => [
                    { "static" => { "affects" => { "each" => "creature", "controller" => "you" },
                                    "pump" => { "power" => 2, "toughness" => 2 } } }
                  ] } }

        attr_reader :ref, :granted_abilities

        def self.keys = %w[abilities to if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @ref = "emblem:#{path}"
          list = Mechanics.list_param(params, :abilities, errors, path)
          errors << "#{path}.abilities: needs at least one ability" if list.empty?
          @granted_abilities = list.each_with_index.filter_map do |entry, j|
            ability = Mechanics.build_entry(:ability, entry, errors, "#{path}.abilities[#{j}]")
            next ability if ability.nil? || KINDS.include?(ability.kind)

            errors << "#{path}.abilities[#{j}]: an emblem's abilities are #{KINDS.join(", ")} abilities"
            nil
          end.freeze
        end

        def nested_effects = granted_abilities.flat_map(&:try_effects)

        def apply(engine, ctx)
          card = engine.object(ctx.object).card
          players(engine, ctx).each { engine.create_emblem!(it, card, ref) }
        end

        def to_s = "gets an emblem with \"#{granted_abilities.join("; ")}\" → #{to}"
      end
    end
  end
end
