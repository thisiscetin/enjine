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
    # CR 702.26: phasing isn't a zone change; `indirectly`: it phased out attached to another permanent.
    PhasedOut = define(:phased_out, :object, :indirectly)
    PhasedIn = define(:phased_in, :object)
    ManaAdded = define(:mana_added, :player, :mana, :source)
    ManaEmptied = define(:mana_emptied, :player, :mana)
    PlayerLost = define(:player_lost, :player, :reason)
    GameEnded = define(:game_ended, :winner, :reason)
    TargetChosen = define(:target_chosen, :player, :object, :target)
    XAnnounced = define(:x_announced, :player, :object, :value)
    ManaPaid = define(:mana_paid, :player, :mana, :object)
    # `during_resolution`: cast while another spell or ability resolves (CR 608.2g), ignoring timing.
    SpellCast = define(:spell_cast, :player, :object, :card, :targets, :during_resolution) do
      def initialize(player:, object:, card:, targets:, during_resolution: false) = super
    end
    AbilityActivated = define(:ability_activated, :player, :object, :card, :source, :ability, :targets)
    CastCancelled = define(:cast_cancelled, :player, :object, :card)
    Resolved = define(:resolved, :object, :card, :kind)
    Fizzled = define(:fizzled, :object, :card)
    # `combat`: dealt as combat damage (CR 510.2); triggers such as "deals combat damage to a player" read it.
    DamageDealt = define(:damage_dealt, :source, :target, :amount, :combat) do
      def initialize(source:, target:, amount:, combat: false) = super
    end
    # A life total changed. CR 119.9: a gain is a life gain event, a loss a life loss event.
    LifeChanged = define(:life_changed, :player, :from, :to) do
      def gain = [to - from, 0].max
      def loss = [from - to, 0].max
    end
    CountersChanged = define(:counters_changed, :object, :counter, :from, :to)
    PlayerCountersChanged = define(:player_counters_changed, :player, :counter, :from, :to) # poison, rad, ... (CR 122.1)
    EmblemCreated = define(:emblem_created, :player, :object, :card) # CR 114.2
    # CR 705: a coin flip; `won` is nil for a flip no one wins or loses (CR 705.2).
    CoinFlipped = define(:coin_flipped, :player, :heads, :won)
    # CR 707.10: a copy of a spell put on the stack (not cast).
    SpellCopied = define(:spell_copied, :player, :object, :card, :original, :targets)
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
    # A card in a hidden zone is shown to every player (CR 701.20a); it doesn't leave its zone (701.20b).
    CardRevealed = define(:card_revealed, :player, :object, :card)
    # A player looks at cards in a hidden zone (CR 701.20e): only they (and the cards' owner) see which.
    LookedAt = define(:looked_at, :player, :owner, :objects, :cards) do
      def for_viewer(viewer)
        return to_h if viewer == :observer || viewer == player || viewer == owner

        { "type" => type, "player" => player, "owner" => owner, "count" => objects.size }
      end
    end
    ControlChanged = define(:control_changed, :object, :controller)
    ExtraTurnAdded = define(:extra_turn_added, :player) # CR 500.7
    TurnSkipped = define(:turn_skipped, :player) # CR 614.10
    DilemmaFaced = define(:dilemma_faced, :player, :object, :modes) # CR 700.17
    # Combat declarations once final (CR 508.3d "whenever [a player] attacks", 509.3c "becomes blocked").
    AttacksDeclared = define(:attacks_declared, :player, :attackers)
    BecameBlocked = define(:became_blocked, :object, :blockers)
    # Crew (CR 702.122): a creature tapped to pay a crew cost crews that Vehicle (702.122b); the Vehicle
    # becomes crewed as its crew ability resolves (702.122e), by the creatures in `crew`.
    CrewedVehicle = define(:crewed_vehicle, :object, :vehicle)
    BecameCrewed = define(:became_crewed, :object, :crew)
    # Saddle (CR 702.171): a creature tapped to pay a saddle cost saddles that Mount (702.171c); the Mount
    # becomes saddled (702.171b), by the creatures in `riders` when its saddle ability did it.
    SaddledMount = define(:saddled_mount, :object, :mount)
    BecameSaddled = define(:became_saddled, :object, :riders)
    # A player's speed changed (CR 702.179); `from` nil: they had no speed.
    SpeedChanged = define(:speed_changed, :player, :from, :to)
    # A player got a designation for the rest of the game, e.g. an enduring story (CR 702.195b).
    DesignationGained = define(:designation_gained, :player, :designation)
    # A permanent's class level became `level` (CR 717.2a).
    ClassLevelChanged = define(:class_level_changed, :object, :level)
    # CR 701.27a: a double-faced permanent turned over; `card` names the face now up (CR 712).
    Transformed = define(:transformed, :object, :card)
    # CR 723.3a-c: a permanent gained (`prepared` true) or lost the prepared designation.
    PreparedChanged = define(:prepared_changed, :object, :prepared)
    # A keyword action that abilities trigger on, once it's complete: "scry" / "surveil" N (CR 701.22, 701.25);
    # earthbend, waterbend, airbend and firebend (CR 701.66b, 701.67c, 701.65b, 702.189b).
    KeywordAction = define(:keyword_action, :player, :action, :amount)

    # A card moved between zones; old_id stops existing and new_id is born (CR 400.7). `lookers`: the card
    # was exiled face down, and only these players (by name) see which card it is (CR 406.3).
    ZoneChanged = define(:zone_changed, :card, :old_id, :new_id, :owner, :from, :to, :reason, :lookers) do
      def initialize(card:, old_id:, new_id:, owner:, from:, to:, reason:, lookers: nil) = super

      def for_viewer(viewer)
        if lookers && viewer != :observer && !lookers.include?(viewer)
          { "type" => type, "owner" => owner, "new_id" => new_id, "from" => from, "to" => to, "reason" => reason,
            "face_down" => true }
        elsif Events.zone_visible?(from, owner, viewer) || Events.zone_visible?(to, owner, viewer)
          to_h
        else
          { "type" => type, "owner" => owner, "from" => from, "to" => to, "reason" => reason }
        end
      end
    end
  end
end
