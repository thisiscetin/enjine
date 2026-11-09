# frozen_string_literal: true

module Enjine
  module Mechanics
    module Keywords
      # Changeling (CR 702.73a, 2026-11-06 numbering): a characteristic-defining ability, "this object is
      # every creature type". It works in every zone (CR 604.3, 113.6a), so it is applied with the object's
      # copiable values (Engine::Characteristics#copy_base): the object's subtypes then include every
      # creature type, and subtype filters, "creature types among" counts and type-changing effects
      # (layer 4) see them like printed ones.
      class Changeling < Primitive
        primitive :keyword, :changeling,
                  description: "This object is every creature type (a characteristic-defining ability that works " \
                               "in all zones).",
                  rules: %w[702.73a 604.3 205.3m 113.6a], example: { "keywords" => ["changeling"] }

        # CR 205.3m (2026-11-06): every creature type, written as card data subtypes (lowercase, "-" and
        # spaces become "_", apostrophes dropped).
        CREATURE_TYPES = %w[
          time_lord advisor aenar aetherborn alien ally andorian android angel antelope ape archer archon armadillo
          army artificer assassin assembly_worker astartes atog aurochs avatar azra badger bajoran balloon barbarian
          bard basilisk bat bear beast beaver beeble beholder berserker betazoid bird bison blinkmoth boar bolian
          borg brikar bringer brushwagg caitian camarid camel capybara cardassian caribou carrier cat centaur child
          chimera citizen cleric clown cockatrice construct coward coyote crab crocodile ctan custodes cyberman
          cyclops dalek dauthi demigod demon denobulan deserter detective devil dinosaur djinn doctor dog dragon
          drake dreadnought drix drone druid dryad dwarf echidna edosian efreet egg el_aurian elder eldrazi
          elemental elephant elf elk employee eternal excalbian eye faerie ferengi ferret fish flagbearer fox
          fractal frog fungus gamer gamma gargoyle germ giant giraffe gith glimmer gnoll gnome goat goblin god golem
          gorgon gorn graveborn gremlin griffin guest hag halfling hamster harpy hedgehog hellion hero hippo
          hippogriff hirogen homarid homunculus horror horse human hydra hyena illusion illyrian imp incarnation
          inhuman inkling inquisitor insect jackal jellyfish jemhadar juggernaut kangaroo kavu kelpien kirin kithkin
          klingon knight kobold kor kraken kree kwejian llama lamia lammasu lanthanite leech lemur leviathan
          lhurgoyf licid lizard lobster manticore masticore medusan melkotian mercenary merfolk metathran minion
          minotaur mite mole monger mongoose monk monkey moogle moonfolk mount mouse mutant myr mystic nakuhl
          nautilus necron nephilim nightmare nightstalker ninja noble noggle nomad nymph ocampa octopus officer ogre
          ooze orb orc orgg orion otter ouphe ox oyster pangolin peasant pegasus pentavite performer pest
          phelddagrif phoenix phyrexian pilot pincher pirate plant platypus porcupine possum praetor primarch prism
          processor q qu rabbit raccoon ranger rat rebel reflection rhino rigger robot rogue romulan sable
          salamander samurai sand saproling satyr scarecrow scientist scion scorpion scout sculpture seal serf
          serpent servo shade shaman shapeshifter shark sheep shiar siren skeleton skrull skunk slith sliver sloth
          slug snail snake soldier soltari sorcerer spawn specter spellshaper sphinx spider spike spirit splinter
          sponge spy squid squirrel starfish surrakar survivor symbiote synth talaxian talosian tamarian tellarite
          tentacle tetravite thalakos tholian thopter thrull tiefling tosk toy treefolk tribble trill trilobite
          triskelavite troll turtle tyranid unicorn utrom vampire varmint vau_nakat vedalken villain volver vorta
          vulcan wall walrus warlock warrior weasel weird werewolf whale wizard wolf wolverine wombat worm wraith
          wurm xindi yeti zombie zubera
        ].map(&:to_sym).freeze

        # The characteristics with every creature type added, if the object has changeling.
        def self.apply(chars)
          return chars unless chars.keywords.include?(:changeling)

          chars.with(subtypes: (chars.subtypes | CREATURE_TYPES).freeze)
        end
      end
    end
  end
end
