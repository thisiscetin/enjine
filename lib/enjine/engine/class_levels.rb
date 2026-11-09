# frozen_string_literal: true

module Enjine
  class Engine
    # Class levels (CR 717.2b): a designation of a permanent, kept in its memory ("class_level"), not copiable,
    # and lost when it leaves the battlefield (CR 400.7). Without one a permanent is level 1 (CR 717.2d).
    module ClassLevels
      NO_LEVELS = [].freeze

      def class_level(obj) = obj.memory.fetch("class_level", 1)

      def set_class_level!(obj, level)
        obj.memory["class_level"] = level
        emit Events::ClassLevelChanged.new(object: obj.id, level: level)
      end

      # The class level bars whose abilities apply: level N or greater (CR 717.2a).
      def active_class_levels(obj)
        level = obj.memory["class_level"] or return NO_LEVELS
        catalog.fetch(obj.card).ability_instances.select { it.ability.is_a?(Mechanics::Abilities::ClassLevel) && level >= it.ability.level }
      end
    end
    include ClassLevels
  end
end
