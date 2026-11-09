# frozen_string_literal: true

if ENV["COVERAGE"] != "0"
  require "simplecov"
  SimpleCov.start do
    enable_coverage :branch
    add_filter "/spec/"
    minimum_coverage line: 95, branch: 90
  end
end

require "enjine"
require "enjine/docs"
require "enjine/cli"
require "enjine/deck_builder"

Dir[File.join(__dir__, "support/**/*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.include ScenarioHelpers
end
