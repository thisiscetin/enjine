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
    missing << "layout: #{source["layout"]}" unless %w[normal saga].include?(source["layout"])
    left, right = source["type_line"].to_s.split(" — ", 2)
    words = left.to_s.split
    supertypes = words & SUPERTYPES
    missing.concat((supertypes & UNSUPPORTED_SUPERTYPES).map { "supertype: #{it.downcase}" })
    data = { "name" => source["name"], "types" => (words - SUPERTYPES).map(&:downcase) }
    data["supertypes"] = (supertypes - UNSUPPORTED_SUPERTYPES).map(&:downcase) unless (supertypes - UNSUPPORTED_SUPERTYPES).empty?
    data["subtypes"] = right.split.map { it.downcase.tr("-", "_").delete("'") } if right # Jem'Hadar -> jemhadar
    data["mana_cost"] = source["mana_cost"] unless source["mana_cost"].to_s.empty? || data["types"].include?("land")
    %w[power toughness loyalty].each do |stat|
      next unless source[stat]
      next if stat != "loyalty" && station_card?(source) # a station card's P/T box belongs to a station symbol (CR 722.2b-c)

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
    short = source["name"].split(", ").first # a legendary card may call itself by its first name
    text = text.gsub(/(?<![\w.])#{Regexp.escape(short)}(?!\w)/, "CARDNAME") if short != source["name"]
    text = text.gsub(/\b[Tt]his (creature|artifact|enchantment|land|planeswalker|permanent|Vehicle|Spacecraft|Saga|Equipment|Aura)\b/,
                     "CARDNAME")
    text, station = translate_station_symbols(source, text, data, missing)
    keywords = []
    abilities = []
    spell_effects = []
    spell_targets = []
    spell_modes = []
    text = fold_modes(text)
    text.split("\n").map(&:strip).reject(&:empty?).each do |line|
      if (cycling = cycling_line(line))
        abilities << cycling
      elsif (kw = keyword_line(line))
        unknown = kw - SUPPORTED_KEYWORDS.to_a
        unknown.empty? ? keywords.concat(kw) : missing.concat(unknown.map { "keyword: #{it}" })
      elsif (modal = modal_line(line, data))
        modal[:spell] ? spell_modes.replace(modal[:spell]) : abilities << modal[:ability]
      elsif line.start_with?("CHOOSE")
        missing << "modal choice"
      elsif (triggered = triggered_ability(line))
        abilities << triggered
      elsif (chapters = chapter_line(line))
        chapters.empty? ? missing.concat(classify(line)) : abilities.concat(chapters)
      elsif (m = /\AAs CARDNAME enters, you may pay (\d+) life\. If you don't, it enters tapped\.\z/.match(line))
        abilities << { "enters_tapped_unless_pay_life" => { "life" => Integer(m[1]) } }
      elsif line.match?(/\ACARDNAME enters tapped\.\z/)
        abilities << "enters_tapped"
      elsif (entering = enters_with_line(line))
        abilities << entering
      elsif (flag = RESTRICTION_LINES[line])
        keywords << flag
      elsif (static = static_line(line) || cost_line(line) || attachment_line(line))
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
    abilities = name_self(abilities, source["name"])
    data["keywords"] = keywords.uniq unless keywords.empty?
    abilities.unshift({ "spell" => { "choose" => spell_modes.first, "modes" => spell_modes.drop(1) } }) unless spell_modes.empty?
    unless spell_effects.empty?
      abilities.unshift({ "spell" => { "targets" => spell_targets, "effects" => spell_effects }.reject do |_, v|
        v.empty?
      end })
    end
    abilities.concat(station)
    data["abilities"] = abilities unless abilities.empty?
    # "X" is only the announced X when a cost has {X} (CR 107.3a); otherwise the text defines it.
    text_x = JSON.generate(abilities).include?('"amount":"x"')
    missing << "variable amount" if text_x && !"#{data["mana_cost"]}#{JSON.generate(abilities)}".include?("{X}")
  end

  # Combat restrictions and requirements printed as their own line (CR 508.1c-d, 509.1b).
  RESTRICTION_LINES = { "CARDNAME can't block." => "cant_block", "CARDNAME can't attack." => "cant_attack",
                        "CARDNAME can't be blocked." => "cant_be_blocked",
                        "CARDNAME attacks each combat if able." => "attacks_each_combat" }.freeze

  def keyword_line(line)
    parts = line.split(/,\s*/).map(&:downcase)
    if parts.all? do
      SUPPORTED_KEYWORDS.include?(it) || KNOWN_KEYWORDS.include?(it)
    end
      parts
    end
  end

  # "Cycling {2}", "Basic landcycling {2}", "Swampcycling {2}", "Landcycling {2}" (CR 702.29a, 702.29e).
  def cycling_line(line)
    m = /\A(?:(Basic land|Land|[A-Z][a-z]+)c|C)ycling ((?:\{[0-9WUBRGC]\})+)\z/.match(line) or return nil
    ability = { "cost" => m[2] }
    ability["for"] = card_spec(m[1].downcase) if m[1]
    { "cycling" => ability }
  end

  CARD_TYPES = Enjine.registry.names(:type).to_set.freeze

  # "basic land" -> {"supertypes": ["basic"], "types": ["land"]}; "Swamp" -> {"subtypes": ["swamp"]};
  # "Type, Type, or Type" / "basic land card or Type" -> {"any_of": [...]}.
  def card_spec(phrase)
    parts = phrase.split(/,? or |, /).map { it.delete_suffix(" card").strip }
    return { "any_of" => parts.map { card_spec(it) } } if parts.size > 1

    spec = Hash.new { |h, k| h[k] = [] }
    phrase.split.each do |word|
      word = word.downcase
      key = if word == "basic" then "supertypes"
            elsif CARD_TYPES.include?(word) then "types"
            else "subtypes"
            end
      spec[key] << word
    end
    spec.to_h
  end

  SEARCH = /
    \A(You\ may\ search|Search)\ your\ library\ for\ (a|an|up\ to\ (?:two|three|\d+)|any\ number\ of)\ (.+?),
    \ (reveal\ (?:it|them|that\ card),\ )?put\ (?:it|them|that\ card)\ (into\ your\ hand|onto\ the\ battlefield(?:\ tapped)?),
    \ then\ shuffle\z
  /x

  # "Search your library for a basic land card, reveal it, put it into your hand, then shuffle" (CR 701.23).
  def search_effect(match)
    optional, count, what, reveal, put = match.captures
    count = case count
            when "a", "an" then 1
            when "any number of" then "any"
            else number(count.delete_prefix("up to "))
            end
    spec = if what.match?(/\Acards?\z/) then "card"
           elsif (name = what[/\Acards? named (.+)\z/, 1]) then { "name" => name }
           elsif what.match?(/ cards?\z/) then card_spec(what.sub(/ cards?\z/, ""))
           else return nil
           end
    return nil if spec == "card" && optional.start_with?("You may") # an optional search for any card: no data form yet

    effect = { "for" => spec }
    effect["count"] = count unless count == 1
    effect["reveal"] = true if reveal
    effect["put"] = "battlefield" if put.start_with?("onto")
    effect["tapped"] = true if put.end_with?("tapped")
    { "search_library" => effect }
  end

  # A search for cards with the card's own name: the text uses CARDNAME for it.
  def name_self(abilities, name)
    JSON.parse(JSON.generate(abilities).gsub('"name":"CARDNAME"', "\"name\":#{JSON.generate(name)}"))
  end

  STATION_LINE = /^(\d+)\+ \| /

  # A station card: its text has station symbols "N+ | ..." (CR 722.1).
  def station_card?(source) = source["oracle_text"].to_s.match?(STATION_LINE)

  # Station symbols (CR 722.2): every line from the first "N+ | " on belongs to a striation. Each
  # becomes a station_symbol ability; the card's power/toughness goes to the symbol that makes it a
  # creature (the "artifact creature at N+" reminder, else the last symbol). Returns the other text.
  def translate_station_symbols(source, text, data, missing)
    start = text.index(STATION_LINE) or return [text, []]
    creature_at = source["oracle_text"][/artifact creature at (\d+)\+/, 1]&.to_i
    sections = text[start..].split(/^(?=\d+\+ \| )/)
    thresholds = sections.map { Integer(it[/\A\d+/]) }
    creature_at ||= thresholds.max if source["power"]
    symbols = sections.each_with_index.map do |section, i|
      inner = { "types" => data["types"] }
      translate_text({ "name" => source["name"], "oracle_text" => section.sub(STATION_LINE, "") }, inner, missing)
      symbol = { "at" => thresholds[i] }.merge(inner.slice("keywords", "abilities"))
      if creature_at == thresholds[i] && source["power"]
        %w[power toughness].each { |k| Integer(source[k], exception: false) ? symbol[k] = Integer(source[k]) : missing << "variable #{k}" }
      end
      { "station_symbol" => symbol }
    end
    [text[0...start], symbols]
  end

  ROMAN = { "I" => 1, "II" => 2, "III" => 3, "IV" => 4, "V" => 5, "VI" => 6 }.freeze
  CHAPTER_LINE = /\A((?:I|II|III|IV|V|VI)(?:, (?:I|II|III|IV|V|VI))*) — (.+)\z/

  # A Saga's chapter line "I, II — effect" (CR 715.2): one chapter ability per number (CR 715.2c).
  # Returns nil for other lines, [] when the effect isn't understood.
  def chapter_line(line)
    m = CHAPTER_LINE.match(line) or return nil
    effects, targets = sentence_effects(m[2], 0)
    return [] unless effects

    body = { "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? }
    m[1].split(", ").map { { "chapter" => { "chapter" => ROMAN.fetch(it) }.merge(body) } }
  end

  # Combat and event triggers (deals combat damage, attacking, blocking, life, draws, dies).
  YOURS = { "each" => "creature", "controller" => "you" }.freeze
  COMBAT_TRIGGERS = [
    [/\AWhenever CARDNAME deals combat damage to a player, (.+)\z/, { "deals_damage" => { "combat" => true, "to" => "player" } }],
    [/\AWhenever CARDNAME deals combat damage, (.+)\z/, { "deals_damage" => { "combat" => true } }],
    [/\AWhenever CARDNAME enters or attacks, (.+)\z/, { "any_of" => [{ "enters" => {} }, { "attacks" => {} }] }],
    [/\AWhenever CARDNAME enters or deals combat damage to a player, (.+)\z/,
     { "any_of" => [{ "enters" => {} }, { "deals_damage" => { "combat" => true, "to" => "player" } }] }],
    [/\AWhenever (?:you attack|one or more creatures you control attack), (.+)\z/, { "player_attacks" => {} }],
    [/\AWhenever CARDNAME becomes blocked, (.+)\z/, { "becomes_blocked" => {} }],
    [/\AWhenever you gain life, (.+)\z/, { "gains_life" => {} }],
    [/\AWhenever an opponent loses life, (.+)\z/, { "loses_life" => { "controller" => "opponent" } }],
    [/\AWhenever you draw a card, (.+)\z/, { "draws" => {} }],
    [/\AWhenever (?:a creature you control|CARDNAME or another creature you control) dies, (.+)\z/, { "dies" => { "subject" => YOURS } }],
    [/\AWhenever another creature you control dies, (.+)\z/, { "dies" => { "subject" => YOURS.merge("other" => true) } }],
    [/\AWhenever a creature dies, (.+)\z/, { "dies" => { "subject" => { "each" => "creature" } } }],
    [/\AWhenever another creature dies, (.+)\z/, { "dies" => { "subject" => { "each" => "creature", "other" => true } } }]
  ].freeze

  TRIGGERS = [
    [/\AWhen CARDNAME enters, (.+)\z/, { "enters" => {} }],
    [/\AWhen CARDNAME dies, (.+)\z/, { "dies" => {} }],
    [/\AWhenever CARDNAME attacks, (.+)\z/, { "attacks" => {} }],
    [/\AAt the beginning of your upkeep, (.+)\z/, { "step_begins" => { "step" => "upkeep" } }],
    [/\AAt the beginning of your end step, (.+)\z/, { "step_begins" => { "step" => "end" } }],
    [/\AAt the beginning of combat on your turn, (.+)\z/, { "step_begins" => { "step" => "beginning_of_combat" } }],
    [/\AAt the beginning of each upkeep, (.+)\z/, { "step_begins" => { "step" => "upkeep", "whose" => "each" } }],
    [/\AWhenever another creature you control enters, (.+)\z/,
     { "enters" => { "subject" => { "each" => "creature", "controller" => "you", "other" => true } } }],
    [/\A(?:Landfall — )?Whenever a land you control enters, (.+)\z/,
     { "enters" => { "subject" => { "each" => "land", "controller" => "you" } } }],
    [/\AWhenever you cast a noncreature spell, (.+)\z/, { "cast" => { "spell" => "noncreature" } }],
    [/\AWhenever equipped creature attacks, (.+)\z/, { "attacks" => { "subject" => "attached" } }],
    [/\AWhenever you face a dilemma, (.+)\z/, { "faces_dilemma" => {} }],
    *COMBAT_TRIGGERS
  ].freeze

  def triggered_ability(line)
    TRIGGERS.each do |pattern, trigger|
      m = pattern.match(line) or next
      cast = m[1].start_with?("if you cast it, ") # intervening "if" (CR 603.4)
      effects, targets = sentence_effects(capitalize(m[1].delete_prefix("if you cast it, ")), 0)
      ability = { "when" => trigger, "if" => cast ? { "was_cast" => true } : nil, "targets" => targets, "effects" => effects }
      return effects && { "triggered" => ability.reject { |_, v| v.nil? || v.empty? } }
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
      effects, targets = sentence_effects(capitalize(text.sub(/\A[A-Z][^—.]* — /, "")), 0) # drop a mode's name
      return nil unless effects

      { "targets" => targets, "effects" => effects }.reject { |_, v| v.empty? }
    end
    if prefix.empty? && data["types"].intersect?(%w[instant sorcery])
      { spell: [Integer(choose)] + modes }
    elsif (trigger = TRIGGERS.find { |pattern, _| pattern.match?("#{prefix} X") }&.last)
      { ability: { "triggered" => { "when" => trigger, "choose" => Integer(choose), "modes" => modes } } }
    end
  end

  SUBJECTS = { "creatures" => "creature", "artifact creatures" => { "creature" => { "types" => ["artifact"] } },
               "lands" => "land", "artifacts" => "artifact" }.freeze

  STATIC_LINE = %r{
    \A(Other\ )?((?i:creatures|artifact\ creatures|artifacts))\ you\ control\ (with\ counters\ on\ them\ )?
    (?:get\ ([+-]\d+)/([+-]\d+)(?:\ and\ have\ ([a-z,\ ]+))?|have\ ([a-z,\ ]+))\.\z
  }x

  # "Other creatures you control get +1/+1." / "Creatures you control have vigilance."
  def static_line(line)
    m = STATIC_LINE.match(line)
    return nil unless m

    keywords = (m[6] || m[7]).to_s.split(/, (?:and )?| and /).map(&:strip).reject(&:empty?)
    return nil unless (keywords - SUPPORTED_KEYWORDS.to_a).empty?

    affects = { "each" => static_subject(m[2].downcase, m[3]), "controller" => "you" }
    affects["other"] = true if m[1]
    static = { "affects" => affects }
    static["pump"] = { "power" => Integer(m[4]), "toughness" => Integer(m[5]) } if m[4]
    static["keywords"] = keywords unless keywords.empty?
    { "static" => static }
  end

  # The static's filter; "with counters on them" restricts it to permanents with a counter (CR 122).
  def static_subject(words, with_counters)
    filter = SUBJECTS.fetch(words)
    return filter unless with_counters

    name, restrictions = filter.is_a?(String) ? [filter, {}] : filter.first
    { name => restrictions.merge("counters" => true) }
  end

  ENCHANT = { "creature" => "creature", "artifact" => "artifact", "land" => "land", "permanent" => "permanent",
              "planeswalker" => "planeswalker", "creature you control" => { "creature" => { "controller" => "you" } },
              "creature an opponent controls" => { "creature" => { "controller" => "opponent" } },
              "artifact or creature" => { "permanent" => { "any_of" => %w[artifact creature] } } }.freeze

  ATTACHED_STATIC = %r{
    \A(?:Equipped|Enchanted)\ creature
    \ (?:gets\ ([+-]\d+)/([+-]\d+)(?:\ and\ has\ ([a-z,\ ]+))?|has\ ([a-z,\ ]+))\.\z
  }x

  # Keyword names as the text writes them ("double strike") are supported registry names ("double_strike").
  def supported_keywords?(keywords) = (keywords.map { it.tr(" ", "_") } - SUPPORTED_KEYWORDS.to_a).empty?

  # Auras and Equipment: "Enchant creature", "Equip {2}", "Equipped creature gets +1/+1 and has vigilance."
  def attachment_line(line)
    if (m = /\AEnchant (.+)\z/.match(line))
      ENCHANT.key?(m[1]) ? { "enchant" => ENCHANT[m[1]] } : nil
    elsif (m = /\AEquip ((?:\{[0-9WUBRGC]\})+)\z/.match(line))
      { "equip" => { "cost" => [{ "mana" => m[1] }] } }
    elsif (m = ATTACHED_STATIC.match(line))
      keywords = (m[3] || m[4]).to_s.split(/, (?:and )?| and /).map(&:strip).reject(&:empty?)
      return nil unless supported_keywords?(keywords)

      static = { "affects" => "attached" }
      static["pump"] = { "power" => Integer(m[1]), "toughness" => Integer(m[2]) } if m[1]
      static["keywords"] = keywords.map { it.tr(" ", "_") } unless keywords.empty?
      { "static" => static }
    end
  end

  def mana_ability(line)
    m = /\A\{T\}: Add (.+)\.\z/.match(line) or return nil
    produced = case m[1]
               when /\A(?:\{[WUBRGC]\})+\z/ then [m[1]]
               when /\A(\{[WUBRGC]\})(?:, (\{[WUBRGC]\}))*,? or (\{[WUBRGC]\})\z/ then m[1].scan(/\{[WUBRGC]\}/)
               when "one mana of any color" then %w[{W} {U} {B} {R} {G}]
               when /\A(two|three) mana of any one color\z/ then %w[{W} {U} {B} {R} {G}].map { it * number(::Regexp.last_match(1)) }
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
      when /\A(\{[0-9WUBRGCX]\})+\z/ then { "mana" => cost }
      else return nil
      end
    end
    effects, targets = sentence_effects(m[2], 0)
    return nil if effects&.any? { it.key?("add_mana") } # CR 605.1a: that's a mana ability

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
              "target tapped creature" => { "creature" => { "tapped" => true } },
              "target noncreature spell" => { "spell" => { "not" => ["creature"] } },
              "target artifact or enchantment" => { "permanent" => { "any_of" => %w[artifact enchantment] } },
              "target noncreature artifact" => { "artifact" => { "not" => ["creature"] } },
              "target nonartifact creature" => { "creature" => { "not" => ["artifact"] } },
              "target nontoken artifact" => { "artifact" => { "token" => false } },
              "target nontoken creature" => { "creature" => { "token" => false } },
              "target legendary creature" => { "creature" => { "supertypes" => ["legendary"] } },
              "target token" => { "permanent" => { "token" => true } },
              "target tapped creature an opponent controls" => { "creature" => { "tapped" => true, "controller" => "opponent" } },
              "target creature card from a graveyard" => { "graveyard_card" => { "any_of" => ["creature"] } } }.freeze

  # "... with power 4 or greater" / "... with mana value 3 or less" after a target phrase.
  TARGET_STAT = /\A(.+) with (power|toughness|mana value) (\d+) or (greater|less)\z/

  # Longest phrases first so "target creature you control" wins over "target creature".
  TARGET_PHRASES = "(?:#{TARGETS.keys.sort_by { -it.size }.map { Regexp.escape(it) }.join("|")})" \
                   "(?: with (?:power|toughness|mana value) \\d+ or (?:greater|less))?".freeze

  # Translates a line of plain sentences; nil when any sentence isn't understood. "X, then Y" is two
  # sentences; "You may X. If you do, Y." is one optional effect; "it" / "that card" in a follow-up
  # sentence is what the previous effect moved or created ({"result": n}).
  def sentence_effects(line, target_offset)
    effects = []
    targets = []
    line = line.gsub(/ and (you gain \d+ life\.)/) { ". #{::Regexp.last_match(1).capitalize}" } # two effects
    sentences = line.split(/(?<=\.)\s+/).flat_map { it.delete_suffix(".").split(", then ").map { capitalize(it) } }
    until sentences.empty?
      sentence = sentences.shift
      effect = optional_effect(sentence, sentences, targets, target_offset) ||
               follow_up_effect(sentence, effects) ||
               sentence_effect(sentence, targets, target_offset) or return nil
      effect.is_a?(Array) ? effects.concat(effect) : effects << effect
    end
    [effects, targets]
  end

  def capitalize(text) = text.sub(/\A./, &:upcase)

  # "You may X." optionally followed by "If you do, Y." (consumed from `rest`).
  def optional_effect(sentence, rest, targets, offset)
    m = /\AYou may (.+)\z/.match(sentence) or return nil
    optional = sentence_effect(capitalize(m[1]), targets, offset) or return nil
    may = { "effects" => [optional] }
    if (follow = /\AIf you do, (.+)\z/.match(rest.first.to_s))
      rest.shift
      then_effect = sentence_effect(capitalize(follow[1]), targets, offset) or return nil
      may["then"] = [then_effect]
    end
    { "may" => may }
  end

  NEXT_END_STEP = { "the next end step" => { "step_begins" => { "step" => "end", "whose" => "each" } },
                    "your next end step" => { "step_begins" => { "step" => "end", "whose" => "your" } } }.freeze
  IT = /(?:it|them|that card|those cards|that token|those tokens|that creature)/
  AT_END = /at the beginning of (the next end step|your next end step)/
  RETURN_IT = /Return #{IT} to the battlefield under (?:its|their) owners?'s? control/o
  FOLLOW_UPS = [
    # [pattern, effect key the previous effect must have, builder(match, result selector)]
    [/\A(Sacrifice|Exile|Destroy) #{IT} #{AT_END}\z/o, %w[create_token return_to_battlefield],
     ->(m, ref) { delayed(m[2], { m[1].downcase => { "to" => ref } }) }],
    [/\A#{RETURN_IT} #{AT_END}\z/o, %w[exile], ->(m, ref) { delayed(m[1], { "return_to_battlefield" => { "to" => ref } }) }],
    [/\A#{RETURN_IT}\z/o, %w[exile], ->(_m, ref) { { "return_to_battlefield" => { "to" => ref } } }],
    [/\A(?:It|They|That token|Those tokens) gains? ([a-z ,]+) until end of turn\z/, %w[create_token],
     lambda do |m, ref|
       keywords = m[1].split(/, (?:and )?| and /).map(&:strip)
       { "grant" => { "keywords" => keywords, "to" => ref } } if (keywords - SUPPORTED_KEYWORDS.to_a).empty?
     end]
  ].freeze

  def delayed(step, effect) = { "delayed_trigger" => { "when" => NEXT_END_STEP.fetch(step), "effects" => [effect] } }

  # A sentence about what the previous effect moved or created (CR 400.7j).
  def follow_up_effect(sentence, effects)
    previous = effects.last or return nil
    FOLLOW_UPS.each do |pattern, after, build|
      m = pattern.match(sentence) or next
      return after.include?(previous.keys.first) ? build.call(m, { "result" => effects.size - 1 }) : nil
    end
    nil
  end

  def target_ref(phrase, targets, offset)
    filter = target_filter(phrase) or return nil
    targets << filter
    { "target" => offset + targets.size - 1 }
  end

  # A target phrase as a filter, with a power/toughness/mana value comparison when it has one.
  def target_filter(phrase)
    m = TARGET_STAT.match(phrase) or return TARGETS[phrase]
    base = TARGETS[m[1]] or return nil
    name, restrictions = base.is_a?(String) ? [base, {}] : base.first
    range = { m[4] == "greater" ? "at_least" : "at_most" => Integer(m[3]) }
    { name => restrictions.merge(m[2].tr(" ", "_") => range) }
  end

  # "Put a stun counter on ..." / "Put two +1/+1 counters on ...": the counter name, or nil.
  def counter_name(word)
    name = word.downcase.tr(" -", "__")
    Enjine::Mechanics::Counters.valid?(name) ? name : nil
  end

  def number(word) = NUMBER[word] || Integer(word, exception: false)

  # A number word, or X (an amount announced while casting, CR 107.3a).
  def amount(word) = word == "X" ? "x" : number(word)

  # "This spell costs {2} less to cast if ..." / "for each ..." (CR 601.2f) and "Affinity for artifacts"
  # (CR 702.41a); "[Noncreature] spells you cast cost {1} less to cast." (a static cost modifier).
  COST_CONDITIONS = { "a creature is attacking you" => { "attacked" => true } }.freeze
  SPELL_KINDS = { "" => {}, "Creature " => { "any_of" => ["creature"] }, "Noncreature " => { "not" => ["creature"] },
                  "Artifact " => { "any_of" => ["artifact"] },
                  "Instant and sorcery " => { "any_of" => %w[instant sorcery] } }.freeze

  SPELL_COST_LINE = /\A(Creature\ |Noncreature\ |Artifact\ |Instant\ and\ sorcery\ )?[Ss]pells\ (you|your\ opponents)
                     \ cast\ cost\ \{(\d+)\}\ (less|more)\ to\ cast\.\z/x

  def cost_line(line)
    if line == "Affinity for artifacts"
      return { "cost_reduction" => { "amount" => { "count" => { "each" => "artifact", "controller" => "you" } } } }
    end

    if (m = SPELL_COST_LINE.match(line))
      modifier = { "caster" => m[2] == "you" ? "you" : "opponent", m[4] == "less" ? "reduce" : "increase" => Integer(m[3]) }
      kinds = SPELL_KINDS.fetch(m[1].to_s)
      return { "cost_modifier" => (kinds.empty? ? modifier : modifier.merge("spells" => kinds)) }
    end
    m = /\AThis spell costs \{(\d+)\} less to cast (?:if (.+)|for each (artifact|creature|land) you control)\.\z/.match(line)
    return nil unless m

    reduction = { "amount" => Integer(m[1]) }
    if m[3]
      reduction["amount"] = { "count" => { "each" => m[3], "controller" => "you" } }
      return nil unless m[1] == "1"
    elsif (condition = cost_condition(m[2]))
      reduction["if"] = condition
    else
      return nil
    end
    { "cost_reduction" => reduction }
  end

  def cost_condition(text)
    return COST_CONDITIONS[text] if COST_CONDITIONS.key?(text)

    phrase = text[/\Ait targets (?:a|an) (.+)\z/, 1] or return nil
    filter = TARGETS["target #{phrase}"]
    filter && { "targets" => filter }
  end

  CREATURE_TOKEN = %r{
    \ACreate\ (a|an|one|two|three|\d+)\ (tapped\ )?(\d+)/(\d+)
    \ (?:(?:white|blue|black|red|green|colorless)(?:\ and\ \w+)?\ )?
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
    when /\A(?:CARDNAME|This spell) deals (\d+|X) damage to (.+)\z/
      to = target_ref(::Regexp.last_match(2), targets, offset) || { "each opponent" => "each_opponent",
                                                                    "each player" => { "each" => "player" } }[::Regexp.last_match(2)]
      to && { "deal_damage" => { "amount" => amount(::Regexp.last_match(1)), "to" => to } }
    when /\AAdd ((?:\{[WUBRGC]\})+)\z/ then { "add_mana" => { "produce" => ::Regexp.last_match(1) } }
    when /\AAdd (one|two|three) mana of any (?:one )?color\z/
      { "add_mana" => { "amount" => number(::Regexp.last_match(1)), "color" => "any_one" } }
    when /\AAdd (two|three) mana in any combination of colors\z/
      { "add_mana" => { "amount" => number(::Regexp.last_match(1)), "color" => "any" } }
    when /\A(?:You draw|Draw) (a|two|three|\d+|X) cards?\z/ then { "draw" => { "amount" => amount(::Regexp.last_match(1)) } }
    when /\AEach player draws (a|two|three|\d+) cards?\z/
      { "draw" => { "amount" => number(::Regexp.last_match(1)), "to" => { "each" => "player" } } }
    when /\AYou gain (\d+|X) life\z/ then { "gain_life" => { "amount" => amount(::Regexp.last_match(1)) } }
    when /\AEach opponent loses (\d+) life\z/ then { "lose_life" => { "amount" => Integer(::Regexp.last_match(1)),
                                                                      "to" => "each_opponent" } }
    when %r{\A(#{TARGET_PHRASES}) gets \+(\d+)/\+(\d+) until end of turn\z}io
      to = target_ref(::Regexp.last_match(1).downcase, targets, offset)
      { "pump" => { "power" => Integer(::Regexp.last_match(2)), "toughness" => Integer(::Regexp.last_match(3)), "to" => to } }
    when %r{\ACreatures you control get \+(\d+)/\+(\d+) until end of turn\z}
      { "pump" => { "power" => Integer(::Regexp.last_match(1)), "toughness" => Integer(::Regexp.last_match(2)),
                    "to" => { "each" => "creature", "controller" => "you" } } }
    when /\ADestroy all (?:non(artifact|land) )?creatures\z/
      filter = ::Regexp.last_match(1) ? { "creature" => { "not" => [::Regexp.last_match(1)] } } : "creature"
      { "destroy" => { "to" => { "each" => filter } } }
    when /\ADestroy (#{TARGET_PHRASES})\z/o
      { "destroy" => { "to" => target_ref(::Regexp.last_match(1), targets, offset) } }
    when /\ACounter (target spell|target noncreature spell|target spell with mana value \d+ or (?:greater|less))\z/
      { "counter" => { "to" => target_ref(::Regexp.last_match(1), targets, offset) } }
    when /\AAssimilate (#{TARGET_PHRASES})\z/o
      { "assimilate" => { "to" => target_ref(::Regexp.last_match(1), targets, offset) } }
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
    when /\A(#{TARGET_PHRASES}|CARDNAME|(?:E|e)(?:nchanted|quipped) creature) gains ([a-z ,]+) until end of turn\z/o
      who = ::Regexp.last_match(1)
      keywords = ::Regexp.last_match(2).split(/, (?:and )?| and /).map(&:strip)
      return nil unless supported_keywords?(keywords)

      to = if who == "CARDNAME" then "self"
           elsif who.match?(/\A[Ee](nchanted|quipped)/) then "attached" # CR 303.4m, 301.5f
           else target_ref(who, targets, offset)
           end
      { "grant" => { "keywords" => keywords.map { it.tr(" ", "_") }, "to" => to } }
    when /\ADraw a card for each (creature|artifact|land) you control\z/
      { "draw" => { "amount" => { "count" => { "each" => ::Regexp.last_match(1), "controller" => "you" } } } }
    when /\ACreate (a|an|one|two|three|\d+) (tapped )?(Treasure|Clue|Food) tokens?\z/
      { "create_token" => { "token" => ::Regexp.last_match(3), "amount" => number(::Regexp.last_match(1)),
                            "tapped" => !::Regexp.last_match(2).nil? }.reject { |k, v| k == "tapped" && !v } }
    when CREATURE_TOKEN
      creature_token(::Regexp.last_match)
    when SEARCH then search_effect(::Regexp.last_match)
    when %r{\APut (a|an|one|two|three|\d+) ([+-]\d+/[+-]\d+|[a-z]+) counters? on CARDNAME\z}
      counter_effect(::Regexp.last_match(2), ::Regexp.last_match(1), "self")
    when %r{\APut (a|one|two|three|\d+) ([+-]\d+/[+-]\d+|[a-z]+) counters? on each creature you control\z}
      counter_effect(::Regexp.last_match(2), ::Regexp.last_match(1), { "each" => "creature", "controller" => "you" })
    when /\ATap (#{TARGET_PHRASES}) and put (a|one|two|three|\d+) ([a-z]+) counters? on it\z/o
      to = target_ref(::Regexp.last_match(1), targets, offset)
      counters = counter_effect(::Regexp.last_match(3), ::Regexp.last_match(2), to)
      counters && [{ "tap" => { "to" => to } }, counters]
    when /\ACARDNAME deals (\d+) damage to each opponent\z/
      { "deal_damage" => { "amount" => Integer(::Regexp.last_match(1)), "to" => "each_opponent" } }
    when /\AYou lose (\d+) life\z/ then { "lose_life" => { "amount" => Integer(::Regexp.last_match(1)), "to" => "you" } }
    when %r{\APut (a|an|one|two|three|\d+) ([+-]\d+/[+-]\d+|[a-z]+) counters? on (#{TARGET_PHRASES})\z}o
      counter_effect(::Regexp.last_match(2), ::Regexp.last_match(1), target_ref(::Regexp.last_match(3), targets, offset))
    end
  end

  def counter_effect(word, amount, to)
    name = counter_name(word) or return nil
    { "add_counters" => { "counter" => name, "amount" => number(amount), "to" => to } }
  end

  ENTERS_WITH = %r{
    \A(?:CARDNAME\ enters|(Other\ )?(creatures)\ you\ control\ enter)\ with
    \ (a|an|one|two|three|\d+)\ (?:additional\ )?([+-]\d+/[+-]\d+|[a-z]+)\ counters?\ on\ (?:it|them)\.\z
  }x

  # A permanent entering with N counters of a kind, or (other) creatures you control entering with
  # extra counters (CR 614.1c).
  def enters_with_line(line)
    m = ENTERS_WITH.match(line) or return nil
    other, subject, count, word = m.captures
    name = counter_name(word) or return nil
    ability = { "counters" => { name => number(count) } }
    return { "enters_with_counters" => ability } unless subject

    ability["affects"] = { "each" => SUBJECTS.fetch(subject), "controller" => "you" }
    ability["affects"]["other"] = true if other
    { "enters_with_counters" => ability }
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
