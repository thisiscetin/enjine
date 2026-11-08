# frozen_string_literal: true

module Enjine
  module Actions
    # CR 117.3d: pass priority.
    class Pass
      def self.doc
        '`{type: "pass"}` — pass priority. When all players pass in succession with an empty stack, the step ends (CR 117.4).'
      end

      OPTION = { type: "pass" }.freeze

      def self.options(_engine, _index) = [OPTION]
      def self.perform(engine, index, _option) = engine.pass_priority!(index)
    end
    register("pass", Pass)
  end
end
