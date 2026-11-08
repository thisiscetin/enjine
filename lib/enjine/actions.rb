# frozen_string_literal: true

module Enjine
  # Actions a player can take while holding priority. Each action class has:
  #   .options(engine, player_index) -> Array of option Hashes
  #   .perform(engine, player_index, option)
  # Adding a new kind of action (cast a spell, activate an ability, ...) means adding
  # one class and registering it here.
  module Actions
    PRIORITY = [] # rubocop:disable Style/MutableConstant -- extension registry
    BY_TYPE = {} # rubocop:disable Style/MutableConstant -- extension registry

    def self.register(type, klass)
      PRIORITY << klass
      BY_TYPE[type] = klass
    end

    def self.fetch(type) = BY_TYPE.fetch(type)
  end
end
