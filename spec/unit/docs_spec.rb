# frozen_string_literal: true

require "tmpdir"
RSpec.describe Enjine::Docs do
  it "matches the committed reference docs (run `rake docs` after changing a primitive)" do
    described_class.generate.each do |path, content|
      file = File.join(Enjine::Docs::ROOT, path)
      expect(File.exist?(file) && File.read(file)).to eq(content), "#{path} is out of date; run `rake docs`"
    end
  end

  it "documents every primitive, decision and priority action" do
    files = described_class.generate
    Enjine::Primitive::CATEGORIES.each do |category|
      Enjine.registry.each(category) { |k| expect(files["SUPPORTED.md"]).to include("`#{k.primitive_name}`") }
    end
    Enjine::Decisions::KINDS.each_key { expect(files["docs/reference/decisions.md"]).to include("## #{it}") }
    Enjine::Actions::BY_TYPE.each_key { expect(files["docs/reference/decisions.md"]).to include("`#{it}`") }
  end

  it "writes files to a directory" do
    Dir.mktmpdir do |dir|
      described_class.write(dir)
      expect(File.read(File.join(dir, "SUPPORTED.md"))).to start_with("# Supported mechanics")
    end
  end
end
