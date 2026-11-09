# frozen_string_literal: true

require_relative "replacement_effects"

module Enjine
  module Mechanics
    # Which damage a damage replacement or prevention effect of a permanent watches, relative to that
    # permanent (the "holder"): its sources (`by`) or recipients (`to`).
    #   "self" | "attached"                         the holder, or what it enchants or equips
    #   {"each": filter, "controller": you|opponent|any, "other": bool}
    # `each` is optional (any player or object); players match on the filter (`player`, `opponent`) and
    # on `controller` (themselves), so {"controller": "opponent"} is "an opponent or a permanent an
    # opponent controls" and {"controller": "you", "other": true} "you and other permanents you control".
    class DamageScope
      CONTROLLERS = %w[you opponent any].freeze

      def self.build(data, errors, path)
        return nil if data.nil?
        return new(data.to_sym, nil, "any", false) if %w[self attached].include?(data)

        unless data.is_a?(Hash)
          errors << "#{path}: must be \"self\", \"attached\" or {\"each\": filter, \"controller\": you|opponent|any, " \
                    "\"other\": bool}"
          return nil
        end
        Mechanics.check_keys(data, %w[each controller other], errors, path)
        controller = data.fetch("controller", "any")
        errors << "#{path}.controller: must be one of #{CONTROLLERS.join(", ")}" unless CONTROLLERS.include?(controller)
        filter = data["each"] && Mechanics.build_entry(:filter, data["each"], errors, "#{path}.each")
        new(:each, filter, controller, data["other"] == true)
      end

      def initialize(kind, filter, controller, other)
        @kind = kind
        @filter = filter
        @controller = controller
        @other = other
        freeze
      end

      # Whether `ref` (a player reference or an object id) is in scope for the permanent `holder`.
      def match?(engine, ref, holder)
        return ref == holder.id if @kind == :self
        return !holder.attached_to.nil? && ref == holder.attached_to if @kind == :attached
        return false if @other && ref == holder.id

        index = Filters.player_index(engine, ref)
        owner = index || engine.state.objects[ref]&.controller
        return false if owner.nil?
        return false unless @controller == "any" || (@controller == "you") == (owner == holder.controller)

        @filter.nil? || @filter.match_for?(engine, ref, holder.controller, holder.id)
      end

      # The permanent a redirection sends damage to (CR 614.9).
      def redirect_target(holder) = @kind == :self ? holder.id : holder.attached_to

      def to_s
        return "this" if @kind == :self
        return "the attached creature" if @kind == :attached

        what = @filter ? Triggers.filter_words(@filter) : "anything"
        "#{"other " if @other}#{what}#{{ "you" => " (yours)", "opponent" => " (an opponent's)" }[@controller]}"
      end
    end

    # The damage pass of the replacement step (CR 614.1a, 614.9, 615, 616.1): redirection, prevention and
    # damage modification, from static abilities of permanents and from resolved prevention effects.
    #
    # The affected player (or the affected permanent's controller) chooses the order (CR 616.1). The engine
    # applies them in the order that player would choose to take the least damage: redirections first (the
    # damage then affects the new recipient), then prevention, then multiplying, then adding.
    module DamageEvents
      module_function

      def replace!(engine, proposal)
        redirect!(engine, proposal)
        proposal.data["unpreventable"] = true if unpreventable?(engine, proposal.data) # CR 615.12 (also shield counters)
        prevent!(engine, proposal)
        modify!(engine, proposal)
      end

      def statics(engine, kind)
        Replacements.battlefield_abilities(engine, :damage_scope).select { |_, ability| ability.kind == kind }
      end

      def applicable(engine, proposal, kind)
        statics(engine, kind).select do |holder, ability|
          !proposal.applied.include?("#{holder.id}:#{kind}") && ability.applies?(engine, proposal.data, holder)
        end
      end

      # CR 614.9: "all damage that would be dealt to you is dealt to [this creature] instead". The new
      # recipient must still be a creature or planeswalker on the battlefield, else nothing happens.
      def redirect!(engine, proposal)
        loop do # each redirection applies once (CR 614.5); the next one sees the new recipient (CR 616.1f)
          holder, ability = applicable(engine, proposal, :damage_replacement).find do |source, found|
            found.redirect && redirect_ok?(engine, found.redirect.redirect_target(source), proposal.data["target"])
          end
          return unless holder

          proposal.applied << "#{holder.id}:damage_replacement"
          proposal.data["target"] = ability.redirect.redirect_target(holder)
        end
      end

      def redirect_ok?(engine, to, from)
        to && to != from && engine.state.battlefield.include?(to) && (engine.chars(to).creature? || engine.chars(to).planeswalker?)
      end

      # CR 615: prevention effects of static abilities, then shields from resolved effects (CR 615.7).
      # Damage that can't be prevented still passes through them without being prevented (CR 615.12).
      def prevent!(engine, proposal)
        data = proposal.data
        return if data["amount"].zero? || data["unpreventable"]

        data["amount"] = 0 if engine.damage_prevented?(data["target"]) # "prevent all damage to you" (player_rule)
        data["amount"] = 0 if protected?(engine, data) # CR 702.16e
        applicable(engine, proposal, :prevent_damage).each do |holder, ability|
          break if data["amount"].zero?

          follow_up!(engine, data, ability.follow_up&.entry(holder.card, holder.controller, holder.id, {}), data["amount"])
          data["amount"] = 0
        end
        engine.state.effects.select { it["kind"] == "prevent_damage" }.each do |effect|
          break if data["amount"].zero?
          next unless PreventionEffect.applies?(engine, effect, data)

          before = data["amount"]
          PreventionEffect.use!(engine, effect, data)
          follow_up!(engine, data, effect["follow_up"], before - data["amount"])
        end
      end

      # CR 615.5: the rest of a prevention effect happens right after the event (Engine#run_follow_ups!), seeing
      # the damage prevented, its source and the source's controller.
      def follow_up!(engine, data, entry, prevented)
        return unless entry && prevented.positive?

        facts = { "amount" => prevented, "object" => data["source"], "player" => engine.damage_source_controller(data["source"]) }
        (data["follow_ups"] ||= []) << entry.merge("facts" => facts.compact)
      end

      # Protection from the source's quality prevents the damage (CR 702.16e), also a player's protection from each
      # of their opponents (CR 702.16k).
      def protected?(engine, data)
        source = engine.state.objects[data["source"]]
        player = Filters.player_index(engine, data["target"])
        if player
          return !source.nil? && engine.player_rule?(player, "protection_from_opponents") &&
                 Abilities::QualityAbility.opponents?(source, player)
        end
        target = engine.state.objects[data["target"]]
        target&.zone == :battlefield && engine.protected_from?(target, source)
      end

      # CR 615.12: a game rule (Engine::Rules#unpreventable?), a static ability or a resolved effect.
      def unpreventable?(engine, data)
        engine.unpreventable?(data["combat"]) ||
          statics(engine, :damage_unpreventable).any? { |holder, ability| ability.applies?(engine, data, holder) } ||
          engine.state.effects.any? do
            it["kind"] == "damage_unpreventable" && (it["combat"].nil? || it["combat"] == (data["combat"] ? "combat" : "noncombat"))
          end
      end

      # "Deals double that damage instead" and "that much damage plus N instead" (CR 614.1a).
      def modify!(engine, proposal)
        data = proposal.data
        return if data["amount"].zero?

        found = applicable(engine, proposal, :damage_replacement).reject { |_, ability| ability.redirect }
        found.sort_by { |_, ability| ability.multiply ? 0 : 1 }.each do |holder, ability|
          proposal.applied << "#{holder.id}:damage_replacement"
          data["amount"] = ability.modified(engine, data["amount"], holder)
        end
        modify_by_effects!(engine, proposal)
      end

      # Resolved "until your next turn, if a source would deal damage to that player or a permanent that player
      # controls, it deals double that damage instead" effects (Effects::DamageReplacementEffect): doubling first.
      def modify_by_effects!(engine, proposal)
        data = proposal.data
        found = engine.state.effects.select do |effect|
          effect["kind"] == "damage_replacement" && !proposal.applied.include?("effect:#{effect["timestamp"]}") &&
            ModifyingEffect.applies?(engine, effect, data)
        end
        found.sort_by { it["multiply"] ? 0 : 1 }.each do |effect|
          proposal.applied << "effect:#{effect["timestamp"]}"
          data["amount"] = effect["multiply"] ? data["amount"] * effect["multiply"] : data["amount"] + effect["plus"]
        end
      end

      # Damage replacement effects of resolved spells and abilities (state.effects, kind "damage_replacement"):
      # {"to": [refs], "permanents": bool, "combat": ..., "multiply": n | nil, "plus": n | nil}. A player in `to`
      # with "permanents" also covers the permanents they control as the damage is dealt (CR 611.2c).
      module ModifyingEffect
        module_function

        def applies?(engine, effect, data)
          return false unless DamageEvents.combat_ok?(effect["combat"], data["combat"])

          target = data["target"]
          return true if effect["to"].include?(target)

          controller = engine.state.battlefield.include?(target) && engine.object(target).controller
          effect["permanents"] && controller && effect["to"].include?(Filters.player_ref(engine, controller))
        end
      end

      # Prevention effects started by a resolved spell or ability (state.effects, kind "prevent_damage"):
      # {"to": [refs] | nil, "to_each": damage scope | nil, "by": [refs] | nil, "combat": "combat" | "noncombat" | nil,
      # "remaining": n | nil, "next_time": true | nil, "follow_up": FollowUp entry | nil}.
      module PreventionEffect
        module_function

        # The effect's controller, standing in for the holder of a `to_each` damage scope (CR 611.2c: the
        # recipients are checked as the damage is dealt).
        Holder = Data.define(:id, :controller, :attached_to)

        def applies?(engine, effect, data)
          (effect["to"].nil? || effect["to"].include?(data["target"])) &&
            (effect["to_each"].nil? || to_each?(engine, effect, data["target"])) &&
            (effect["by"].nil? || effect["by"].include?(data["source"])) &&
            DamageEvents.combat_ok?(effect["combat"], data["combat"])
        end

        def to_each?(engine, effect, ref)
          scope = DamageScope.build(effect["to_each"], [], "to_each")
          scope.match?(engine, ref, Holder.new(id: nil, controller: effect["controller"], attached_to: nil))
        end

        # A shield prevents that much and is used up (CR 615.7); without one, all of it is prevented.
        def use!(engine, effect, data)
          engine.state.effects.delete(effect) if effect["next_time"] # CR 615.8: the next time only
          return data["amount"] = 0 unless effect["remaining"]

          prevented = [effect["remaining"], data["amount"]].min
          effect["remaining"] -= prevented
          data["amount"] -= prevented
          engine.state.effects.delete(effect) if effect["remaining"].zero?
        end
      end

      COMBAT = %w[combat noncombat].freeze

      def combat_ok?(wanted, combat) = wanted.nil? || (wanted == "combat") == combat

      def parse_combat(params, errors, path)
        combat = Mechanics.fetch_param(params, :combat)
        errors << "#{path}.combat: must be one of #{COMBAT.join(", ")}" unless combat.nil? || COMBAT.include?(combat)
        combat
      end
    end

    module Abilities
      # Base for static abilities of a permanent about some damage events: damage from sources `by`,
      # to recipients `to`, combat or noncombat damage.
      class DamageStatic < StaticReplacement
        attr_reader :by, :to, :combat

        def self.parse_scopes(params, errors, path)
          [DamageScope.build(Mechanics.fetch_param(params, :by), errors, "#{path}.by"),
           DamageScope.build(Mechanics.fetch_param(params, :to), errors, "#{path}.to"),
           DamageEvents.parse_combat(params, errors, path)]
        end

        def initialize(sources, recipients, combat)
          super()
          @by = sources
          @to = recipients
          @combat = combat
          freeze
        end

        def damage_scope = true

        def applies?(engine, data, holder)
          DamageEvents.combat_ok?(combat, data["combat"]) &&
            (by.nil? || by.match?(engine, data["source"], holder)) && (to.nil? || to.match?(engine, data["target"], holder))
        end

        def scope_text
          ["#{"#{combat} " if combat}damage", by && "by #{by}", to && "to #{to}"].compact.join(" ")
        end
      end

      # "If a source you control would deal damage to an opponent or a permanent an opponent controls, it
      # deals double that damage instead" / "... that much damage plus 1 instead" / "All damage that would
      # be dealt to you is dealt to this creature instead" (CR 614.1a, 614.9).
      class DamageReplacement < DamageStatic
        primitive :ability, :damage_replacement,
                  description: "While this permanent is on the battlefield, damage from sources in `by` to recipients " \
                               "in `to` (both optional; `combat`: combat | noncombat) is changed: `multiply` (2 = " \
                               "\"double that damage\"), `plus` an amount (\"that much damage plus 1\"), or " \
                               "`redirect` (\"self\" | \"attached\": dealt to this permanent or the one it's attached " \
                               "to instead). A scope is \"self\", \"attached\" or {\"each\": filter, \"controller\": " \
                               "you|opponent|any, \"other\": bool}; `each` is optional and players match too, so " \
                               "{\"controller\": \"opponent\"} is \"an opponent or a permanent an opponent controls\". " \
                               "Several apply in the order the affected player would pick: redirections, then " \
                               "prevention, then multiplying, then adding.",
                  rules: %w[614.1a 614.5 614.9 616.1 616.1e 616.1f 120.2b],
                  params: { "by" => "damage scope", "to" => "damage scope", "combat" => "combat | noncombat",
                            "multiply" => "integer >= 2", "plus" => "amount", "redirect" => "\"self\" | \"attached\"" },
                  example: { "damage_replacement" => { "by" => { "controller" => "you" }, "to" => { "controller" => "opponent" },
                                                       "multiply" => 2 } }

        attr_reader :multiply, :plus, :redirect

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[by to combat multiply plus redirect], errors, path)
          modes = %w[multiply plus redirect].select { params.key?(it) }
          errors << "#{path}: needs exactly one of multiply, plus, redirect" unless modes.size == 1
          multiply = params.key?("multiply") ? Mechanics.integer_param(params, :multiply, errors, path, min: 2) : nil
          plus = params.key?("plus") ? Amount.build(params["plus"], errors, "#{path}.plus", targets_count: 0) : nil
          redirect = params["redirect"]
          errors << "#{path}.redirect: must be \"self\" or \"attached\"" if params.key?("redirect") && !%w[self attached].include?(redirect)
          new(*parse_scopes(params, errors, path), multiply, plus, redirect && DamageScope.new(redirect.to_sym, nil, "any", false))
        end

        def initialize(sources, recipients, combat, multiply, plus, redirect)
          @multiply = multiply
          @plus = plus
          @redirect = redirect
          super(sources, recipients, combat)
        end

        def kind = :damage_replacement

        def modified(engine, amount, holder)
          return amount * multiply if multiply

          amount + [plus.value(engine, EffectContext.new(holder.controller, holder.id, holder.id, [], [])), 0].max
        end

        def to_s
          instead = if multiply then "#{multiply} times that damage"
                    elsif plus then "that much plus #{plus}"
                    else "that damage to #{redirect}"
                    end
          "#{scope_text}: #{instead} instead"
        end
      end

      # "Prevent all combat damage that would be dealt to and dealt by this creature" / "Prevent all
      # noncombat damage that would be dealt to other creatures you control" (CR 615.1).
      class PreventDamage < DamageStatic
        primitive :ability, :prevent_damage,
                  description: "While this permanent is on the battlefield, all damage from sources in `by` to " \
                               "recipients in `to` (damage scopes as in damage_replacement, both optional; " \
                               "`combat`: combat | noncombat) is prevented. \"To and by this creature\" is two of them. " \
                               "`then`: effects right after it prevents damage (\"prevent that damage and put that many " \
                               "+1/+1 counters on him\"), reading {\"triggering\": \"amount\"} (the damage prevented), " \
                               "\"object\" (the source) and \"player\" (its controller).",
                  rules: %w[615.1 615.1a 615.5 615.6],
                  params: { "by" => "damage scope", "to" => "damage scope", "combat" => "combat | noncombat",
                            "then" => "list of effects" },
                  example: { "prevent_damage" => { "to" => { "each" => "creature", "controller" => "you", "other" => true },
                                                   "combat" => "noncombat" } }

        attr_reader :follow_up

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[by to combat then], errors, path)
          new(*parse_scopes(params, errors, path), FollowUp.build(params, errors, path))
        end

        def initialize(sources, recipients, combat, follow_up = nil)
          @follow_up = follow_up
          super(sources, recipients, combat)
        end

        def kind = :prevent_damage
        def try_effects = [follow_up].compact
        def to_s = "prevent all #{scope_text}#{", then #{follow_up}" if follow_up}"
      end

      # "Damage can't be prevented." / "Combat damage that would be dealt by creatures you control can't be
      # prevented." (CR 615.12)
      class DamageUnpreventable < DamageStatic
        primitive :ability, :damage_unpreventable,
                  description: "While this permanent is on the battlefield, damage from sources in `by` to recipients " \
                               "in `to` (both optional; `combat`: combat | noncombat) can't be prevented: prevention " \
                               "effects don't reduce it and shields aren't used up.",
                  rules: %w[615.12],
                  params: { "by" => "damage scope", "to" => "damage scope", "combat" => "combat | noncombat" },
                  example: { "damage_unpreventable" => { "combat" => "combat" } }

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[by to combat], errors, path)
          new(*parse_scopes(params, errors, path))
        end

        def kind = :damage_unpreventable
        def to_s = "#{scope_text} can't be prevented"
      end
    end

    module Effects
      # "Prevent all combat damage that would be dealt to it this turn", "Prevent the next 3 damage that
      # would be dealt to any target this turn", "Prevent all damage that would be dealt by target creature
      # this turn", "Prevent all damage that would be dealt to creatures you control this turn", "The next time
      # a source of your choice would deal damage to you this turn, prevent that damage. When damage is
      # prevented this way, ..." (CR 615.1, 615.3, 615.5, 615.7, 615.8, 609.7a, 611.2b-c).
      class PreventDamageEffect < ChoiceEffect
        DURATIONS = %w[end_of_turn until_your_next_turn while_source_on_battlefield].freeze

        primitive :effect, :prevent_damage,
                  description: "For the `duration` (end_of_turn by default, until_your_next_turn, or " \
                               "while_source_on_battlefield: for as long as this effect's source remains on the " \
                               "battlefield), damage that would be dealt to the referenced players and permanents " \
                               "(`to`, fixed as it resolves) or to those matching `to_each` as the damage is dealt " \
                               "(a damage scope seen from the controller, e.g. {\"each\": \"creature\", " \
                               "\"controller\": \"you\"}), and/or by the referenced sources (`by`; \"chosen_source\": " \
                               "a source the controller chooses as it resolves) is prevented (`combat`: combat | " \
                               "noncombat only). With `next`, it is a shield that prevents only the next that much " \
                               "damage; with `next_time: true` it prevents only the next damage event it applies to. " \
                               "`then`: effects right after it prevents damage, reading {\"triggering\": \"amount\"} " \
                               "(the damage prevented), \"object\" (the source) and \"player\" (its controller).",
                  rules: %w[615.1 615.3 615.5 615.7 615.8 609.7a 611.2a 611.2b 611.2c],
                  params: { "to" => "selector (recipients)", "to_each" => "damage scope (recipients, as damage is dealt)",
                            "by" => "selector (sources) | \"chosen_source\"", "combat" => "combat | noncombat",
                            "next" => "amount (a shield)", "next_time" => "boolean", "duration" => DURATIONS.join(" | "),
                            "then" => "list of effects" },
                  example: { "prevent_damage" => { "to" => { "target" => 0 }, "combat" => "combat" } }

        attr_reader :by, :combat, :shield, :duration, :to_each, :follow_up

        def self.keys = %w[to to_each by combat next next_time duration then if]

        # `to` may be left out when `by` names the sources ("damage that would be dealt by target creature") or
        # `to_each` the recipients.
        def self.build(params, errors, path, targets_count: 0, results_count: 0, **)
          if Mechanics.fetch_param(params, :to) || (!Mechanics.fetch_param(params, :by) && !Mechanics.fetch_param(params, :to_each))
            return super
          end

          Mechanics.check_keys(params, keys, errors, path)
          new(to: nil, params: params, errors: errors, path: path, targets_count: targets_count, results_count: results_count)
        end

        def setup(params, errors, path)
          raw_by = Mechanics.fetch_param(params, :by)
          @chosen_source = raw_by == "chosen_source"
          unless raw_by.nil? || @chosen_source
            @by = Selector.build(raw_by, errors, "#{path}.by", targets_count: @targets_count, results_count: @results_count)
          end
          @to_each_data = Mechanics.fetch_param(params, :to_each)
          @to_each = DamageScope.build(@to_each_data, errors, "#{path}.to_each")
          errors << "#{path}.to_each: must be a damage scope {\"each\": filter, \"controller\": ...}" if @to_each_data.is_a?(String)
          @combat = DamageEvents.parse_combat(params, errors, path)
          raw_next = Mechanics.fetch_param(params, :next)
          @shield = raw_next && Amount.build(raw_next, errors, "#{path}.next", targets_count: @targets_count, min: 1,
                                                                               results_count: @results_count)
          @next_time = Mechanics.flag_param(params, :next_time, errors, path)
          errors << "#{path}: next and next_time can't be combined" if @shield && @next_time
          @duration = Mechanics.fetch_param(params, :duration) || "end_of_turn"
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
          @follow_up = FollowUp.build(params, errors, path)
        end

        def nested_effects = [follow_up].compact

        # A source of the controller's choice (CR 609.7a): a permanent or a spell on the stack, chosen as it resolves.
        def run(engine, ctx, locals)
          return :done unless locals["asked"] || condition.nil? || condition.true?(engine, ctx)
          return start(engine, ctx, nil) unless @chosen_source

          answer = answers(locals).first
          return start(engine, ctx, [answer["object"]]) if answer

          sources = engine.state.battlefield + engine.state.stack.reject { it == ctx.object }
          return :done if sources.empty?

          ask(engine, locals, ctx.controller, "Choose a source of damage", sources.map { { "type" => "source", "object" => it } })
        end

        def start(engine, ctx, chosen)
          # CR 611.2b: "for as long as" a source that has already left never starts.
          return :done if duration == "while_source_on_battlefield" && !engine.state.battlefield.include?(ctx.source)

          to = self.to && refs(engine, ctx)
          by = chosen || @by&.resolve(engine, ctx)
          details = { "to" => to, "to_each" => @to_each_data, "by" => by, "combat" => combat, "duration" => duration,
                      "source" => ctx.source, "next_time" => (true if @next_time) }.compact
          details["to"] = nil if to.nil? # "to": nil means any recipient
          details["by"] = nil if by.nil?
          details["remaining"] = shield.value(engine, ctx) if shield
          card = engine.state.objects[ctx.object]&.card
          details["follow_up"] = follow_up.entry(card, ctx.controller, ctx.source, {}) if follow_up && card
          engine.add_continuous_effect!("prevent_damage", ctx, (to || []) + (by || []), details)
          :done
        end

        def to_s
          what = if shield then "the next #{shield}"
                 elsif @next_time then "the next time"
                 else "all"
                 end
          ["prevent #{what} #{"#{combat} " if combat}damage", to && "to #{to}", @to_each && "to #{@to_each}",
           (@chosen_source ? "by a source of your choice" : by && "by #{by}"), follow_up && "then #{follow_up}"].compact.join(" ")
        end
      end

      # "Until your next turn, if a source would deal damage to that player or a permanent that player controls,
      # it deals double that damage instead." (CR 614.1a, 611.2c, 616.1)
      class DamageReplacementEffect < Effect
        DURATIONS = %w[end_of_turn until_your_next_turn].freeze

        primitive :effect, :damage_replacement,
                  description: "For the `duration` (end_of_turn by default, or until_your_next_turn), damage that " \
                               "would be dealt to the referenced players and permanents (`to`, fixed as it resolves; " \
                               "with `permanents: true` also the permanents a referenced player controls as the damage " \
                               "is dealt) is changed: `multiply` (2 = \"double that damage\") or `plus` an amount " \
                               "(computed as it resolves). `combat`: combat | noncombat only. Doubling applies before " \
                               "adding.",
                  rules: %w[614.1a 611.2a 611.2c 616.1],
                  params: { "to" => "selector", "permanents" => "boolean", "combat" => "combat | noncombat",
                            "multiply" => "integer >= 2", "plus" => "amount", "duration" => DURATIONS.join(" | ") },
                  example: { "damage_replacement" => { "to" => { "triggering" => "player" }, "permanents" => true,
                                                       "multiply" => 2, "duration" => "until_your_next_turn" } }

        attr_reader :multiply, :plus, :combat, :duration

        def self.keys = %w[to permanents combat multiply plus duration if]

        def setup(params, errors, path)
          modes = %w[multiply plus].select { params.key?(it) }
          errors << "#{path}: needs exactly one of multiply, plus" unless modes.size == 1
          @multiply = params.key?("multiply") ? Mechanics.integer_param(params, :multiply, errors, path, min: 2) : nil
          @plus = params.key?("plus") ? Amount.build(params["plus"], errors, "#{path}.plus", targets_count: @targets_count) : nil
          @permanents = Mechanics.flag_param(params, :permanents, errors, path)
          @combat = DamageEvents.parse_combat(params, errors, path)
          @duration = Mechanics.fetch_param(params, :duration) || "end_of_turn"
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
        end

        def apply(engine, ctx)
          to = refs(engine, ctx)
          details = { "to" => to, "permanents" => @permanents == true, "combat" => combat, "duration" => duration }
          multiply ? details["multiply"] = multiply : details["plus"] = [plus.value(engine, ctx), 0].max
          engine.add_continuous_effect!("damage_replacement", ctx, to, details)
        end

        def to_s
          instead = multiply ? "#{multiply} times that damage" : "that much plus #{plus}"
          "#{"#{combat} " if combat}damage to #{to}#{" and their permanents" if @permanents}: #{instead} instead"
        end
      end

      # "Damage can't be prevented this turn." (CR 615.12)
      class DamageUnpreventableEffect < Effect
        primitive :effect, :damage_unpreventable,
                  description: "Until end of turn, damage (`combat`: combat | noncombat only) can't be prevented.",
                  rules: %w[615.12 611.2a],
                  params: { "combat" => "combat | noncombat" },
                  example: "damage_unpreventable"

        attr_reader :combat

        def self.keys = %w[combat if]
        def self.default_to = "you"

        def setup(params, errors, path) = @combat = DamageEvents.parse_combat(params, errors, path)
        def apply(engine, ctx) = engine.add_continuous_effect!("damage_unpreventable", ctx, [], "combat" => combat)
        def to_s = "#{"#{combat} " if combat}damage can't be prevented this turn"
      end
    end
  end
end
