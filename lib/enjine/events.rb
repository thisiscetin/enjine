# frozen_string_literal: true

module Enjine
  # Typed, serializable game events. Every state change emits one.
  #
  # Players are referenced by name. Each event knows how to present itself to a
  # viewer (a player name or :observer); hidden information is redacted.
  module Events
    PUBLIC_ZONES = %w[battlefield graveyard stack exile].freeze
    REGISTRY = {} # rubocop:disable Style/MutableConstant -- extension registry

    # Behavior shared by every event class.
    module Base
      def type = self.class.event_type

      def to_h = { "type" => type }.merge(super.transform_keys(&:to_s))

      # Hash form for one viewer. Defaults to the full event.
      def for_viewer(_viewer) = to_h
    end

    def self.define(name, *fields, &)
      klass = Data.define(*fields, &)
      klass.include(Base)
      klass.define_singleton_method(:event_type) { name.to_s }
      REGISTRY[name.to_s] = klass
      klass
    end

    def self.from_h(hash)
      hash = hash.transform_keys(&:to_s)
      klass = REGISTRY.fetch(hash["type"]) { raise ArgumentError, "unknown event #{hash["type"].inspect}" }
      klass.new(**klass.members.to_h { |m| [m, hash[m.to_s]] })
    end

    def self.zone_visible?(zone, owner, viewer)
      viewer == :observer || PUBLIC_ZONES.include?(zone) || (zone == "hand" && viewer == owner)
    end

    GameStarted = define(:game_started, :players, :seed)
    DieRolled = define(:die_rolled, :winner)
    StartingPlayerChosen = define(:starting_player_chosen, :chooser, :choice, :starting_player)
    LibraryShuffled = define(:library_shuffled, :player)
    MulliganDeclared = define(:mulligan_declared, :player, :choice)
    MulliganTaken = define(:mulligan_taken, :player, :mulligans)
    HandKept = define(:hand_kept, :player, :mulligans)
    TurnBegan = define(:turn_began, :turn, :active)
    StepBegan = define(:step_began, :turn, :step, :phase)
    PriorityPassed = define(:priority_passed, :player)
    Tapped = define(:tapped, :object)
    Untapped = define(:untapped, :object)
    ManaAdded = define(:mana_added, :player, :mana, :source)
    ManaEmptied = define(:mana_emptied, :player, :mana)
    PlayerLost = define(:player_lost, :player, :reason)
    GameEnded = define(:game_ended, :winner, :reason)
    TargetChosen = define(:target_chosen, :player, :object, :target)
    ManaPaid = define(:mana_paid, :player, :mana, :object)
    SpellCast = define(:spell_cast, :player, :object, :card, :targets)
    AbilityActivated = define(:ability_activated, :player, :object, :card, :source, :ability, :targets)
    CastCancelled = define(:cast_cancelled, :player, :object, :card)
    Resolved = define(:resolved, :object, :card, :kind)
    Fizzled = define(:fizzled, :object, :card)
    DamageDealt = define(:damage_dealt, :source, :target, :amount)
    LifeChanged = define(:life_changed, :player, :from, :to)
    CountersChanged = define(:counters_changed, :object, :counter, :from, :to)
    EffectStarted = define(:effect_started, :kind, :affected, :details)
    EffectsEnded = define(:effects_ended, :count)
    AttackerDeclared = define(:attacker_declared, :object, :target)
    BlockerDeclared = define(:blocker_declared, :object, :attacker)
    DamageAssigned = define(:damage_assigned, :attacker, :blocker)
    AbilityTriggered = define(:ability_triggered, :player, :source, :card, :ability)
    TriggerPutOnStack = define(:trigger_put_on_stack, :player, :object, :source, :card, :ability, :targets)
    TriggerRemoved = define(:trigger_removed, :player, :source, :card, :reason)
    TokenCeased = define(:token_ceased, :object, :card, :zone)
    LibraryReordered = define(:library_reordered, :player, :top, :bottom)
    Attached = define(:attached, :object, :to) # CR 701.3
    Unattached = define(:unattached, :object, :from) # CR 701.3d

    # A card moved between zones; old_id stops existing and new_id is born (CR 400.7).
    ZoneChanged = define(:zone_changed, :card, :old_id, :new_id, :owner, :from, :to, :reason) do
      def for_viewer(viewer)
        if Events.zone_visible?(from, owner, viewer) || Events.zone_visible?(to, owner, viewer)
          to_h
        else
          { "type" => type, "owner" => owner, "from" => from, "to" => to, "reason" => reason }
        end
      end
    end
  end
end
