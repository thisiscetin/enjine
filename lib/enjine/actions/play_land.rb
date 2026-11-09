# frozen_string_literal: true

module Enjine
  module Actions
    # CR 305.1-305.2, 116.2a: playing a land is a special action — own main phase,
    # empty stack, while holding priority, one land per turn plus any additional land plays
    # (Engine#land_plays_allowed).
    # A land outside the hand (the top of the library, exile) can be played when an effect allows it;
    # `via` names the permission (CR 305.1: "from the zone it was in").
    class PlayLand
      def self.doc
        '`{type: "play_land", object: id}` — special action: your main phase, empty stack, one land per turn ' \
          "plus additional land plays (CR 305.1, 305.2). With `via`: a land from another zone that an effect lets you play."
      end

      def self.options(engine, index)
        return [] unless engine.sorcery_timing?(index) && engine.land_play_available?(index)

        engine.player(index).hand.filter_map do |id|
          { type: "play_land", object: id } if engine.chars(id).land?
        end + engine.permission_land_options(index)
      end

      def self.perform(engine, index, option)
        engine.use_play_method!(engine.play_method(index, option[:object], option[:via])) if option[:via]
        engine.player(index).lands_played += 1
        if engine.entering_choice(option[:object])
          engine.state.frames << { "type" => "play_land", "object" => option[:object], "player" => index }
          return engine.ask!(nil)
        end
        engine.move!(option[:object], :battlefield, controller: index, reason: "play_land")
        engine.action_taken!(index) # CR 117.3c: the player receives priority again
      end

      # The play_land frame: ask the "as this enters" choice, then put the land onto the battlefield.
      def self.step(engine, frame)
        return engine.ask_enter_choice!(frame["object"], frame["player"]) unless frame["enter"]

        enters = engine.enters_from_answer(frame["object"], frame)
        engine.pay_entering_life!(frame["player"], frame)
        engine.move!(frame["object"], :battlefield, controller: frame["player"], reason: "play_land", enters: enters)
        engine.action_taken!(frame["player"])
        :done
      end
    end
    register("play_land", PlayLand)
  end
end
