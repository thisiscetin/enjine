# frozen_string_literal: true

module Enjine
  module Decisions
    # CR 704.5j: choose which of your same-named legendary permanents to keep.
    class LegendRule < Base
      def self.doc
        'Keep one of your legendary permanents named `name`: `{type: "keep", object: id}`; the others go ' \
          "to the graveyard (CR 704.5j)."
      end

      def self.options(engine, _pending)
        frame = engine.state.frames.rfind { it["type"] == "legend_rule" }
        engine.legend_candidates(frame).map { { type: "keep", object: it } }
      end

      def self.submit(engine, _pending, option) = engine.keep_legend!(option[:object])
    end
    register("legend_rule", LegendRule)
  end
end
