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
        data["amount"] = 0 if applicable(engine, proposal, :prevent_damage).any?
        engine.state.effects.select { it["kind"] == "prevent_damage" }.each do |effect|
          break if data["amount"].zero?
          next unless PreventionEffect.applies?(effect, data)

          PreventionEffect.use!(engine, effect, data)
        end
      end

      # Protection from the source's quality prevents the damage (CR 702.16e).
      def protected?(engine, data)
        target = engine.state.objects[data["target"]]
        target&.zone == :battlefield && engine.protected_from?(target, engine.state.objects[data["source"]])
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
      end

      # Prevention effects started by a resolved spell or ability (state.effects, kind "prevent_damage"):
      # {"to": [refs] | nil, "by": [refs] | nil, "combat": "combat" | "noncombat" | nil, "remaining": n | nil}.
      module PreventionEffect
        module_function

        def applies?(effect, data)
          (effect["to"].nil? || effect["to"].include?(data["target"])) &&
            (effect["by"].nil? || effect["by"].include?(data["source"])) &&
            DamageEvents.combat_ok?(effect["combat"], data["combat"])
        end

        # A shield prevents that much and is used up (CR 615.7); without one, all of it is prevented.
        def use!(engine, effect, data)
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
                               "`combat`: combat | noncombat) is prevented. \"To and by this creature\" is two of them.",
                  rules: %w[615.1 615.1a 615.6],
                  params: { "by" => "damage scope", "to" => "damage scope", "combat" => "combat | noncombat" },
                  example: { "prevent_damage" => { "to" => { "each" => "creature", "controller" => "you", "other" => true },
                                                   "combat" => "noncombat" } }

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[by to combat], errors, path)
          new(*parse_scopes(params, errors, path))
        end

        def kind = :prevent_damage
        def to_s = "prevent all #{scope_text}"
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
      # this turn" (CR 615.1, 615.3, 615.7).
      class PreventDamageEffect < Effect
        DURATIONS = %w[end_of_turn until_your_next_turn].freeze

        primitive :effect, :prevent_damage,
                  description: "For the `duration` (end_of_turn by default, or until_your_next_turn), damage that " \
                               "would be dealt to the referenced players and permanents (`to`) and/or by the " \
                               "referenced sources (`by`) is prevented (`combat`: combat | noncombat only). With " \
                               "`next`, it is a shield that prevents only the next that much damage (CR 615.7). " \
                               "The referenced objects are fixed as it resolves.",
                  rules: %w[615.1 615.3 615.7 611.2a],
                  params: { "to" => "selector (recipients)", "by" => "selector (sources)", "combat" => "combat | noncombat",
                            "next" => "amount (a shield)", "duration" => DURATIONS.join(" | ") },
                  example: { "prevent_damage" => { "to" => { "target" => 0 }, "combat" => "combat" } }

        attr_reader :by, :combat, :shield, :duration

        def self.keys = %w[to by combat next duration if]

        # `to` may be left out when `by` names the sources ("damage that would be dealt by target creature").
        def self.build(params, errors, path, targets_count: 0, results_count: 0, **)
          return super if Mechanics.fetch_param(params, :to) || !Mechanics.fetch_param(params, :by)

          Mechanics.check_keys(params, keys, errors, path)
          new(to: nil, params: params, errors: errors, path: path, targets_count: targets_count, results_count: results_count)
        end

        def setup(params, errors, path)
          raw_by = Mechanics.fetch_param(params, :by)
          @by = raw_by && Selector.build(raw_by, errors, "#{path}.by", targets_count: @targets_count, results_count: @results_count)
          @combat = DamageEvents.parse_combat(params, errors, path)
          raw_next = Mechanics.fetch_param(params, :next)
          @shield = raw_next && Amount.build(raw_next, errors, "#{path}.next", targets_count: @targets_count, min: 1,
                                                                               results_count: @results_count)
          @duration = Mechanics.fetch_param(params, :duration) || "end_of_turn"
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
        end

        def apply(engine, ctx)
          to = self.to && refs(engine, ctx)
          by = @by&.resolve(engine, ctx)
          details = { "to" => to, "by" => by, "combat" => combat, "duration" => duration }
          details["remaining"] = shield.value(engine, ctx) if shield
          engine.add_continuous_effect!("prevent_damage", ctx, (to || []) + (by || []), details)
        end

        def to_s
          what = shield ? "the next #{shield}" : "all"
          ["prevent #{what} #{"#{combat} " if combat}damage", to && "to #{to}", by && "by #{by}"].compact.join(" ")
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
