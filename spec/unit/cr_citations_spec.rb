# frozen_string_literal: true

require "stringio"
require "tmpdir"
require_relative "../../script/check_cr_citations"

# Every rule number the code and docs cite must exist in the pinned Comprehensive Rules. The rule
# numbers (no rule text) are vendored in spec/fixtures/cr/rule_numbers.txt; regenerate them from a
# new CR with `ruby script/check_cr_citations.rb --extract MagicCompRules.txt`.
RSpec.describe CrCitations do
  let(:numbers) { described_class.rule_numbers(File.read(described_class::NUMBERS)) }

  it "vendors the rule numbers of the pinned CR (Enjine::RULES_VERSION)" do
    expect(described_class.effective_date(File.read(described_class::NUMBERS))).to eq(Enjine::RULES_VERSION)
    expect(numbers).to include("100", "702.184a", "734.1")
  end

  it "finds every cited rule number in the pinned CR" do
    cited = described_class.cited
    expect(cited.size).to be > 500
    expect(described_class.missing(cited, numbers)).to eq({})
  end

  it "finds every primitive's rules metadata in the pinned CR" do
    rules = Enjine::Primitive::CATEGORIES.flat_map { |c| Enjine.registry.each(c).flat_map(&:rules) }
    expect(rules).not_to be_empty
    expect(rules.uniq - numbers).to eq([])
  end

  it "matches the full CR text when ENJINE_CR_TEXT points at it" do
    path = ENV.fetch("ENJINE_CR_TEXT", nil)
    skip "set ENJINE_CR_TEXT to the plain-text CR to compare it with the vendored list" unless path && File.exist?(path)
    text = File.read(path)
    expect([described_class.effective_date(text), described_class.rule_numbers(text)])
      .to eq([Enjine::RULES_VERSION, numbers])
  end

  describe ".line_citations" do
    it "expands letter, slash and numeric ranges" do
      expect(described_class.line_citations("CR 722.2a-c and 616.1a–b, 702.33a/d; 701.51–52"))
        .to eq(%w[722.2a 722.2c 616.1a 616.1b 702.33a 702.33d 701.51 701.52])
    end

    it "counts bare sections only after CR or rule, in rules arrays and in table rows" do
      expect(described_class.line_citations("CR 702.184 and 722 cover 123 cards")).to eq(%w[702.184 722])
      expect(described_class.line_citations("rules: %w[715.3a 715]")).to eq(%w[715.3a 715])
      expect(described_class.line_citations("| *(701.72)* | Assimilate |")).to eq(%w[701.72])
      expect(described_class.line_citations("| 713 | Meld |")).to eq(%w[713])
      expect(described_class.line_citations("took 100 games at 1.5x, version 0.1.0")).to eq([])
    end

    it "skips lines marked as citing another CR version" do
      expect(described_class.line_citations("| 614.13c | <!-- cr-citations: ignore --> |")).to eq([])
    end
  end

  describe ".rule_numbers" do
    let(:cr) do
      <<~TXT
        Magic: The Gathering Comprehensive Rules
        These rules are effective as of November 6, 2026.
        Contents
        100. General
        999. Not A Rule
        Glossary
        100. General
        100.1. These rules apply.
        100.1a A subrule.
        Glossary
        123. Not a rule either
      TXT
    end

    it "reads rules between the contents and the glossary" do
      expect(described_class.rule_numbers(cr)).to eq(%w[100 100.1 100.1a])
      expect(described_class.effective_date(cr)).to eq("2026-11-06")
      expect(described_class.effective_date("no date")).to be_nil
    end

    it "extracts a rule-number list and checks citations against one" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "cr.txt"), cr)
        out = StringIO.new
        expect(described_class.main(["--extract", File.join(dir, "cr.txt")], out: out)).to eq(0)
        expect(out.string.lines(chomp: true).drop(1)).to eq(["# effective 2026-11-06", "100", "100.1", "100.1a"])

        File.write(File.join(dir, "list.txt"), out.string)
        report = StringIO.new
        expect(described_class.main([File.join(dir, "list.txt")], out: report)).to eq(1)
        expect(report.string).to include("702.184a not in the CR:", "missing from the CR effective 2026-11-06 (3 rules)")
        expect(described_class.main([], out: StringIO.new)).to eq(0)
      end
    end
  end
end
