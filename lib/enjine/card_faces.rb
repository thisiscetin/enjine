# frozen_string_literal: true

module Enjine
  class CardDefinition
    # Cards with more than one set of characteristics, written as
    #
    #   {"name": "Alfa // Bravo", "layout": "transform", "faces": [{...front...}, {...back...}]}
    #
    # where each face is a complete card block (name, mana_cost, types, abilities, ...). `name` is optional
    # and, when given, must be "<front name> // <back name>". The layouts:
    #
    #   transform  a nonmodal double-faced card (CR 712.2): cast and played front face up, it can transform
    #              (CR 701.27) or enter transformed (CR 712.11a)
    #   modal      a modal double-faced card (CR 712.3): its owner chooses the face to cast or play (CR 712.8b,
    #              712.9); a modal card may also transform (CR 712.3)
    #   adventure  an adventurer card (CR 716): faces[1] is the Adventure, an instant or sorcery
    #   omen       an omen card (CR 721): faces[1] is the Omen, an instant or sorcery
    #   prepare    a preparation card (CR 723): faces[1] is the prepare spell, an instant or sorcery
    #   meld       a meld card (CR 713): faces[1] is the combined back face of its meld pair, the same on both
    #              cards; it's up only on the melded permanent (CR 713.1b, 713.5c; effect `meld`)
    #
    # The definition itself has the front face's (faces[0]'s) characteristics, which are the card's in
    # every zone where no other face is up (CR 712.6a, 716.4, 721.4, 723.4). Every other face is a
    # CardDefinition with the id "<card id>/<index>"; a game object whose `card` names a face has that
    # face up (see Engine::Faces).
    module Faces
      LAYOUTS = %w[transform modal adventure omen prepare meld].freeze
      DOUBLE_FACED = %w[transform modal].freeze
      # Layouts whose faces[1] is a spell the card can be (CR 716.2, 721.2, 723.2).
      SPELL_FACE = { "adventure" => "adventure", "omen" => "omen", "prepare" => nil }.freeze
      FACED_KEYS = %w[name layout faces].freeze
      FACE_SEPARATOR = "/"

      # A face's error list: it holds the face's own messages (so validation reading them back sees the
      # same paths as for a single-faced card) and adds each to the card's errors under the face's path
      # ("faces[1].types: ...").
      class PathErrors < Array
        def initialize(errors, path)
          super()
          @errors = errors
          @path = path
        end

        def <<(message)
          @errors << "#{@path}.#{message}"
          super
        end
      end

      # The layout of the card this face belongs to (nil for a single-faced card).
      def layout = @front ? @front.layout : @layout

      # Every face, front first ([self] for a single-faced card).
      def faces = @front ? @front.faces : (@faces || [self])
      def face(index) = faces.fetch(index)
      def other_faces = @front || @faces.nil? ? [] : @faces.drop(1)

      # 0 for the front face (and a single-faced card).
      def face_index = @face_index || 0

      # The card's own definition: the front face.
      def card = @front || self

      # A double-faced card (CR 712.1), whose faces can transform (CR 712.7).
      def double_faced? = DOUBLE_FACED.include?(layout)

      # The face to turn to when this face transforms (CR 701.27a).
      def other_face = faces[1 - face_index]

      # "Alfa // Bravo" for a card with faces.
      def full_name = faces.map(&:name).join(" // ")

      private

      def read_faces(card, errors, token_id)
        (card.keys - FACED_KEYS).each do |key|
          errors << "#{key}: a card with faces keeps its characteristics in each face (allowed beside faces: " \
                    "#{(FACED_KEYS + PRINT_KEYS).join(", ")})"
        end
        @layout = card["layout"]
        errors << "layout: required with faces, one of #{LAYOUTS.join(", ")}" unless LAYOUTS.include?(@layout)
        list = card["faces"]
        unless list.is_a?(Array) && list.size == 2 && list.all?(Hash)
          errors << "faces: must be a list of two faces, each a card object"
          list = Array(list).grep(Hash).first(2)
          list << {} while list.size < 2
        end
        front, back = list.map { it.transform_keys(&:to_s) }
        read_card(front, prefixed(errors, "faces[0]"), token_id)
        @faces = [self, CardDefinition.new(back, prefixed(errors, "faces[1]"), face: [self, 1])].freeze
        validate_faces(card, errors)
        @source = deep_freeze({ "name" => full_name, "layout" => @layout,
                                "faces" => [normalize(front), @faces[1].to_h] })
      end

      def prefixed(errors, path) = PathErrors.new(errors, path)

      def validate_faces(card, errors)
        name = card["name"]
        errors << "name: must be #{full_name.inspect} (the faces' names joined by \" // \")" unless name.nil? || name == full_name
        errors << "faces[1].types: a melded permanent is a permanent (CR 713.1a)" if @layout == "meld" && !@faces[1].permanent?
        return unless SPELL_FACE.key?(@layout)

        spell = @faces[1]
        errors << "faces[0].types: the main face of a #{@layout} card is a permanent card" unless permanent?
        unless spell.type?(:instant) || spell.type?(:sorcery)
          errors << "faces[1].types: the #{@layout} face is an instant or sorcery (CR 716.2, 721.2, 723.2)"
        end
        subtype = SPELL_FACE[@layout]
        return if subtype.nil? || spell.subtypes.include?(subtype.to_sym)

        errors << "faces[1].subtypes: an #{@layout} face has the spell type #{subtype} (CR 205.3k)"
      end
    end
  end
end
