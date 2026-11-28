# frozen_string_literal: true

module Enjine
  module Mechanics
    class Condition
      # Void (an ability word, CR 207.2c, of Edge of Eternities): "if a nonland permanent left the battlefield this
      # turn or a spell was warped this turn". `{"void": true}`; `{"void": false}` is its negation. Any player's
      # permanent counts, tokens too (CR 400.7, 111.7), and so does a permanent a warp's delayed trigger exiled;
      # "warped" is a spell cast for its warp cost, by any player (CR 702.185c).
      class Void
        DATA = { "any" => [{ "amount" => { "left_this_turn" => { "each" => { "permanent" => { "not" => ["land"] } } } },
                             "at_least" => 1 },
                           { "cast_with_this_turn" => "warp" }] }.freeze

        def self.build(data, errors, path)
          Mechanics.check_keys(data, %w[void], errors, path)
          wanted = data["void"]
          errors << "#{path}.void: must be true or false" unless [true, false].include?(wanted)
          new(Condition.build(DATA, errors, path), wanted != false)
        end

        def initialize(test, wanted)
          @test = test
          @wanted = wanted
          freeze
        end

        def true?(engine, ctx) = @test.true?(engine, ctx) == @wanted

        def to_s = "#{"not " unless @wanted}void (a nonland permanent left the battlefield this turn or a spell was warped this turn)"
      end
    end
  end
end
