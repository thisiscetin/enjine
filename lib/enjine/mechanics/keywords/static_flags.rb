# frozen_string_literal: true

require_relative "evergreen"

module Enjine
  module Mechanics
    module Keywords
      # Rules modifications that work like a keyword: a flag on the object's characteristics that the
      # rules code checks, printed, handed out by a static ability (often a conditional one) or gained until end of
      # turn.
      {
        attacks_despite_defender: ["Defender doesn't stop this creature from attacking.", %w[702.3b 508.1c]],
        doesnt_untap: ["This permanent doesn't untap during its controller's untap step.", %w[502.3]]
      }.each { |name, (description, rules)| Evergreen.define(name, description, rules) }
    end
  end
end
