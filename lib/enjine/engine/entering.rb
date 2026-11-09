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

      # The "as this enters" choices the controller must make before `id` enters (CR 614.12), in printed order
      # (Multiversal Passage: a basic land type, then pay 2 life or enter tapped). `id` may also be an object (a
      # stand-in), name a land played from outside the game, or a token an effect is about to create (see
      # #token_key).
      def entering_choices(id)
        id = outside_object(nil, outside_card(id)) if outside_key?(id)
        abilities = if id.is_a?(GameObject) || state.objects.key?(id) then chars(id).abilities
                    else token_to_create(id).printed_characteristics.abilities
                    end
        abilities.map(&:ability).select { it.kind == :entering_choice }
      end

      def entering_choice(id) = entering_choices(id).first

      # The answers given so far, one per choice in order (a single answer from an older snapshot counts as one).
      def self.answers(given) = given.is_a?(Hash) ? [given] : Array(given)

      # Whether `id` still has an "as this enters" choice to make, given the answers so far.
      def entering_choice_pending?(id, given) = entering_choices(id).size > Entering.answers(given).size

      # Records the answer to an enter_choice decision on the frame that asked, or, for a permanent an
      # effect puts onto the battlefield, in that effect's locals (#ask_entering_choices!).
      def enter_choice!(option)
        answer = option.transform_keys(&:to_s)
        if state.pending["effect"]
          answers = (answering_locals["entering"] ||= {})
          id = state.pending["object"]
          answers[id] = Entering.answers(answers[id]) + [answer.merge("player" => state.pending["player"])]
        else
          frame = state.frames.last
          frame["enter"] = Entering.answers(frame["enter"]) + [answer]
        end
        ask!(nil)
      end

      def ask_enter_choice!(id, controller)
        ask!("kind" => "enter_choice", "player" => controller, "object" => id)
        :wait
      end

      def enters_from_answer(id, frame) = entering_statuses(id, Entering.answers(frame["enter"]))

      # What a permanent enters with given its "as this enters" answers, combined (memories merged, counters
      # added, tapped if any says so), or nil.
      def entering_statuses(id, answers)
        choices = entering_choices(id)
        answers.each_with_index.reduce(nil) do |status, (answer, i)|
          extra = choices[i] && entering_status(choices[i], answer)
          next status || extra unless status && extra

          status.merge(extra) do |key, mine, theirs|
            next mine || theirs if key == "tapped"
            next mine.merge(theirs) { |_, a, b| a + b } if key == "counters"

            mine.is_a?(Hash) ? mine.merge(theirs) : theirs
          end
        end
      end

      # What a permanent enters with given one "as this enters" answer (a memory, tapped, a copy, CR 707.5).
      def entering_status(choice, answer)
        answer = answer.except("player").transform_keys(&:to_sym)
        choice.respond_to?(:enters_with) ? choice.enters_with(self, answer) : choice.enters_for(answer)
      end

      # What the "as this enters" answers pay as the permanent enters: life (CR 119.4), or beholding (CR 701.4a).
      def pay_entering_cost!(controller, frame)
        Entering.answers(frame["enter"]).each do |answer|
          case answer["type"]
          when "pay_life" then change_life!(controller, -answer["life"])
          when "behold"
            id = answer["object"]
            Mechanics::Beholding.behold!(self, controller, id) if state.objects.key?(id)
          end
        end
      end

      # ---- permanents an effect puts onto the battlefield (CR 614.12, 614.12a) ----------------

      # Before any of them enters, the player who will control each permanent makes its "as this enters"
      # choice, one permanent at a time. `entries`: [[object id or token key, controller], ...]. Answers
      # stay in the effect's locals (Engine#enter_choice!), so the effect resumes after each. :wait while asking.
      def ask_entering_choices!(locals, entries)
        answers = locals["entering"] ||= {}
        id, controller = entries.find { |ref, _| entering_choice_pending?(ref, answers[ref]) }
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
        answers = locals.fetch("entering", {})[id] or return enters
        pay_entering_cost!(controller, "enter" => answers)
        extra = entering_statuses(id, Entering.answers(answers)) or return enters
        (enters || {}).merge(extra) do |key, mine, theirs|
          next mine || theirs if key == "tapped" # "enters tapped" from the effect stays

          mine.is_a?(Hash) ? mine.merge(theirs) : theirs
        end
      end

      # The options of a pending enter_choice: the first choice not answered yet. Several permanents entering at
      # once can't be given choices whose combined life payments are more than the player has (CR 614.12b).
      def entering_options(pending)
        given = pending["effect"] ? answering_locals.fetch("entering", {})[pending["object"]] : state.frames.last["enter"]
        options = entering_choices(pending["object"])[Entering.answers(given).size].options(self, pending["player"])
        return options unless pending["effect"]

        spent = answering_locals.fetch("entering", {}).values.flat_map { Entering.answers(it) }.sum do
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
