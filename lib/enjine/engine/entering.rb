# frozen_string_literal: true

module Enjine
  class Engine
    # "As this enters" choices (CR 614.12), the status a permanent enters with (Engine#plan_move), and
    # permanents a resolving effect puts onto the battlefield.
    module Entering
      # Counters from the caller ("with a +1/+1 counter", CR 701.72b) add to the ones replacements gave it.
      def merge_enters!(status, extra)
        extra.each do |key, value|
          status[key] = key == "counters" ? status.fetch(key, {}).merge(value) { |_, a, b| a + b } : value
        end
      end

      # An "as this enters" choice the controller must make before `id` enters (CR 614.12). `id` may also
      # be an object (a stand-in), name a land played from outside the game, or a token an effect is about
      # to create (see #token_key).
      def entering_choice(id)
        id = outside_object(nil, outside_card(id)) if outside_key?(id)
        abilities = if id.is_a?(GameObject) || state.objects.key?(id) then chars(id).abilities
                    else token_to_create(id).printed_characteristics.abilities
                    end
        abilities.map(&:ability).find { it.kind == :entering_choice }
      end

      # Records the answer to an enter_choice decision on the frame that asked, or, for a permanent an
      # effect puts onto the battlefield, in that effect's locals (#ask_entering_choices!).
      def enter_choice!(option)
        answer = option.transform_keys(&:to_s)
        # A choice of any number of permanents (devour): each pick asks again; "done" ends it (CR 614.12).
        return ask!(state.pending.merge("chosen" => state.pending.fetch("chosen", []) + [answer["object"]])) if answer["type"] == "devour"

        answer["objects"] = state.pending["chosen"] if state.pending.key?("chosen")
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

      # What an "as this enters" answer costs, paid as the permanent enters: life (CR 119.4), or the
      # permanents it devours (CR 702.82a).
      def pay_entering_costs!(controller, frame)
        answer = frame["enter"] or return
        return change_life!(controller, -answer["life"]) if answer["type"] == "pay_life"

        choice = answer.key?("objects") && entering_choice(frame["object"])
        choice.pay!(self, controller, answer) if choice.respond_to?(:pay!)
      end

      # ---- permanents an effect puts onto the battlefield (CR 614.12, 614.12a) ----------------

      # Before any of them enters, the player who will control each permanent makes its "as this enters"
      # choice, one permanent at a time. `entries`: [[object id or token key, controller], ...]. Answers
      # stay in the effect's locals (Engine#enter_choice!), so the effect resumes after each. :wait while asking.
      def ask_entering_choices!(locals, entries)
        answers = locals["entering"] ||= {}
        id, controller = entries.find { |ref, _| !answers.key?(ref) && entering_choice(ref) }
        return nil unless id

        token = state.objects.key?(id) ? {} : { "card" => token_to_create(id).id }
        ask!({ "kind" => "enter_choice", "player" => controller, "object" => id, "effect" => true }.merge(token))
        :wait
      end

      # Puts cards onto the battlefield at the same time: replacement effects for all of them are determined
      # before any enters (CR 614.12), with the choices asked by #ask_entering_choices!. `entries`:
      # [[id, controller, enters]]. Returns the new permanents.
      def enter_battlefield!(locals, entries, reason:)
        plans = entries.map do |id, controller, enters|
          plan_move(id, :battlefield, reason: reason, controller: controller,
                                      enters: with_entering_answer(locals, id, controller, enters))
        end
        plans.compact.map { execute_zone_change!(it) }
      end

      # The entering status `enters` plus what the "as this enters" answer for `id` adds (a memory, tapped);
      # a life payment chosen is paid now, as it enters (CR 119.4).
      def with_entering_answer(locals, id, controller, enters)
        answer = locals.fetch("entering", {})[id] or return enters
        pay_entering_costs!(controller, "enter" => answer, "object" => id)
        extra = entering_status(entering_choice(id), answer) or return enters
        (enters || {}).merge(extra) do |key, mine, theirs|
          next mine || theirs if key == "tapped" # "enters tapped" from the effect stays

          mine.is_a?(Hash) ? mine.merge(theirs) : theirs
        end
      end

      # The options of a pending enter_choice. Several permanents entering at once can't be given choices
      # whose combined life payments are more than the player has (CR 614.12b).
      def entering_options(pending)
        choice = entering_choice(pending["object"])
        return choice.pick_options(self, pending["player"], pending.fetch("chosen", [])) if choice.respond_to?(:pick_options)

        options = choice.options(self, pending["player"])
        return options unless pending["effect"]

        spent = answering_locals.fetch("entering", {}).values.sum do
          it["player"] == pending["player"] && it["type"] == "pay_life" ? it["life"] : 0
        end
        options.reject { it[:type] == "pay_life" && it[:life] > player(pending["player"]).life - spent }
      end

      # A token an effect is about to create, named before it exists ("new_token:<card>:<n>") so its "as
      # this enters" choice can be asked first (CR 614.12, 111.1).
      def token_key(definition, index) = "new_token:#{definition.id}:#{index}"
      def token_to_create(key) = catalog.fetch(key.to_s.split(":")[1].to_s)
    end

    include Entering
  end
end
