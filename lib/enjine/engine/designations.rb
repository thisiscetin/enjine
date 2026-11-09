# frozen_string_literal: true

module Enjine
  class Engine
    # Player designations that last for the rest of the game (PlayerState#designations), such as an enduring
    # story (CR 702.195b). They have no rules meaning of their own; conditions read them
    # (`{"designation": "enduring_story"}`, Mechanics::Condition::Designation).
    module Designations
      NAMES = %w[enduring_story].freeze

      def designation?(index, designation) = player(index).designations.to_a.include?(designation)

      def gain_designation!(index, designation)
        return if designation?(index, designation)

        (player(index).designations ||= []) << designation
        emit Events::DesignationGained.new(player: name(index), designation: designation)
      end

      # Storied (CR 702.195a): "Any time you control three or more permanents that are artifacts, Sagas, and/or
      # legendary and you don't have an enduring story, you have an enduring story for the rest of the game."
      # Checked whenever state-based actions are, so before triggered abilities are put on the stack
      # (CR 702.195c). Returns true when a player got one.
      def tell_enduring_stories!
        return false unless storied_card?

        told = state.players.each_index.select do |i|
          mine = state.battlefield.filter_map { (obj = object(it)).controller == i ? chars(obj) : nil }
          !designation?(i, "enduring_story") && mine.any? { it.keyword?(:storied) } && mine.count { story_piece?(it) } >= 3
        end
        told.each { gain_designation!(it, "enduring_story") }
        !told.empty?
      end

      private

      def story_piece?(chars) = chars.type?(:artifact) || chars.legendary? || chars.subtypes.include?(:saga)

      def storied_card?
        @storied_card = !catalog.find { it.keyword?(:storied) }.nil? unless defined?(@storied_card)
        @storied_card
      end
    end
    include Designations
  end
end
