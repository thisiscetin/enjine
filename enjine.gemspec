# frozen_string_literal: true

require_relative "lib/enjine/version"

Gem::Specification.new do |spec|
  spec.name = "enjine"
  spec.version = Enjine::VERSION
  spec.authors = ["Mehmet Cetin"]
  spec.email = ["thisiscetin@gmail.com"]

  spec.summary = "A deterministic, rules-accurate Magic: The Gathering engine for the Standard format."
  spec.description = "Enjine runs two-player Magic: The Gathering games following the " \
                     "Comprehensive Rules, exposing every step as an atomic decision API. " \
                     "It targets the mechanics of the Standard-legal sets."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"
  spec.homepage = "https://github.com/thisiscetin/enjine"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "#{spec.homepage}/blob/main/docs/guides/api.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "exe/*", "docs/**/*.md", "README.md", "SUPPORTED.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.bindir = "exe"
  spec.executables = ["enjine"]
  spec.require_paths = ["lib"]
end
