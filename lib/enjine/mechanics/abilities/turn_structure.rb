# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # Static abilities that change the rules of a turn for their controller (CR 305.2, 502.3).
      # They take no parameters and do nothing on their own: the engine looks for them by kind
      # (Engine::TurnStructure).
      class TurnRule < Primitive
        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          self::INSTANCE
        end

        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
      end

      # "You may play an additional land on each of your turns" (CR 305.2): each instance adds one to the
      # number of lands its controller can play each turn (Engine#land_plays_allowed).
      class AdditionalLandPlays < TurnRule
        primitive :ability, :additional_land_plays,
                  description: "Its controller may play an additional land on each of their turns. Each instance " \
                               "adds one land play (CR 305.2); lands put onto the battlefield by effects don't count.",
                  rules: %w[305.2 305.2a 305.2b 604.1], example: "additional_land_plays"

        INSTANCE = new.freeze

        def kind = :additional_land_plays
        def to_s = "You may play an additional land on each of your turns"
      end

      # "You may choose not to untap [this permanent] during your untap step" (CR 502.3): its controller is
      # asked in their untap step, while it's tapped (decision `untap_choice`).
      class MayNotUntap < TurnRule
        primitive :ability, :may_not_untap,
                  description: "Its controller may choose not to untap it during their untap step (decision " \
                               "`untap_choice`, asked only while it's tapped).",
                  rules: %w[502.3 604.1], example: "may_not_untap"

        INSTANCE = new.freeze

        def kind = :may_not_untap
        def to_s = "You may choose not to untap it during your untap step"
      end
    end
  end
end
