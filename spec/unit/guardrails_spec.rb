# frozen_string_literal: true

# Rules code must ask Engine#chars (current characteristics, CR 613) instead of the
# printed CardDefinition, or layer effects will silently be ignored (review finding F2).
RSpec.describe "Guardrails" do
  let(:allowed) do
    {
      "lib/enjine/engine/characteristics.rb" => "the layer system starts from printed values",
      "lib/enjine/engine/ability_layers.rb" => "granted abilities live in the granting card's data (layer 6)",
      "lib/enjine/engine/defined_power_toughness.rb" => "the printed characteristic-defining amount (layer 7a)",
      "lib/enjine/engine/casting/casting.rb" => "spells in hand/stack (printed) and stack abilities (CR 113.7a)",
      "lib/enjine/engine/resolution.rb" => "spell abilities and permanence of the printed spell",
      "lib/enjine/replacements.rb" => "entering status from printed card types",
      "lib/enjine/view.rb" => "printed name, cost and rules text",
      "lib/enjine/deck_builder.rb" => "deck construction works on printed cards, not game objects",
      "lib/enjine/rules_monitor.rb" => "independent checker recomputes from printed values on purpose"
    }
  end

  it "keeps direct definition() reads out of rules code" do
    offenders = Dir[File.join(Enjine::Docs::ROOT, "lib/**/*.rb")].filter_map do |file|
      rel = file.delete_prefix("#{Enjine::Docs::ROOT}/")
      next if allowed.key?(rel) || rel.start_with?("lib/enjine/cli")

      rel if File.read(file).lines.any? { it.match?(/\bdefinition\(/) && !it.match?(/def definition\(/) }
    end
    expect(offenders).to be_empty, "use engine.chars(obj) instead of definition(obj) in: #{offenders.join(", ")}"
  end
end
