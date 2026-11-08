# frozen_string_literal: true

require_relative "enjine/version"
require_relative "enjine/errors"
require_relative "enjine/rng"
require_relative "enjine/mana"
require_relative "enjine/primitive"
require_relative "enjine/mechanics"
require_relative "enjine/mechanics/selector"
Dir[File.join(__dir__, "enjine/mechanics/**/*.rb")].each { |f| require f }
require_relative "enjine/card_definition"
require_relative "enjine/catalog"
require_relative "enjine/deck"
require_relative "enjine/player"
require_relative "enjine/state"
require_relative "enjine/events"
require_relative "enjine/steps"
require_relative "enjine/decisions"
Dir[File.join(__dir__, "enjine/decisions/*.rb")].each { |f| require f }
require_relative "enjine/actions"
%w[pass play_land activate_mana_ability cast].each { |f| require_relative "enjine/actions/#{f}" }
require_relative "enjine/engine"
Dir[File.join(__dir__, "enjine/engine/*.rb")].each { |f| require f }
require_relative "enjine/snapshot"
require_relative "enjine/history"
require_relative "enjine/view"
require_relative "enjine/game"
require_relative "enjine/setup"

# Enjine: a deterministic, rules-accurate Magic: The Gathering engine.
# Card pools are opt-in: require "enjine/card_pool/core".
module Enjine
end
require_relative "enjine/agents/random"
require_relative "enjine/fuzz"
