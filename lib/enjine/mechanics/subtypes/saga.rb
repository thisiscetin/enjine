# frozen_string_literal: true

require_relative "../abilities/stack_abilities"
require_relative "../triggers/triggers"

module Enjine
  module Mechanics
    module Subtypes
      # The Saga enchantment type (CR 715).
      class Saga < Primitive
        primitive :subtype, :saga,
                  description: "Enchantment type. A Saga enters with a lore counter; as its controller's precombat " \
                               "main phase begins, they put another lore counter on it. Each lore counter added can " \
                               "trigger its chapter abilities. Once its lore counters reach its final chapter number " \
                               "and no chapter ability of it is waiting to resolve, its controller sacrifices it.",
                  rules: %w[715.3a 715.3c 505.4 715.4 704.5s],
                  example: { "types" => ["enchantment"], "subtypes" => ["saga"],
                             "abilities" => [{ "chapter" => { "chapter" => 1, "effects" => [{ "draw" => { "amount" => 1 } }] } }] }

        def self.applies_to = [:enchantment]

        # CR 715.3a: "This Saga enters with a lore counter on it" (a replacement effect, CR 614.1c).
        def self.entering(_definition, enters)
          enters["counters"]["lore"] = enters["counters"].fetch("lore", 0) + 1
        end
      end
    end

    module Triggers
      # The trigger condition of a chapter ability (CR 715.2b): one or more lore counters are put on
      # this Saga and their number goes from less than N to at least N. Entering with lore counters
      # counts as having them put on it (CR 122.6).
      class ChapterTrigger
        attr_reader :chapter

        def initialize(chapter)
          @chapter = chapter
          freeze
        end

        def watches?(event) = event.is_a?(Events::CountersChanged) || event.is_a?(Events::ZoneChanged)
        def leaves_battlefield? = false

        def match?(engine, event, source)
          if event.is_a?(Events::CountersChanged)
            event.object == source["id"] && event.counter == "lore" && event.from < chapter && event.to >= chapter
          else
            entered = event.to == "battlefield" && event.new_id == source["id"]
            entered && engine.state.objects[event.new_id].counters.fetch("lore", 0) >= chapter
          end
        end

        def to_s = "Chapter #{chapter}"
      end
    end

    module Abilities
      # A chapter ability "{rN} — [effect]" (CR 715.2): a triggered ability of a Saga. Write
      # "{rN1}, {rN2} — [effect]" as one chapter ability per number (CR 715.2c).
      class ChapterAbility < StackAbility
        primitive :ability, :chapter,
                  description: "A Saga's chapter ability: triggers when lore counters put on it bring their number " \
                               "from below `chapter` to at least `chapter`. Its targets are chosen as it's put on the " \
                               "stack. A Saga's final chapter number is its greatest `chapter`.",
                  rules: %w[715.2 715.2b 715.2c 715.2d 122.6],
                  params: { "chapter" => "integer >= 1 (the chapter symbol's number)", "targets" => "list of target filters",
                            "effects" => "list of effects", "modes" => "optional modes, as for a spell" },
                  example: { "chapter" => { "chapter" => 2, "effects" => [{ "gain_life" => { "amount" => 3 } }] } }

        attr_reader :chapter, :trigger

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[chapter] + BODY_KEYS, errors, path)
          chapter = Mechanics.integer_param(params, :chapter, errors, path, min: 1)
          new(**parse_body(params, errors, path), chapter: chapter)
        end

        def initialize(chapter:, **)
          @chapter = chapter
          @trigger = Triggers::ChapterTrigger.new(chapter)
          super(**)
        end

        def kind = :triggered
        def allowed_types = [:enchantment]
        def condition = nil
        def condition_met?(*, **) = true
        def to_s = "Chapter #{chapter} — #{effects_text}"
      end
    end
  end
end
