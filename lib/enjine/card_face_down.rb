# frozen_string_literal: true

module Enjine
  class CardDefinition
    # The characteristics a face-down spell or permanent has (CR 708.2): a 2/2 creature with no text, no name, no
    # subtypes and no mana cost (manifest, CR 701.40a; morph, CR 702.37a; CR 708.2a), or the same with ward {2}
    # (cloak, CR 701.58a; disguise, CR 702.168a). They aren't cards of any catalog: every catalog knows them
    # (Catalog#fetch), and a face-down object's `card` names one while the card it really is waits in its memory
    # (Engine::FaceDownPermanents).
    module FaceDownCards
      PLAIN = "face_down_2_2"
      WARD = "face_down_ward"
      DATA = {
        PLAIN => { "name" => "", "types" => ["creature"], "power" => 2, "toughness" => 2 },
        WARD => { "name" => "", "types" => ["creature"], "power" => 2, "toughness" => 2,
                  "abilities" => [{ "ward" => { "cost" => [{ "mana" => "{2}" }] } }] }
      }.freeze

      module_function

      def id?(id) = DATA.key?(id)

      # The definition with that id, or nil.
      def fetch(id)
        return nil unless id?(id)

        (@definitions ||= {})[id] ||= CardDefinition.new(DATA.fetch(id).dup, [], token_id: id)
      end
    end
  end
end
