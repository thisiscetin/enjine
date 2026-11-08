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
  UNSUPPORTED_SUPERTYPES = %w[Snow World].freeze
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

  # Hand-written translations, keyed by card name: {"abilities": [...], "keywords": [...]} replacing what
  # the text parser would produce. Structured data only; never the card's text.
  def translations(code)
    path = File.expand_path("../data/translations/#{code}.json", __dir__)
    File.exist?(path) ? JSON.parse(File.read(path)) : {}
  end

  # Returns [card_data, nil] or [nil, missing_capabilities].
  def convert(source, translation = nil)
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
    if translation
      data.merge!(translation.except("note"))
    else
      translate_text(source, data, missing)
    end
    return [nil, missing.uniq] unless missing.empty?

    [Enjine::CardDefinition.from_h(data).to_h, nil]
  rescue Enjine::InvalidCardDefinition => e
    [nil, e.errors.map { "invalid: #{it}" }]
  end

  def translate_text(source, data, missing)
    text = source["oracle_text"].to_s.gsub(/\s*\([^)]*\)/, "") # reminder text is not rules
    text = text.gsub(source["name"], "CARDNAME")
    text = text.gsub(/\b[Tt]his (creature|artifact|enchantment|land|planeswalker|permanent|Vehicle|Spacecraft)\b/, "CARDNAME")
    keywords = []
    abilities = []
    spell_effects = []
    spell_targets = []
    spell_modes = []
    text = fold_modes(text)
    text.split("\n").map(&:strip).reject(&:empty?).each do |line|
      if (kw = keyword_line(line))
        unknown = kw - SUPPORTED_KEYWORDS.to_a
        unknown.empty? ? keywords.concat(kw) : missing.concat(unknown.map { "keyword: #{it}" })
      elsif (modal = modal_line(line, data))
        modal[:spell] ? spell_modes.replace(modal[:spell]) : abilities << modal[:ability]
      elsif line.start_with?("CHOOSE")
        missing << "modal choice"
      elsif (triggered = triggered_ability(line))
        abilities << triggered
      elsif (m = /\AAs CARDNAME enters, you may pay (\d+) life\. If you don't, it enters tapped\.\z/.match(line))
        abilities << { "enters_tapped_unless_pay_life" => { "life" => Integer(m[1]) } }
      elsif line.match?(/\ACARDNAME enters tapped\.\z/)
        abilities << "enters_tapped"
      elsif (static = static_line(line))
        abilities << static
      elsif line == "Activate only as a sorcery." && abilities.last.is_a?(Hash) && abilities.last["activated"]
        abilities.last["activated"]["timing"] = "sorcery"
      elsif (mana = mana_ability(line))
        abilities.concat(mana)
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
    abilities.unshift({ "spell" => { "choose" => spell_modes.first, "modes" => spell_modes.drop(1) } }) unless spell_modes.empty?
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

  # "{T}: Add {G}." / "{T}: Add {W} or {U}." / "{T}: Add one mana of any color." Choices between
  # kinds of mana become one mana ability per kind: the same decisions, no new rules.
  # "Choose one —" followed by "• mode" lines becomes one line: "CHOOSE n|prefix|mode|mode".
  CHOOSE_WORDS = { "one" => 1, "two" => 2 }.freeze

  def fold_modes(text)
    text.gsub(/^(.*?)[Cc]hoose (one|two) —((?:\n• .+)+)/) do
      prefix = ::Regexp.last_match(1).strip
      modes = ::Regexp.last_match(3).split("\n• ").map(&:strip).reject(&:empty?)
      "CHOOSE #{CHOOSE_WORDS.fetch(::Regexp.last_match(2))}|#{prefix}|#{modes.join("|")}"
    end
  end

  # A folded modal line: a spell's modes, or a triggered ability with modes ("When ~ enters, choose one —").
  def modal_line(line, data)
    return nil unless line.start_with?("CHOOSE ")

    choose, prefix, *texts = line.delete_prefix("CHOOSE ").split("|")
    modes = texts.map do |text|
      effects, targets = sentence_effects(text.sub(/\A./, &:upcase), 0)
      return nil unless effects

      { "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? }
    end
    if prefix.empty? && data["types"].intersect?(%w[instant sorcery])
      { spell: [Integer(choose)] + modes }
    elsif (trigger = TRIGGERS.find { |pattern, _| pattern.match?("#{prefix} X") }&.last)
      { ability: { "triggered" => { "when" => trigger, "choose" => Integer(choose), "modes" => modes } } }
    end
  end

  SUBJECTS = { "creatures" => "creature", "artifact creatures" => "creature", "lands" => "land", "artifacts" => "artifact" }.freeze

  # "Other creatures you control get +1/+1." / "Creatures you control have vigilance."
  def static_line(line)
    m = %r{\A(Other )?(creatures|artifact creatures|artifacts) you control (?:get ([+-]\d+)/([+-]\d+)(?: and have ([a-z, ]+))?|have ([a-z, ]+))\.\z}.match(line)
    return nil unless m

    keywords = (m[5] || m[6]).to_s.split(/, (?:and )?| and /).map(&:strip).reject(&:empty?)
    return nil unless (keywords - SUPPORTED_KEYWORDS.to_a).empty?

    affects = { "each" => SUBJECTS.fetch(m[2]), "controller" => "you" }
    affects["other"] = true if m[1]
    static = { "affects" => affects }
    static["pump"] = { "power" => Integer(m[3]), "toughness" => Integer(m[4]) } if m[3]
    static["keywords"] = keywords unless keywords.empty?
    { "static" => static }
  end

  def mana_ability(line)
    m = /\A\{T\}: Add (.+)\.\z/.match(line) or return nil
    produced = case m[1]
               when /\A(?:\{[WUBRGC]\})+\z/ then [m[1]]
               when /\A(\{[WUBRGC]\})(?:, (\{[WUBRGC]\}))*,? or (\{[WUBRGC]\})\z/ then m[1].scan(/\{[WUBRGC]\}/)
               when "one mana of any color" then %w[{W} {U} {B} {R} {G}]
               else return nil
               end
    produced.map { { "mana" => { "cost" => ["tap"], "produce" => it } } }
  end

  # "{2}, {T}: CARDNAME deals 1 damage to any target." and similar.
  def activated_ability(line)
    m = /\A((?:(?:\{[^}]+\}|Sacrifice CARDNAME)(?:, )?)+): (.+)\z/.match(line) or return nil
    costs = m[1].split(", ").map do |cost|
      case cost
      when "{T}" then "tap"
      when "Sacrifice CARDNAME" then "sacrifice"
      when /\A(\{[0-9WUBRGC]\})+\z/ then { "mana" => cost }
      else return nil
      end
    end
    effects, targets = sentence_effects(m[2], 0)
    effects && { "activated" => { "cost" => costs, "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? } }
  end

  TARGETS = { "any target" => "any_target", "target creature" => "creature", "target player" => "player",
              "target opponent" => "opponent", "target spell" => "spell", "target planeswalker" => "planeswalker",
              "target permanent" => "permanent", "target creature or planeswalker" => "creature_or_planeswalker",
              "target creature you control" => { "creature" => { "controller" => "you" } },
              "another target creature you control" => { "creature" => { "controller" => "you", "other" => true } },
              "another target creature" => { "creature" => { "other" => true } },
              "target creature an opponent controls" => { "creature" => { "controller" => "opponent" } },
              "target creature you don't control" => { "creature" => { "controller" => "opponent" } },
              "target nonland permanent" => { "permanent" => { "not" => ["land"] } },
              "target nonland permanent an opponent controls" => { "permanent" => { "not" => ["land"], "controller" => "opponent" } },
              "target artifact or creature" => { "permanent" => { "any_of" => %w[artifact creature] } },
              "target artifact" => "artifact", "target attacking creature" => { "creature" => { "attacking" => true } },
              "target attacking or blocking creature" => "creature",
              "target tapped creature" => { "creature" => { "tapped" => true } } }.freeze

  # Longest phrases first so "target creature you control" wins over "target creature".
  TARGET_PHRASES = TARGETS.keys.sort_by { -it.size }.map { Regexp.escape(it) }.join("|")

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

  CREATURE_TOKEN = %r{
    \ACreate\ (a|an|one|two|three|\d+)\ (tapped\ )?(\d+)/(\d+)\
    (?:(?:white|blue|black|red|green|colorless)(?:\ and\ \w+)?\ )?
    ([A-Z][\w\ ]*?)\ (artifact\ )?creature\ tokens?(?:\ with\ ([a-z,\ ]+))?\z
  }x

  def creature_token(match)
    amount, tapped, power, toughness, subtypes, artifact, keywords = match.captures
    keywords = keywords.to_s.split(/, (?:and )?| and /).map(&:strip).reject(&:empty?)
    return nil unless (keywords - SUPPORTED_KEYWORDS.to_a).empty?

    token = { "name" => subtypes, "types" => [artifact ? "artifact" : nil, "creature"].compact,
              "subtypes" => subtypes.split.map(&:downcase), "power" => Integer(power), "toughness" => Integer(toughness) }
    token["keywords"] = keywords unless keywords.empty?
    effect = { "token" => token, "amount" => number(amount) }
    effect["tapped"] = true if tapped
    { "create_token" => effect }
  end

  def sentence_effect(sentence, targets, offset)
    case sentence
    when /\A(?:CARDNAME|This spell) deals (\d+) damage to (.+)\z/
      to = target_ref(::Regexp.last_match(2), targets, offset) || (::Regexp.last_match(2) == "each opponent" && "each_opponent")
      to && { "deal_damage" => { "amount" => Integer(::Regexp.last_match(1)), "to" => to } }
    when /\A(?:You draw|Draw) (a|two|three|\d+) cards?\z/ then { "draw" => { "amount" => number(::Regexp.last_match(1)) } }
    when /\AYou gain (\d+) life\z/ then { "gain_life" => { "amount" => Integer(::Regexp.last_match(1)) } }
    when /\AEach opponent loses (\d+) life\z/ then { "lose_life" => { "amount" => Integer(::Regexp.last_match(1)),
                                                                      "to" => "each_opponent" } }
    when %r{\A(#{TARGET_PHRASES}) gets \+(\d+)/\+(\d+) until end of turn\z}io
      to = target_ref(::Regexp.last_match(1).downcase, targets, offset)
      { "pump" => { "power" => Integer(::Regexp.last_match(2)), "toughness" => Integer(::Regexp.last_match(3)), "to" => to } }
    when %r{\ACreatures you control get \+(\d+)/\+(\d+) until end of turn\z}
      { "pump" => { "power" => Integer(::Regexp.last_match(1)), "toughness" => Integer(::Regexp.last_match(2)),
                    "to" => { "each" => "creature", "controller" => "you" } } }
    when /\ADestroy (#{TARGET_PHRASES})\z/o
      { "destroy" => { "to" => target_ref(::Regexp.last_match(1), targets, offset) } }
    when /\ACounter (target spell)\z/ then { "counter" => { "to" => target_ref(::Regexp.last_match(1), targets, offset) } }
    when /\AExile (#{TARGET_PHRASES})\z/o
      { "exile" => { "to" => target_ref(::Regexp.last_match(1), targets, offset) } }
    when /\AReturn (#{TARGET_PHRASES}) to its owner's hand\z/o
      { "return_to_hand" => { "to" => target_ref(::Regexp.last_match(1), targets, offset) } }
    when /\ATap (#{TARGET_PHRASES})\z/o then { "tap" => { "to" => target_ref(::Regexp.last_match(1), targets, offset) } }
    when /\AUntap CARDNAME\z/ then { "untap" => { "to" => "self" } }
    when /\A(Scry|Surveil) (\d+)\z/ then { ::Regexp.last_match(1).downcase => { "amount" => Integer(::Regexp.last_match(2)) } }
    when /\AMill (a|one|two|three|\d+) cards?\z/ then { "mill" => { "amount" => number(::Regexp.last_match(1)) } }
    when /\AEach opponent mills (a|one|two|three|\d+) cards?\z/
      { "mill" => { "amount" => number(::Regexp.last_match(1)), "to" => "each_opponent" } }
    when /\A(Target player|Target opponent) mills (a|one|two|three|\d+) cards?\z/
      { "mill" => { "amount" => number(::Regexp.last_match(2)), "to" => target_ref(::Regexp.last_match(1).downcase, targets, offset) } }
    when /\AEach opponent discards (a|one|two|\d+) cards?\z/
      { "discard" => { "amount" => number(::Regexp.last_match(1)), "to" => "each_opponent" } }
    when /\A(Target player|Target opponent) discards (a|one|two|\d+) cards?\z/
      { "discard" => { "amount" => number(::Regexp.last_match(2)), "to" => target_ref(::Regexp.last_match(1).downcase, targets, offset) } }
    when /\ADiscard (a|one|two|\d+) cards?\z/ then { "discard" => { "amount" => number(::Regexp.last_match(1)) } }
    when /\A(#{TARGET_PHRASES}|CARDNAME) gains ([a-z ,]+) until end of turn\z/o
      keywords = ::Regexp.last_match(2).split(/, (?:and )?| and /).map(&:strip)
      return nil unless (keywords - SUPPORTED_KEYWORDS.to_a).empty?

      to = ::Regexp.last_match(1) == "CARDNAME" ? "self" : target_ref(::Regexp.last_match(1), targets, offset)
      { "grant" => { "keywords" => keywords, "to" => to } }
    when /\ADraw a card for each (creature|artifact|land) you control\z/
      { "draw" => { "amount" => { "count" => { "each" => ::Regexp.last_match(1), "controller" => "you" } } } }
    when /\ACreate (a|an|one|two|three|\d+) (tapped )?(Treasure|Clue|Food) tokens?\z/
      { "create_token" => { "token" => ::Regexp.last_match(3), "amount" => number(::Regexp.last_match(1)),
                            "tapped" => !::Regexp.last_match(2).nil? }.reject { |k, v| k == "tapped" && !v } }
    when CREATURE_TOKEN
      creature_token(::Regexp.last_match)
    when %r{\APut (a|one|two|three|\d+) \+1/\+1 counters? on CARDNAME\z}
      { "add_counters" => { "counter" => "+1/+1", "amount" => number(::Regexp.last_match(1)), "to" => "self" } }
    when /\ACARDNAME deals (\d+) damage to each opponent\z/
      { "deal_damage" => { "amount" => Integer(::Regexp.last_match(1)), "to" => "each_opponent" } }
    when /\AYou lose (\d+) life\z/ then { "lose_life" => { "amount" => Integer(::Regexp.last_match(1)), "to" => "you" } }
    when %r{\APut (a|one|two|three|\d+) \+1/\+1 counters? on (#{TARGET_PHRASES})\z}o
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
    manual = translations(code)
    entries = []
    unsupported = []
    sources.sort_by { [it["collector_number"].to_i, it["collector_number"]] }.each do |source|
      data, missing = convert(source, manual[source["name"]])
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
