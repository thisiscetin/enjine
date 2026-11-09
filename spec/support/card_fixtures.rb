# frozen_string_literal: true

require "json"

# The invented cards the specs, fuzz and benchmarks play with (spec/fixtures/cards/*.json, one file per
# mechanic family), the deck builder's fixture pools (spec/fixtures/pools) and the example decks (examples/decks).
module CardFixtures
  ROOT = File.expand_path("../..", __dir__)

  module_function

  def cards = @cards ||= Dir[File.join(ROOT, "spec/fixtures/cards/*.json")].flat_map { read(it) }.freeze
  def catalog = Enjine::Catalog.from_definitions(cards)
  def pool(name) = read(File.join(ROOT, "spec/fixtures/pools/#{name}.json"))
  # Real cards written in the DSL, one file per family (spec/fixtures/cards/real); kept out of `cards`.
  def real(family) = read(File.join(ROOT, "spec/fixtures/cards/real/#{family}.json"))
  def deck_names = Dir[File.join(ROOT, "examples/decks/*.json")].map { File.basename(it, ".json") }.sort
  def deck(name) = read(File.join(ROOT, "examples/decks/#{name}.json"))
  def read(path) = JSON.parse(File.read(path), freeze: true)
end
