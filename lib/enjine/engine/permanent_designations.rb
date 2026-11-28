# frozen_string_literal: true

module Enjine
  class Engine
    # Designations of a permanent that last until it leaves the battlefield and aren't copiable values: "solved"
    # (a Case, CR 720.3b) and "harnessed" (CR 701.64b). Kept in the permanent's memory, so a new object (CR 400.7)
    # has neither. Abilities that work only while it has one: Mechanics::Abilities::DesignatedAbility; conditions
    # {"solved": true} / {"harnessed": true}.
    module PermanentDesignations
      NAMES = %w[solved harnessed].freeze

      def designated?(obj, designation) = obj.zone == :battlefield && obj.memory[designation] == true

      # CR 720.3a, 701.64a: "if it isn't [designated], it becomes [designated]". Only a permanent can
      # (CR 701.64b). Returns whether it changed.
      def designate!(obj, designation)
        return false unless obj.zone == :battlefield && !designated?(obj, designation)

        obj.memory[designation] = true
        emit Events::PermanentDesignated.new(object: obj.id, designation: designation)
        true
      end

      # The designations a permanent has, for views.
      def permanent_designations(obj) = NAMES.select { designated?(obj, it) }
    end
    include PermanentDesignations
  end
end
