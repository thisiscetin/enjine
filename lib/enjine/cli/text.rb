# frozen_string_literal: true

module Enjine
  class CLI
    # Plain-text rendering of views, decisions, options and events.
    # Works only from the public API (views, history, options), never engine internals.
    class Text
      STEP_NAMES = {
        "untap" => "Untap", "upkeep" => "Upkeep", "draw" => "Draw", "precombat_main" => "Main 1",
        "beginning_of_combat" => "Beginning of Combat", "declare_attackers" => "Declare Attackers",
        "declare_blockers" => "Declare Blockers", "combat_damage" => "Combat Damage", "end_of_combat" => "End of Combat",
        "postcombat_main" => "Main 2", "end" => "End Step", "cleanup" => "Cleanup"
      }.freeze

      def initialize(game)
        @game = game
      end

      # ---- board -----------------------------------------------------------------

      def board(view)
        lines = [rule("Turn #{view["turn"]} · #{STEP_NAMES.fetch(view["step"].to_s, "Pregame")} · " \
                      "active: #{view["active"] || "-"} · priority: #{view["priority"] || "-"}")]
        viewer = view["viewer"]
        view["players"].sort_by { it["name"] == viewer ? 1 : 0 }.each { lines.concat(player_block(view, it)) }
        lines << "  Stack (top first): #{"empty" if view["stack"].empty?}"
        view["stack"].each { lines << "    #{stack_item(it)}" }
        view["effects"].each do |e|
          lines << "  Effect: +#{e["power"]}/+#{e["toughness"]} until end of turn on #{e["affected"].map do
            name_of(it)
          end.join(", ")}"
        end
        lines.join("\n")
      end

      def player_block(view, player)
        pool = player["mana_pool"].map { |t, n| "{#{t}}" * n }.join + player.fetch("restricted_mana", []).map { "{#{it["mana"]}}*" }.join
        poison = player["poison"].positive? ? " · poison #{player["poison"]}" : ""
        lines = ["", "  #{player["name"].upcase} — life #{player["life"]}#{poison} · " \
                     "library #{player["library_count"]} · hand #{player["hand_count"]} · " \
                     "graveyard #{player["graveyard"].size}#{" · mana pool #{pool}" unless pool.empty?}"]
        perms = view["battlefield"].select { it["controller"] == player["name"] }
        lands, others = perms.partition { it["type_line"].include?("Land") }
        lines << "    Lands:     #{lands.empty? ? "-" : lands.map { permanent(it) }.join(", ")}"
        lines << "    Permanents: #{"-" if others.empty?}"
        others.each { lines << "      #{permanent(it)}" }
        lines << "    Hand:      #{player["hand"].map { card(it) }.join(", ")}" if player["hand"]
        if player["library"]
          lines << "    Library (top first): #{player["library"].first(5).map do
            it["name"]
          end.join(", ")}#{" …" if player["library_count"] > 5}"
        end
        lines << "    Graveyard: #{player["graveyard"].map { it["name"] }.join(", ")}" unless player["graveyard"].empty?
        lines
      end

      def permanent(obj)
        parts = [obj["name"]]
        parts << "#{obj["power"]}/#{obj["toughness"]}" if obj.key?("power")
        parts << "loyalty #{obj["loyalty"]}" if obj.key?("loyalty")
        parts << obj["keywords"].map { it.tr("_", " ") }.join(", ") if obj["keywords"]
        parts << "damage #{obj["damage"]}" if obj["damage"].to_i.positive?
        obj.fetch("counters", {}).except("loyalty").each { |kind, n| parts << "#{n}×#{kind}" }
        parts << "tapped" if obj["tapped"]
        parts << "sick" if obj["summoning_sick"]
        parts << "attacking #{name_of(obj["attacking"])}" if obj["attacking"]
        parts << "blocking #{name_of(obj["blocking"])}" if obj["blocking"]
        "#{parts.join(" · ")} [#{obj["id"]}]"
      end

      def card(obj) = "#{obj["name"]}#{" #{obj["mana_cost"]}" if obj["mana_cost"]} [#{obj["id"]}]"

      def stack_item(obj)
        targets = obj["targets"].empty? ? "" : " → #{obj["targets"].map { name_of(it) }.join(", ")}"
        "#{obj["name"]}#{" (#{"+" if obj["loyalty_cost"].to_i.positive?}#{obj["loyalty_cost"]})" if obj["loyalty_cost"]} " \
          "controlled by #{obj["controller"]}#{targets} [#{obj["id"]}]"
      end

      # ---- decisions & options -------------------------------------------------

      def decision(decision)
        extra = case decision.kind
                when "pay_cost" then " — left to pay: #{decision.details["remaining"]}"
                when "discard" then " — discard #{decision.details["count"]} more"
                when "bottom" then " — put #{decision.details["count"]} more on the bottom"
                when "assign_damage" then " — #{name_of(decision.details["attacker"])}: #{decision.details["remaining"]} damage left"
                when "choose_target" then " — target ##{decision.details["index"] + 1}"
                when "choose_target_count" then " — how many for target ##{decision.details["index"] + 1}"
                else ""
                end
        "▶ #{decision.player.upcase} must act: #{decision.kind.tr("_", " ")}#{extra}"
      end

      def option(opt)
        case opt[:type]
        when "pass" then "Pass priority"
        when "play_land" then "Play land #{name_of(opt[:object])}"
        when "cast" then "Cast #{name_of(opt[:object])} #{cost_of(opt[:object])}".rstrip
        when "activate" then "Activate #{name_of(opt[:object])}: #{ability_text(opt[:object], opt[:ability])}"
        when "activate_mana"
          "Tap #{name_of(opt[:object])} for #{opt[:mana] || "mana"} (#{ability_text(opt[:object], opt[:ability])})"
        when "pay_mana"
          "Pay {#{opt[:mana]}} from mana pool#{" (restricted)" if opt[:restricted]}#{" (made by an artifact)" if opt[:from]}"
        when "target" then "Target #{name_of(opt[:target])}"
        when "cost" then "Use #{name_of(opt[:object])} to pay the cost"
        when "cancel" then "Cancel (rewind this cast/activation)"
        when "attack" then "Attack #{name_of(opt[:target])} with #{name_of(opt[:object])}"
        when "block" then "Block #{name_of(opt[:attacker])} with #{name_of(opt[:object])}"
        when "assign" then "Assign 1 damage to #{name_of(opt[:object])}"
        when "done" then "Done"
        when "discard", "bottom", "find" then "#{opt[:type].capitalize} #{name_of(opt[:object])}"
        when "keep" then "Keep hand"
        when "call" then "Call #{opt[:call]}"
        when "mulligan" then "Mulligan"
        when "play", "draw" then "#{opt[:type].capitalize} first"
        else opt.inspect
        end
      end

      # ---- events --------------------------------------------------------------

      def events(list) = list.filter_map { event(it) }

      def event(ev)
        case ev["type"]
        when "zone_changed" then zone_changed(ev)
        when "turn_began" then "══ Turn #{ev["turn"]}: #{ev["active"]} ══"
        when "step_began" then "· #{STEP_NAMES.fetch(ev["step"], ev["step"])}"
        when "priority_passed" then "#{ev["player"]} passes"
        when "tapped" then "#{name_of(ev["object"])} becomes tapped"
        when "untapped" then "#{name_of(ev["object"])} untaps"
        when "mana_added" then "#{ev["player"]} adds #{ev["mana"]}"
        when "mana_paid" then "#{ev["player"]} pays #{ev["mana"]}"
        when "mana_emptied" then "#{ev["player"]}'s unused #{ev["mana"]} empties"
        when "spell_cast" then "#{ev["player"]} casts #{name_of(ev["object"])}#{targets(ev["targets"])}"
        when "ability_activated" then "#{ev["player"]} activates #{name_of(ev["source"])}'s ability#{targets(ev["targets"])}"
        when "target_chosen" then "#{ev["player"]} targets #{name_of(ev["target"])}"
        when "cast_cancelled" then "#{ev["player"]} cancels casting #{card_name(ev["card"])}"
        when "resolved" then "#{card_name(ev["card"])}#{" ability" if ev["kind"] == "ability"} resolves"
        when "fizzled" then "#{card_name(ev["card"])} doesn't resolve: its targets are gone"
        when "damage_dealt" then "#{name_of(ev["source"])} deals #{ev["amount"]} damage to #{name_of(ev["target"])}"
        when "life_changed" then "#{ev["player"]}: life #{ev["from"]} → #{ev["to"]}"
        when "counters_changed" then "#{name_of(ev["object"])}: #{ev["counter"]} counters #{ev["from"]} → #{ev["to"]}"
        when "effect_started" then pumped(ev)
        when "effects_ended" then "#{ev["count"]} until-end-of-turn effect(s) end"
        when "attacker_declared" then "#{name_of(ev["object"])} attacks #{name_of(ev["target"])}"
        when "blocker_declared" then "#{name_of(ev["object"])} blocks #{name_of(ev["attacker"])}"
        when "damage_assigned" then "1 damage of #{name_of(ev["attacker"])} assigned to #{name_of(ev["blocker"])}"
        when "player_lost" then "#{ev["player"]} LOSES (#{ev["reason"]})"
        when "game_ended" then "GAME OVER — #{result(ev)}"
        when "library_shuffled" then "#{ev["player"]} shuffles their library"
        when "card_revealed" then "#{ev["player"]} reveals #{card_name(ev["card"])}"
        when "die_rolled" then "#{ev["winner"]} wins the die roll"
        when "starting_player_chosen" then "#{ev["chooser"]} chooses to #{ev["choice"]}: #{ev["starting_player"]} goes first"
        when "mulligan_declared" then "#{ev["player"]} declares: #{ev["choice"]}"
        when "mulligan_taken" then "#{ev["player"]} mulligans (#{ev["mulligans"]} so far)"
        when "hand_kept" then "#{ev["player"]} keeps#{" after #{ev["mulligans"]} mulligan(s)" if ev["mulligans"].positive?}"
        when "game_started" then "Game started: #{ev["players"].join(" vs ")} (seed #{ev["seed"]})"
        else mechanic_event(ev)
        end
      end

      # Events of particular mechanics; attacks_declared is told by its attacker_declared events.
      def mechanic_event(ev)
        case ev["type"]
        when "attacks_declared" then nil
        when "ability_triggered" then "#{card_name(ev["card"])}'s ability triggers"
        when "trigger_put_on_stack" then "#{card_name(ev["card"])}'s triggered ability goes on the stack#{targets(ev["targets"])}"
        when "trigger_removed" then "#{card_name(ev["card"])}'s triggered ability is removed (#{ev["reason"]})"
        when "ability_countered" then "#{card_name(ev["card"])}'s ability is countered"
        when "spell_copied" then "#{ev["player"]} copies #{card_name(ev["card"])}#{targets(ev["targets"])}"
        when "x_announced" then "#{ev["player"]} announces X = #{ev["value"]}"
        when "payment_finished" then "#{ev["player"]} #{ev["outcome"]}"
        when "attached" then "#{name_of(ev["object"])} is attached to #{name_of(ev["to"])}"
        when "unattached" then "#{name_of(ev["object"])} becomes unattached from #{name_of(ev["from"])}"
        when "control_changed" then "#{ev["controller"]} gains control of #{name_of(ev["object"])}"
        when "became_blocked" then "#{name_of(ev["object"])} is blocked"
        when "crewed_vehicle" then "#{name_of(ev["object"])} crews #{name_of(ev["vehicle"])}"
        when "became_crewed" then "#{name_of(ev["object"])} becomes crewed"
        when "transformed" then "#{name_of(ev["object"])} transforms into #{card_name(ev["card"])}"
        when "prepared_changed" then "#{name_of(ev["object"])} #{ev["prepared"] ? "becomes prepared" : "is no longer prepared"}"
        when "phased_out" then "#{name_of(ev["object"])} phases out"
        when "phased_in" then "#{name_of(ev["object"])} phases in"
        when "token_ceased" then "#{card_name(ev["card"])} token ceases to exist"
        when "library_reordered" then "#{ev["player"]} puts #{Array(ev["top"]).size} on top and #{Array(ev["bottom"]).size} on the bottom"
        when "looked_at" then "#{ev["player"]} looks at #{Array(ev["objects"]).size} of #{ev["owner"]}'s cards"
        when "dilemma_faced" then "#{ev["player"]} faces a dilemma"
        when "extra_turn_added" then "#{ev["player"]} will take an extra turn"
        when "turn_skipped" then "#{ev["player"]} skips a turn"
        when "emblem_created" then "#{ev["player"]} gets an emblem from #{card_name(ev["card"])}"
        when "player_counters_changed" then "#{ev["player"]}: #{ev["counter"]} counters #{ev["from"]} → #{ev["to"]}"
        when "speed_changed" then "#{ev["player"]}: speed #{ev["from"]} → #{ev["to"]}"
        when "coin_flipped"
          "#{ev["player"]} flips #{ev["heads"] ? "heads" : "tails"}#{{ true => " and wins", false => " and loses" }[ev["won"]]}"
        when "keyword_action" then "#{ev["player"]} #{ev["action"].to_s.tr("_", " ")}#{" #{ev["amount"]}" if ev["amount"]}"
        else "#{ev["type"]}: #{ev.except("type")}"
        end
      end

      def pumped(ev)
        verb = ev["affected"].size == 1 ? "gets" : "get"
        "#{ev["affected"].map do
          name_of(it)
        end.join(", ")} #{verb} +#{ev["details"]["power"]}/+#{ev["details"]["toughness"]} until end of turn"
      end

      def zone_changed(ev)
        what = ev["card"] ? card_name(ev["card"]) : "a card"
        case ev["reason"]
        when "draw" then "#{ev["owner"]} draws #{what}"
        when "play_land" then "#{ev["owner"]} plays #{what}"
        when "cast", "mulligan" then nil
        when "resolve" then ev["to"] == "battlefield" ? "#{what} enters the battlefield" : "#{what} goes to the graveyard"
        when "sba_lethal_damage" then "#{what} dies (lethal damage)"
        when "sba_toughness" then "#{what} dies (0 toughness)"
        when "sba_loyalty" then "#{what} is put into the graveyard (0 loyalty)"
        when "countered" then "#{what} is countered"
        when "mulligan_bottom" then "#{ev["owner"]} puts #{what} on the bottom of their library (mulligan)"
        else "#{ev["owner"]}'s #{what}: #{ev["from"]} → #{ev["to"]} (#{ev["reason"]})"
        end
      end

      def result(res) = res["winner"] ? "#{res["winner"]} wins (#{res["reason"]})" : "draw (#{res["reason"]})"

      # ---- helpers -------------------------------------------------------------

      def rule(text) = "━━ #{text} #{"━" * [4, 76 - text.size].max}"

      def name_of(ref)
        return "-" if ref.nil?
        return ref.delete_prefix("player:") if ref.start_with?("player:")

        obj = @game.state.objects[ref]
        obj ? "#{@game.catalog.fetch(obj.card).name}#{" ability" if obj.ability?}" : card_name(ref.split("#").first)
      end

      def card_name(card_id) = @game.catalog[card_id]&.name || card_id.to_s

      def cost_of(id) = @game.catalog.fetch(@game.state.object(id).card).mana_cost.to_s

      # A granted ability ("granted:<card>:<ref>") lives in the granting card's data.
      def ability_text(id, ref)
        card, inner = ref.start_with?("granted:") ? ref.delete_prefix("granted:").split(":", 2) : [@game.state.object(id).card, ref]
        @game.catalog.fetch(card).ability(inner).to_s
      end

      def targets(list) = list.nil? || list.empty? ? "" : " targeting #{list.map { name_of(it) }.join(", ")}"
    end
  end
end
