# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # "When you unlock this door" (CR 709.5h) and "whenever you fully unlock a Room" (CR 709.5i). A door's own
      # trigger is written {"unlocks_door": {}} on that door and is tagged with it as the card is read
      # (CardDefinition::Rooms); it triggers when the permanent gets that door's unlocked designation, as it enters
      # from a resolving door spell too. `door: "any"` triggers for either door; `fully: true` only when the
      # permanent ends up with both doors unlocked; `subject` names other Rooms ("a Room you control").
      class UnlocksDoor < Trigger
        DOORS = %w[left right any].freeze

        primitive :trigger, :unlocks_door,
                  description: "A Room permanent (the subject, default this one) gets an unlocked designation. On a Room's " \
                               "door, `{}` means \"when you unlock this door\". `door`: left | right | any; `fully: true`: " \
                               "only when it now has both doors unlocked (\"whenever you fully unlock a Room\").",
                  rules: %w[709.5h 709.5i 709.5j 603.2],
                  params: { "door" => "left | right | any (set on a door's own trigger)", "fully" => "true",
                            "subject" => "\"self\" (default) or {\"each\": filter, \"controller\": ...}" },
                  example: { "unlocks_door" => { "door" => "any", "fully" => true,
                                                 "subject" => { "each" => "permanent", "controller" => "you" } } }

        def self.keys = %w[door fully subject]
        def event_class = Events::DoorUnlocked

        def setup(params, errors, path)
          @door = params["door"]
          errors << "#{path}.door: must be one of #{DOORS.join(", ")} (a door's own trigger needs none)" unless DOORS.include?(@door)
          @fully = Mechanics.flag_param(params, :fully, errors, path)
        end

        def match?(engine, event, source)
          return false unless @door == "any" || event.door == @door
          return false if @fully && !event.fully

          obj = engine.state.objects[event.object] or return false
          @subject.match?(engine, obj.id, obj.controller, obj.card, source)
        end

        def to_s
          return "Whenever you fully unlock #{@subject}" if @fully

          "When you unlock #{@door == "any" ? "a door of" : "the #{@door} door of"} #{@subject}"
        end
      end
    end
  end
end
