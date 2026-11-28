# frozen_string_literal: true

module Enjine
  class Engine
    # Shortcuts used while one decision's legal options are computed (Engine#options). Nothing changes state
    # meanwhile, so facts can be found once and kept in `@options_memo` (dropped when the options are done; never
    # carried to another decision), and some candidates can be ruled out before the full check. Each shortcut gives
    # exactly the answer of the full check; script/determinism_digest.rb compares whole games option by option.
    module OptionsMemo
      EMPTY_LIST = [].freeze

      # The memo table `key` of the decision whose options are being computed; outside that, a fresh table that is
      # thrown away (so the same code answers, only without keeping anything).
      def options_memo(key, identity: false)
        @options_memo&.[](key) || begin
          table = identity ? {}.compare_by_identity : {}
          @options_memo[key] = table if @options_memo
          table
        end
      end

      # On the battlefield (Engine::Characteristics#chars): the layer pass's result, or the copiable values of an
      # object no effect modifies. While legal options are computed it is kept for the decision under the object's id
      # (ids are never reused, CR 400.7), but never mid-pass (`@layering`), when it is still partial.
      def board_chars(object)
        return board_characteristics.fetch(object.id) { copy_base(object) } if @options_memo.nil? || @layering

        @options_memo[object.id] ||= board_characteristics.fetch(object.id) { copy_base(object) }
      end

      # Permanents `index` controls whose static abilities let them play cards from other zones
      # (Engine::Permissions#scan_permission_sources): asked for the cast and the land options and by each card.
      def permission_sources(index)
        options_memo(:permission_sources)[index] ||= scan_permission_sources(index)
      end

      # The play methods of a candidate (Engine::Permissions#play_methods): the cast and the land options both ask.
      def candidate_play_methods(index, ref, obj, sources)
        (options_memo(:play_methods)[index] ||= {})[ref] ||= play_methods(index, obj, sources)
      end

      # Whether Engine::Permissions#candidate_methods can skip the candidate `obj` of `index` (`plain`: no permanent
      # lets them play cards from other zones and no card was granted an ability or an alternative cost; `land`:
      # only lands are asked for):
      # - an exiled card `index` doesn't own can only be played by a permission effect of theirs naming it
      #   (Engine::Permissions#granted_methods; every other method needs them to own the card, CR 108.3);
      # - while `plain`, a card in a graveyard or library only by an ability of its own (#unplayable_elsewhere?);
      # - for the land options, a card that isn't a land (seen face up, CR 406.3a).
      def unplayable_candidate?(index, obj, plain, land)
        return true if obj.zone == :exile && obj.owner != index && !permission_named_ids(index).include?(obj.id)

        (plain && unplayable_elsewhere?(obj)) || (land && !face_up(obj.id) { chars(obj).land? })
      end

      # The ids of the objects permission effects of `index` name (Engine::Permissions#granted_methods), once per
      # decision.
      def permission_named_ids(index)
        options_memo(:permission_named)[index] ||=
          state.effects.flat_map { it["kind"] == "permission" && it["controller"] == index ? it["affected"] : [] }
      end

      # The abilities of `chars` (Characteristics) of one kind, in order. Indexed once per Characteristics object
      # while legal options are computed (it is immutable, and the options ask each card about its kicker,
      # additional costs and so on several times).
      def abilities_of_kind(chars, kind)
        by_kind = options_memo(:abilities_by_kind, identity: true)
        (by_kind[chars] ||= chars.abilities.map(&:ability).group_by(&:kind).each_value(&:freeze)).fetch(kind, EMPTY_LIST)
      end

      # While no effect grants cards abilities (Engine::Casting#own_abilities_only?), a card that isn't a copy has
      # only abilities its card's faces have, printed or nested (Engine::Characteristics#off_board_chars: a
      # characteristic-defining power and toughness or max speed add no other), so the facts of
      # Engine::Casting#card_off_board answer for its characteristics.
      def printed_faces_only?(obj, own_abilities_only)
        own_abilities_only && !obj.memory.key?("copy_except") && !obj.memory.key?("copy_effects")
      end

      # ---- the mana pre-check (CR 601.2f-h) ----------------------------------------------------

      # An upper bound on how many units ManaSources#mana_units could ever list for `index`, whatever the purpose
      # or excluded source. ManaSources#covers? needs at least a cost's mana value in units (each unit pays one
      # symbol, CR 601.2h), so ManaSources#affordable? rejects a cost above the bound without building the units for
      # each card, and the answer is the same. It counts:
      # - every mana in the pool, restricted or not (#pool_units counts no more);
      # - for each mana ability of #all_mana_sources, its largest outcome, ignoring "spend only" restrictions and
      #   mana costs (#source_units counts one source's largest outcome at most, CR 605);
      # - twice each untapped permanent `index` controls that isn't a mana source: once for convoke or improvise
      #   (CR 702.51a, 702.126a; #convoke_units counts only those) and once for waterbend (CR 701.67a;
      #   #waterbend_units counts only those).
      def mana_unit_bound(index)
        options_memo(:mana_unit_bound)[index] ||= begin
          pl = player(index)
          sources = all_mana_sources(index)
          ids = sources.map(&:first)
          helpers = state.battlefield.count { |id| (obj = object(id)).controller == index && !obj.tapped && !ids.include?(id) }
          pl.mana_pool.sum { |_, n| [n, 0].max } + pl.restricted_mana.size + (2 * helpers) +
            sources.sum { |id, ref| chars(id).ability(ref).outcomes(self, object(id)).map(&:size).max.to_i }
        end
      end

      # No effect gives a card off the battlefield an ability (CR 113.6b): each has only its own (and its copiable
      # values'), so the quick nos below hold.
      def own_abilities_only? = state.effects.none? { it["kind"] == "card_ability" }

      # A card that isn't a copy, none of whose faces has an activated ability functioning from the zone it's in
      # (CardDefinition#activation_zones, CR 113.6): nothing of it can be activated there.
      def no_activations_here?(obj)
        !obj.memory.key?("copy_except") && !obj.memory.key?("copy_effects") &&
          !card_off_board(obj.card)[:activation_zones].include?(obj.zone)
      end

      # What a card's faces can do off the battlefield (CardDefinition#plays_itself?, #activation_zones,
      # #special_actions?) and the fewest colored and hybrid mana symbols in any face's mana cost (0 if a face has
      # none; Engine::OptionsMemo#mana_out_of_reach?), once per card: printed facts that never change.
      def card_off_board(card)
        (@card_off_board ||= {}.compare_by_identity)[card] ||= catalog.fetch(card).faces.then do |faces|
          { plays_itself: faces.any?(&:plays_itself?), activation_zones: faces.flat_map(&:activation_zones).uniq,
            special_actions: faces.any?(&:special_actions?),
            colored_floor: faces.map { |face| (cost = face.mana_cost) ? cost.colored.values.sum + cost.hybrid.size : 0 }.min }
        end
      end

      # A quick no for Engine::Casting#castable?: mana can't pay the card's colored and hybrid symbols. Casting from
      # the hand pays the spell's own mana cost, or the kicked cost with more on top (an alternative cost is a
      # method, Engine::Permissions), and cost changes add or remove only generic mana (CR 601.2f; X is 0 until
      # announced, CR 107.3g). So the total cost's mana value is at least that many symbols (each hybrid one at
      # least 1, CR 202.3f), and ManaSources#affordable? would find fewer units than that (#mana_unit_bound). The
      # spell's mana cost is that of one of its card's faces: the characteristics of a card that is a copy (memory
      # "copy_except", "copy_effects") may say otherwise, so it gets the full look.
      def mana_out_of_reach?(index, obj)
        return false unless @options_memo
        return false if obj.memory.key?("copy_except") || obj.memory.key?("copy_effects")

        card_off_board(obj.card)[:colored_floor] > mana_unit_bound(index)
      end
    end

    include OptionsMemo
  end
end
