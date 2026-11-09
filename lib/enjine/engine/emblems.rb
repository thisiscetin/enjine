# frozen_string_literal: true

module Enjine
  class Engine
    # Emblems (CR 114): objects in the command zone with abilities and no other characteristics. An emblem
    # is a GameObject of kind "emblem" whose `card` is the card whose effect created it and whose `ability`
    # is that effect's reference; its abilities are part of that card's data (Effects::CreateEmblem), so it
    # needs no card of its own. It never leaves the command zone. Its abilities function there (CR 114.4):
    # triggered abilities (Engine::Triggers#trigger_sources), static abilities (#static_sources) and
    # player rules (#player_rule_statics).
    module Emblems
      # CR 114.1, 114.2: `index` gets an emblem; returns it.
      def create_emblem!(index, card, ref)
        obj = create_object(card, index, :command)
        obj.kind = "emblem"
        obj.ability = ref
        state.command << obj.id
        emit Events::EmblemCreated.new(player: name(index), object: obj.id, card: card)
        obj
      end

      # CR 114.3: an emblem has no characteristics other than its abilities. They are referenced as granted
      # abilities ("granted:<card>:<ref>:<j>"), so a triggered one resolves from the creating card's data.
      def emblem_characteristics(obj)
        abilities = catalog.fetch(obj.card).effect_granted(obj.ability).map do |inst|
          AbilityInstance.new(ref: "granted:#{obj.card}:#{inst.ref}", ability: inst.ability)
        end
        Enjine::Characteristics::FACE_DOWN.with(name: "Emblem", abilities: abilities.freeze)
      end

      # The emblems in the command zone, as objects.
      def emblems = (state.command || []).map { object(it) }
    end

    include Emblems
  end
end
