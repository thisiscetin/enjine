# frozen_string_literal: true

# Checks that every Comprehensive Rules number cited in the code and docs exists in a CR document.
#
#   ruby script/check_cr_citations.rb [CR text or rule-number list]
#   ruby script/check_cr_citations.rb --extract MagicCompRules.txt > spec/fixtures/cr/rule_numbers.txt
#
# The default source is spec/fixtures/cr/rule_numbers.txt: the rule numbers of the pinned CR
# (Enjine::RULES_VERSION), one per line, without any rule text. `--extract` regenerates that list
# from the plain-text CR published by Wizards of the Coast.
require "date"

module CrCitations
  ROOT = File.expand_path("..", __dir__)
  NUMBERS = File.join(ROOT, "spec/fixtures/cr/rule_numbers.txt")
  # Where citations live. docs/reviews are dated reports and keep the numbers they were written with.
  GLOBS = %w[lib/**/*.rb lib/**/*.json spec/**/*.rb script/**/*.rb exe/* Rakefile *.md docs/**/*.md].freeze
  EXCLUDE = %r{\Adocs/reviews/}
  # "702.33a", "722.2a-c", "616.1a–f", "702.33a/d/g", "601.2f-h", "701.51–52".
  DOTTED = %r{(?<![\w.])([1-9]\d{2})\.(\d+)([a-z]?)((?:[-–/](?:\d+|[a-z])\b)*)(?![\d.]*\d)}
  # Bare section numbers count only in a list that starts with "CR"/"rule(s)", e.g. "CR 702.184 and 722".
  CR_LIST = %r{\b(?:CR|[Rr]ules?)\s+((?:\d{3}(?:\.\d+[a-z]?)?(?:[-–]\w+)?(?:\s*(?:,|/|and|or)\s*|\s+)?)+)}
  BARE = /(?<![\w.])(\d{3})(?![\w.])/
  # Primitive metadata: `rules: %w[715.3a 715]`.
  RULES_ARRAY = /rules:\s*%w\[([^\]]*)\]/
  # First column of a markdown rules table: "| 713 |" or "| *(701.72)* |".
  TABLE_ROW = /\A\|\s*\*?\(?(\d{3})\)?\*?\s*\|/
  # A line that deliberately cites another CR version, e.g. a renumbering table.
  IGNORE = "<!-- cr-citations: ignore -->"

  module_function

  # Rule numbers in a CR text or in a list of numbers (one per line). The CR's table of contents
  # repeats the section headings and the glossary has no numbered rules, so only lines from the
  # second "100. General" up to the second "Glossary" heading count. A plain list has neither.
  def rule_numbers(text)
    lines = text.lines(chomp: true)
    starts = lines.each_index.select { lines[it].start_with?("100. General") }
    lines = lines[starts[1]..].take_while { !it.start_with?("Glossary") } if starts.size > 1
    lines.filter_map { it[/\A(\d{3}(?:\.\d+[a-z]?)?)(?:\.|\s|\z)/, 1] }.uniq
  end

  # The date a CR text says it is effective from ("These rules are effective as of November 6, 2026."),
  # or the "# effective 2026-11-06" header of a rule-number list, as YYYY-MM-DD.
  def effective_date(text)
    return Regexp.last_match(1) if text =~ /^# effective (\d{4}-\d{2}-\d{2})$/

    date = text[/effective as of (\w+ \d{1,2}, \d{4})/, 1]
    date && Date.strptime(date, "%B %d, %Y").iso8601
  end

  # Every rule number cited in `text`, as [number, line number] pairs.
  def citations(text)
    text.each_line.with_index(1).flat_map do |line, lineno|
      line_citations(line).map { [it, lineno] }
    end
  end

  def line_citations(line)
    return [] if line.include?(IGNORE)

    found = line.scan(DOTTED).flat_map { |sec, rule, letter, tail| expand(sec, rule, letter, tail) }
    found.concat(line.scan(CR_LIST).flat_map { |(list)| list.scan(BARE).flatten })
    found.concat(line.scan(RULES_ARRAY).flat_map { |(list)| list.split.grep(/\A\d{3}\z/) })
    found << Regexp.last_match(1) if line =~ TABLE_ROW
    found.uniq
  end

  # "722.2a" + "-c" -> 722.2a, 722.2c; "701.51" + "–52" -> 701.51, 701.52; "702.33a" + "/d/g" -> a, d, g.
  def expand(sec, rule, letter, tail)
    base = "#{sec}.#{rule}"
    tail.scan(%r{[-–/](\d+|[a-z])}).flatten.map { it.match?(/\d/) ? "#{sec}.#{it}" : "#{base}#{it}" }
        .unshift("#{base}#{letter}")
  end

  def files(root = ROOT)
    GLOBS.flat_map { Dir.glob(it, base: root) }.uniq.reject { it.match?(EXCLUDE) || File.directory?(File.join(root, it)) }.sort
  end

  # {rule number => ["path:line", ...]} for every citation under `root`.
  def cited(root = ROOT)
    files(root).each_with_object(Hash.new { |h, k| h[k] = [] }) do |path, acc|
      citations(File.read(File.join(root, path))).each { |num, lineno| acc[num] << "#{path}:#{lineno}" }
    end
  end

  # Citations that name no rule in `numbers`.
  def missing(cited, numbers)
    cited.except(*numbers)
  end

  def main(argv, out: $stdout)
    if argv.first == "--extract"
      text = File.read(argv.fetch(1))
      out.puts "# Comprehensive Rules rule numbers only (no rule text): script/check_cr_citations.rb --extract"
      out.puts "# effective #{effective_date(text)}"
      out.puts rule_numbers(text)
      return 0
    end
    text = File.read(argv.first || NUMBERS)
    numbers = rule_numbers(text)
    all = cited
    bad = missing(all, numbers)
    bad.sort.each { |num, where| out.puts "#{num} not in the CR: #{where.join(", ")}" }
    out.puts "#{all.size} distinct rule numbers cited, #{bad.size} missing from the CR " \
             "effective #{effective_date(text)} (#{numbers.size} rules)"
    bad.empty? ? 0 : 1
  end
end

exit CrCitations.main(ARGV) if $PROGRAM_NAME == __FILE__
