# frozen_string_literal: true

module Enjine
  module Actions
    # CR 116.2b, 708.7: turning a face-down permanent you control face up is a special action, taken any time you
    # have priority: show its cost and pay it (a "pay" frame, which can be cancelled), then you get priority again
    # (CR 116.3). `via`: "mana_cost" (a manifested or cloaked creature card, CR 701.40b, 701.58b), "morph" (CR 702.37e)
    # or "disguise" (CR 702.168d).
    class TurnFaceUp
      def self.doc
        '`{type: "turn_face_up", object: id, via: "mana_cost" | "morph" | "disguise"}` — turn a face-down permanent you ' \
          "control face up by paying its mana cost (a manifested or cloaked creature card) or its morph or disguise " \
          "cost (a special action, any time you have priority, CR 116.2b)."
      end

      def self.options(engine, index) = engine.face_up_options(index)

      def self.perform(engine, index, option)
        cost = engine.face_up_costs(engine.object(option[:object])).fetch(option[:via])
        engine.begin_payment!(index, cost, option[:object], special: { "object" => option[:object], "face_up" => option[:via] })
      end
    end
    register("turn_face_up", TurnFaceUp)
  end
end
