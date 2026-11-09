# frozen_string_literal: true

require_relative "enjine/version"
require_relative "enjine/errors"
require_relative "enjine/rng"
require_relative "enjine/mana"
require_relative "enjine/primitive"
require_relative "enjine/mechanics"
# The shared bases load first; a mechanic file requires any other mechanic it builds on.
%w[selector values effects/base triggers/base filters/base costs/base abilities/stack_abilities].each do |f|
  require_relative "enjine/mechanics/#{f}"
end
Dir[File.join(__dir__, "enjine/mechanics/**/*.rb")].each { |f| require f }
require_relative "enjine/characteristics"
require "json"
require "digest"
require_relative "enjine/tokens"
require_relative "enjine/card_definition"
require_relative "enjine/catalog"
require_relative "enjine/deck"
require_relative "enjine/player"
require_relative "enjine/state"
require_relative "enjine/events"
require_relative "enjine/steps"
require_relative "enjine/frames"
require_relative "enjine/decisions"
Dir[File.join(__dir__, "enjine/decisions/*.rb")].each { |f| require f }
require_relative "enjine/actions"
%w[pass play_land activate_mana_ability cast special_action].each { |f| require_relative "enjine/actions/#{f}" }
require_relative "enjine/replacements"
require_relative "enjine/engine"
Dir[File.join(__dir__, "enjine/engine/**/*.rb")].each { |f| require f }
require_relative "enjine/snapshot"
require_relative "enjine/history"
require_relative "enjine/view"
require_relative "enjine/game"
require_relative "enjine/setup"

# Enjine: a deterministic, rules-accurate Magic: The Gathering engine.
# It knows no cards: every card arrives as data, in a deck or a DeckBuilder pool.
module Enjine
end
require_relative "enjine/agents/random"
require_relative "enjine/agents/busy"
require_relative "enjine/fuzz"
require_relative "enjine/rules_monitor"
