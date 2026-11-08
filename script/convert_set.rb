# frozen_string_literal: true

# Converts a card set from a card source into Enjine's set file format.
#
#   ruby -Ilib script/convert_set.rb trk                  # fetch from the Scryfall API
#   ruby -Ilib script/convert_set.rb trk --from DIR       # use cached Scryfall search pages (DIR/*.json)
#
# Writes lib/enjine/sets/<code>.json. A card is converted only when ALL of its rules
# text matches a translation the engine supports; otherwise it is listed under
# "unsupported" with the capabilities it is missing. No oracle text is written: the
# output holds structured card data plus the printing (set code + collector number).
require "json"
require "net/http"
require "date"
require "fileutils"
require "enjine"

module SetConverter
  SUPPORTED_KEYWORDS = Enjine.registry.names(:keyword).to_set.freeze
  SUPERTYPES = %w[Legendary Basic Snow World].freeze
  UNSUPPORTED_SUPERTYPES = %w[Legendary Snow World].freeze
  NUMBER = { "a" => 1, "an" => 1, "one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5 }.freeze

  # Keyword abilities recognised on a keyword-only line (supported or not; unsupported
  # ones are reported as missing).
  KNOWN_KEYWORDS = ["flying", "reach", "vigilance", "trample", "menace", "lifelink", "deathtouch", "first strike",
                    "double strike", "defender", "indestructible", "hexproof", "haste", "flash"].freeze

  module_function

  # ---- source adapter (Scryfall today; swap for MTGJSON or a database) -----------

  def fetch_scryfall(code)
    url = URI("https://api.scryfall.com/cards/search?q=#{URI.encode_www_form_component("e:#{code}")}&unique=cards")
    cards = []
    while url
      response = Net::HTTP.get_response(url, { "User-Agent" => "enjine-set-converter/#{Enjine::VERSION}",
                                               "Accept" => "application/json" })
      raise "card source returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      page = JSON.parse(response.body)
      cards.concat(page["data"])
      url = page["has_more"] ? URI(page["next_page"]) : nil
      sleep 0.1 # be polite to the API
    end
    cards
  end

  def load_cached(dir, code)
    Dir[File.join(dir, "*.json")].flat_map { Array(JSON.parse(File.read(it))["data"]) }.select { it["set"] == code }
  end

  # ---- one card ----------------------------------------------------------------------

  # Returns [card_data, nil] or [nil, missing_capabilities].
  def convert(source)
    missing = []
    missing << "layout: #{source["layout"]}" unless source["layout"] == "normal"
    left, right = source["type_line"].to_s.split(" — ", 2)
    words = left.to_s.split
    supertypes = words & SUPERTYPES
    missing.concat((supertypes & UNSUPPORTED_SUPERTYPES).map { "supertype: #{it.downcase}" })
    data = { "name" => source["name"], "types" => (words - SUPERTYPES).map(&:downcase) }
    data["supertypes"] = (supertypes - UNSUPPORTED_SUPERTYPES).map(&:downcase) unless (supertypes - UNSUPPORTED_SUPERTYPES).empty?
    data["subtypes"] = right.split.map { it.downcase.tr("-", "_") } if right
    data["mana_cost"] = source["mana_cost"] unless source["mana_cost"].to_s.empty? || data["types"].include?("land")
    %w[power toughness loyalty].each do |stat|
      next unless source[stat]

      Integer(source[stat], exception: false) ? data[stat] = Integer(source[stat]) : missing << "variable #{stat}"
    end
    translate_text(source, data, missing)
    return [nil, missing.uniq] unless missing.empty?

    [Enjine::CardDefinition.from_h(data).to_h, nil]
  rescue Enjine::InvalidCardDefinition => e
    [nil, e.errors.map { "invalid: #{it}" }]
  end

  def translate_text(source, data, missing)
    text = source["oracle_text"].to_s.gsub(/\s*\([^)]*\)/, "") # reminder text is not rules
    text = text.gsub(source["name"], "CARDNAME")
    text = text.gsub(/\bthis (creature|artifact|enchantment|land|planeswalker|permanent|Vehicle|Spacecraft)\b/, "CARDNAME")
    keywords = []
    abilities = []
    spell_effects = []
    spell_targets = []
    text.split("\n").map(&:strip).reject(&:empty?).each do |line|
      if (kw = keyword_line(line))
        unknown = kw - SUPPORTED_KEYWORDS.to_a
        unknown.empty? ? keywords.concat(kw) : missing.concat(unknown.map { "keyword: #{it}" })
      elsif (triggered = triggered_ability(line))
        abilities << triggered
      elsif (mana = mana_ability(line))
        abilities << mana
      elsif data["types"].intersect?(%w[instant sorcery])
        effects, targets = sentence_effects(line, spell_targets.size)
        effects ? (spell_effects.concat(effects) && spell_targets.concat(targets)) : missing.concat(classify(line))
      elsif (activated = activated_ability(line))
        abilities << activated
      else
        missing.concat(classify(line))
      end
    end
    data["keywords"] = keywords.uniq unless keywords.empty?
    unless spell_effects.empty?
      abilities.unshift({ "spell" => { "targets" => spell_targets, "effects" => spell_effects }.reject do |_, v|
        v.empty?
      end })
    end
    data["abilities"] = abilities unless abilities.empty?
  end

  def keyword_line(line)
    parts = line.split(/,\s*/).map(&:downcase)
    if parts.all? do
      SUPPORTED_KEYWORDS.include?(it) || KNOWN_KEYWORDS.include?(it)
    end
      parts
    end
  end

  TRIGGERS = [
    [/\AWhen CARDNAME enters, (.+)\z/, { "enters" => {} }],
    [/\AWhen CARDNAME dies, (.+)\z/, { "dies" => {} }],
    [/\AWhenever CARDNAME attacks, (.+)\z/, { "attacks" => {} }],
    [/\AAt the beginning of your upkeep, (.+)\z/, { "step_begins" => { "step" => "upkeep" } }],
    [/\AAt the beginning of your end step, (.+)\z/, { "step_begins" => { "step" => "end" } }],
    [/\AAt the beginning of each upkeep, (.+)\z/, { "step_begins" => { "step" => "upkeep", "whose" => "each" } }],
    [/\AWhenever another creature you control enters, (.+)\z/,
     { "enters" => { "subject" => { "each" => "creature", "controller" => "you", "other" => true } } }],
    [/\A(?:Landfall — )?Whenever a land you control enters, (.+)\z/,
     { "enters" => { "subject" => { "each" => "land", "controller" => "you" } } }],
    [/\AWhenever you cast a noncreature spell, (.+)\z/, { "cast" => { "spell" => "noncreature" } }]
  ].freeze

  def triggered_ability(line)
    TRIGGERS.each do |pattern, trigger|
      m = pattern.match(line) or next
      body = m[1].sub(/\A./, &:upcase)
      effects, targets = sentence_effects(body, 0)
      return effects && { "triggered" => { "when" => trigger, "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? } }
    end
    nil
  end

  def mana_ability(line)
    m = /\A\{T\}: Add ((?:\{[WUBRGC]\})+)\.\z/.match(line) or return nil
    { "mana" => { "cost" => ["tap"], "produce" => m[1] } }
  end

  # "{2}, {T}: CARDNAME deals 1 damage to any target." and similar.
  def activated_ability(line)
    m = /\A((?:\{[^}]+\}(?:, )?)+): (.+)\z/.match(line) or return nil
    costs = m[1].split(", ").map do |cost|
      case cost
      when "{T}" then "tap"
      when /\A(\{[0-9WUBRGC]\})+\z/ then { "mana" => cost }
      else return nil
      end
    end
    effects, targets = sentence_effects(m[2], 0)
    effects && { "activated" => { "cost" => costs, "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? } }
  end

  TARGETS = { "any target" => "any_target", "target creature" => "creature", "target player" => "player",
              "target opponent" => "opponent", "target spell" => "spell", "target planeswalker" => "planeswalker",
              "target permanent" => "permanent", "target creature or planeswalker" => "creature_or_planeswalker" }.freeze

  # Translates a line of plain sentences; nil when any sentence isn't understood.
  def sentence_effects(line, target_offset)
    effects = []
    targets = []
    line.split(/(?<=\.)\s+/).each do |sentence|
      effect = sentence_effect(sentence.delete_suffix("."), targets, target_offset) or return nil
      effects << effect
    end
    [effects, targets]
  end

  def target_ref(phrase, targets, offset)
    filter = TARGETS[phrase] or return nil
    targets << filter
    { "target" => offset + targets.size - 1 }
  end

  def number(word) = NUMBER[word] || Integer(word, exception: false)

  def sentence_effect(sentence, targets, offset)
    case sentence
    when /\A(?:CARDNAME|This spell) deals (\d+) damage to (.+)\z/
      to = target_ref(::Regexp.last_match(2), targets, offset) || (::Regexp.last_match(2) == "each opponent" && "each_opponent")
      to && { "deal_damage" => { "amount" => Integer(::Regexp.last_match(1)), "to" => to } }
    when /\ADraw (a|two|three|\d+) cards?\z/ then { "draw" => { "amount" => number(::Regexp.last_match(1)) } }
    when /\AYou gain (\d+) life\z/ then { "gain_life" => { "amount" => Integer(::Regexp.last_match(1)) } }
    when /\AEach opponent loses (\d+) life\z/ then { "lose_life" => { "amount" => Integer(::Regexp.last_match(1)),
                                                                      "to" => "each_opponent" } }
    when %r{\A(target creature) gets \+(\d+)/\+(\d+) until end of turn\z}i
      to = target_ref(::Regexp.last_match(1).downcase, targets, offset)
      { "pump" => { "power" => Integer(::Regexp.last_match(2)), "toughness" => Integer(::Regexp.last_match(3)), "to" => to } }
    when %r{\ACreatures you control get \+(\d+)/\+(\d+) until end of turn\z}
      { "pump" => { "power" => Integer(::Regexp.last_match(1)), "toughness" => Integer(::Regexp.last_match(2)),
                    "to" => { "each" => "creature", "controller" => "you" } } }
    when /\ADestroy (target creature|target permanent|target planeswalker)\z/
      { "destroy" => { "to" => target_ref(::Regexp.last_match(1), targets, offset) } }
    when /\ACounter (target spell)\z/ then { "counter" => { "to" => target_ref(::Regexp.last_match(1), targets, offset) } }
    when %r{\APut (a|one|two|three|\d+) \+1/\+1 counters? on CARDNAME\z}
      { "add_counters" => { "counter" => "+1/+1", "amount" => number(::Regexp.last_match(1)), "to" => "self" } }
    when /\ACARDNAME deals (\d+) damage to each opponent\z/
      { "deal_damage" => { "amount" => Integer(::Regexp.last_match(1)), "to" => "each_opponent" } }
    when /\AYou draw (a|two|three|\d+) cards?\z/ then { "draw" => { "amount" => number(::Regexp.last_match(1)) } }
    when /\AYou lose (\d+) life\z/ then { "lose_life" => { "amount" => Integer(::Regexp.last_match(1)), "to" => "you" } }
    when %r{\APut (a|one|two|three|\d+) \+1/\+1 counters? on (target creature)\z}
      { "add_counters" => { "counter" => "+1/+1", "amount" => number(::Regexp.last_match(1)),
                            "to" => target_ref(::Regexp.last_match(2), targets, offset) } }
    end
  end

  # Capability labels for text the converter can't translate (never the text itself).
  CLASSES = {
    "triggered ability" => /\b(when|whenever|at the beginning of)\b/i,
    "condition (if/unless/as long as)" => /\b(if|unless|as long as)\b/i,
    "tokens" => /\bcreate\b/i, "variable amount" => /\{X\}|\bequal to\b|\bfor each\b|\bnumber of\b/i,
    "modal choice" => /choose (one|two|one or more)/i, "exile" => /\bexile/i, "sacrifice" => /\bsacrifice/i,
    "library manipulation" => /\b(scry|surveil|look at the top|search your library|mill)\b/i,
    "static ability" => /\b(you control (get|have)|can't|costs? .* (less|more))\b/i, "discard" => /\bdiscard/i,
    "return to hand" => /return [^.]* to (its|their) owner/i, "tap/untap effect" => /\b(tap|untap) (target|up to|another)/i,
    "counters" => /counters? on/i, "equipment/aura" => /\b(equip|enchant)\b/i, "copy" => /\bcopy\b/i,
    "station" => /\bstation\b/i, "graveyard casting" => /from your graveyard/i
  }.freeze

  def classify(line)
    found = CLASSES.select { |_, re| line.match?(re) }.keys
    found.empty? ? ["other rules text"] : found
  end

  # ---- the set file --------------------------------------------------------------

  # Estimate: a set stays in Standard until the rotation in the January about three
  # years after its release (marked as an estimate in the file).
  def estimated_legal_until(released_at)
    Date.new(Date.parse(released_at).year + 3, 1, 1).iso8601
  end

  def build(code, sources)
    first = sources.first or raise "no cards for set #{code}"
    entries = []
    unsupported = []
    sources.sort_by { [it["collector_number"].to_i, it["collector_number"]] }.each do |source|
      data, missing = convert(source)
      printing = { "set" => source["set"], "number" => source["collector_number"] }
      if data
        entries << { "card" => data, "rarity" => source["rarity"], "printing" => printing }
      else
        unsupported << { "name" => source["name"], "rarity" => source["rarity"], "printing" => printing, "missing" => missing }
      end
    end
    { "format" => 1, "code" => code, "name" => first["set_name"], "released_at" => first["released_at"],
      "standard_legal_until" => estimated_legal_until(first["released_at"]), "standard_legal_until_estimated" => true,
      "converted_with" => { "engine_version" => Enjine::VERSION, "rules_version" => Enjine::RULES_VERSION },
      "cards" => entries, "unsupported" => unsupported }
  end
end

if $PROGRAM_NAME == __FILE__
  code = ARGV.fetch(0) { abort "usage: convert_set.rb CODE [--from DIR]" }
  from = ARGV.index("--from") && ARGV[ARGV.index("--from") + 1]
  sources = from ? SetConverter.load_cached(from, code) : SetConverter.fetch_scryfall(code)
  set = SetConverter.build(code, sources)
  out = File.expand_path("../lib/enjine/sets/#{code}.json", __dir__)
  FileUtils.mkdir_p(File.dirname(out))
  File.write(out, "#{JSON.pretty_generate(set)}\n")
  blockers = set["unsupported"].flat_map { it["missing"] }.tally.sort_by { -it[1] }
  puts "#{set["name"]} (#{code}): #{set["cards"].size} converted, #{set["unsupported"].size} unsupported -> #{out}"
  puts "top missing capabilities:"
  blockers.first(15).each { |label, n| puts format("  %4d  %s", n, label) }
end
