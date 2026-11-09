# frozen_string_literal: true

module Enjine
  class Engine
    # "As this enters" choices (CR 614.12) and the status a permanent enters with (Engine#plan_move).
    module Entering
      # Counters from the caller ("with a +1/+1 counter", CR 701.72b) add to the ones replacements gave it.
      def merge_enters!(status, extra)
        extra.each do |key, value|
          status[key] = key == "counters" ? status.fetch(key, {}).merge(value) { |_, a, b| a + b } : value
        end
      end

      # An "as this enters" choice the controller must make before `id` enters (CR 614.12). `id` may also
      # be an object (a stand-in), name a land played from outside the game, or a token an effect is about
      # to create (see Engine::Resolution#token_key).
      def entering_choice(id)
        id = outside_object(nil, outside_card(id)) if outside_key?(id)
        abilities = if id.is_a?(GameObject) || state.objects.key?(id) then chars(id).abilities
                    else token_to_create(id).printed_characteristics.abilities
                    end
        abilities.map(&:ability).find { it.kind == :entering_choice }
      end

      # Records the answer to an enter_choice decision on the frame that asked, or, for a permanent an
      # effect puts onto the battlefield, in that effect's locals (Engine::Resolution#ask_entering_choices!).
      def enter_choice!(option)
        answer = option.transform_keys(&:to_s)
        if state.pending["effect"]
          (answering_locals["entering"] ||= {})[state.pending["object"]] = answer.merge("player" => state.pending["player"])
        else
          state.frames.last["enter"] = answer
        end
        ask!(nil)
      end

      def ask_enter_choice!(id, controller)
        ask!("kind" => "enter_choice", "player" => controller, "object" => id)
        :wait
      end

      def enters_from_answer(id, frame)
        choice = entering_choice(id)
        return nil unless choice && frame["enter"]

        entering_status(choice, frame["enter"])
      end

      # What a permanent enters with given its "as this enters" answer (a memory, tapped, a copy, CR 707.5).
      def entering_status(choice, answer)
        answer = answer.except("player").transform_keys(&:to_sym)
        choice.respond_to?(:enters_with) ? choice.enters_with(self, answer) : choice.enters_for(answer)
      end

      def pay_entering_life!(controller, frame)
        return unless frame["enter"] && frame["enter"]["type"] == "pay_life"

        change_life!(controller, -frame["enter"]["life"])
      end
    end
    include Entering
  end
end
