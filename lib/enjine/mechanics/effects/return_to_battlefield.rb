# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Puts cards from exile or a graveyard onto the battlefield ("return that card to the
      # battlefield under its owner's control"). Usually aimed at {"result": n}: a flicker is
      # `exile` followed by `return_to_battlefield` of the exile's result.
      class ReturnToBattlefield < Effect
        UNDER = %w[owner you].freeze
        ZONES = %i[exile graveyard].freeze

        primitive :effect, :return_to_battlefield,
                  description: "Put each referenced card that is in exile or a graveyard onto the battlefield under its " \
                               "owner's control (`under: \"you\"`: under the controller's), tapped if `tapped: true`. " \
                               "A card that is no longer in the zone it was expected in, or isn't a permanent card, " \
                               "stays where it is. `transformed: true`: it enters with its back face up; a card that " \
                               "isn't double-faced, or whose back face isn't a permanent, stays where it is.",
                  rules: %w[400.7 400.4a 110.2 111.8 603.7c 614.1c 122.6 712.11a 712.11b],
                  params: { "to" => "selector (usually {\"result\": n})", "tapped" => "boolean", "transformed" => "boolean",
                            "under" => UNDER.join(" | "),
                            "counters" => "{counter name: n}: it enters with these counters (\"with a +1/+1 counter on it\")" },
                  example: { "return_to_battlefield" => { "to" => { "result" => 0 } } }

        attr_reader :tapped, :under, :counters, :transformed

        def self.keys = %w[to tapped under counters transformed if]

        def setup(params, errors, path)
          @tapped = Mechanics.fetch_param(params, :tapped) == true
          @transformed = Mechanics.fetch_param(params, :transformed) == true
          @under = Mechanics.fetch_param(params, :under) || "owner"
          errors << "#{path}.under: must be one of #{UNDER.join(", ")}" unless UNDER.include?(@under)
          @counters = parse_counters(Mechanics.fetch_param(params, :counters) || {}, errors, "#{path}.counters")
        end

        def parse_counters(raw, errors, path)
          return (errors << "#{path}: must be an object of counter name => count") && {} unless raw.is_a?(Hash)

          raw.to_h do |name, n|
            kind = Counters.parse(name.to_s, errors, "#{path}.#{name}")
            errors << "#{path}.#{name}: must be a positive integer" unless n.is_a?(Integer) && n.positive?
            [kind, n]
          end.freeze
        end

        def to_s
          extra = counters.map { |kind, n| " with #{n} #{kind} counter(s)" }.join
          status = "#{" tapped" if tapped}#{" transformed" if transformed}"
          "return to the battlefield#{status}#{" under your control" if under == "you"}#{extra} → #{to}"
        end

        # CR 614.12a: each card's "as this enters" choice is made first (asked in turn), then they all
        # enter at the same time. The cards are fixed as the effect starts.
        def run(engine, ctx, locals)
          return :done unless locals.key?("cards") || condition.nil? || condition.true?(engine, ctx)

          entries = (locals["cards"] ||= cards(engine, ctx).map { [it, under == "you" ? ctx.controller : engine.object(it).owner] })
          entries = entries.select { engine.state.objects.key?(it[0]) }
          return :wait if engine.ask_entering_choices!(locals, entries) == :wait

          enters = { "tapped" => tapped || nil, "counters" => counters.empty? ? nil : counters.dup,
                     "face" => transformed ? 1 : nil }.compact
          engine.enter_battlefield!(locals, entries.map { [*it, enters.empty? ? nil : enters] }, reason: "return")
          :done
        end

        # CR 400.4a: an instant or sorcery card can't enter the battlefield. CR 111.8: a token that
        # has left the battlefield can't come back (it ceases to exist at the next SBA check).
        def cards(engine, ctx)
          refs(engine, ctx).select do |id|
            obj = engine.state.objects[id]
            obj && ZONES.include?(obj.zone) && !engine.token?(obj) &&
              !(engine.chars(obj).types - %i[instant sorcery]).empty? && (!transformed || engine.can_enter_face?(obj, 1))
          end
        end
      end
    end
  end
end
