# frozen_string_literal: true

module Enjine
  module Actions
    # CR 305.1-305.2, 116.2a: playing a land is a special action — own main phase,
    # empty stack, while holding priority, one land per turn plus any additional land plays
    # (Engine#land_plays_allowed).
    # A land outside the hand (the top of the library, exile) can be played when an effect allows it;
    # `via` names the permission (CR 305.1: "from the zone it was in"); a land outside the game is named by
    # its outside key (Engine::Permissions#outside_key) and brought in as it's played (CR 400.11b).
    class PlayLand
      def self.doc
        '`{type: "play_land", object: id}` — special action: your main phase, empty stack, one land per turn ' \
          "plus additional land plays (CR 305.1, 305.2). With `via`: a land from another zone that an effect lets you play. " \
          "With `face: 1`: a modal double-faced card played with its land back face up (CR 712.9)."
      end

      def self.options(engine, index)
        return [] unless engine.sorcery_timing?(index) && engine.land_play_available?(index)

        engine.player(index).hand.flat_map do |id|
          (engine.chars(id).land? ? [{ type: "play_land", object: id }] : []) + engine.face_land_options(id)
        end + engine.permission_land_options(index)
      end

      def self.perform(engine, index, option)
        engine.use_play_method!(engine.play_method(index, option[:object], option[:via])) if option[:via]
        engine.player(index).lands_played += 1
        face = option[:face] && { "face" => option[:face] } # CR 712.9
        if !face && engine.entering_choice(engine.candidate_object(index, option[:object]))
          engine.state.frames << { "type" => "play_land", "object" => option[:object], "player" => index }
          return engine.ask!(nil)
        end
        engine.put_played_land!(index, option[:object], enters: face)
        engine.action_taken!(index) # CR 117.3c: the player receives priority again
      end

      # The play_land frame: ask the "as this enters" choice, then put the land onto the battlefield.
      def self.step(engine, frame)
        return engine.ask_enter_choice!(frame["object"], frame["player"]) unless frame["enter"]

        land = engine.candidate_object(frame["player"], frame["object"])
        enters = engine.enters_from_answer(land, frame)
        engine.pay_entering_costs!(frame["player"], frame)
        engine.put_played_land!(frame["player"], frame["object"], enters: enters)
        engine.action_taken!(frame["player"])
        :done
      end
    end
    register("play_land", PlayLand)
  end
end
