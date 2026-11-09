# Contributing to Enjine

Thanks for helping. Enjine aims to be a **strictly rules-accurate** Magic: The
Gathering engine, so a contribution counts when it's correct, tested and cites
the rules.

## Getting set up

```sh
git clone https://github.com/thisiscetin/enjine && cd enjine
bundle install
bundle exec rake          # specs + coverage gate + docs drift check + RuboCop: must pass
bundle exec exe/enjine    # play a hot-seat game to see the engine in action
```

Ruby 4.0+ is required. Enjine has **no runtime dependencies**. Please keep it that
way, because development dependencies go in the `Gemfile`.

## What to work on

- **Mechanics:** pick an item from [docs/MECHANICS_COVERAGE.md](docs/MECHANICS_COVERAGE.md).
  Do ★ mechanics that appear in current Standard first. Mechanics that only exist on
  cards no longer in Standard are low priority.
- **Bugs:** anything that differs from the Comprehensive Rules. Open an issue with the
  rule number, the seed and the decision log (`game.decision_log`), or a snapshot
  saved with the CLI's `s FILE` command.
- **Cards:** the gem ships none. The cards in `spec/fixtures/cards/` are for tests and
  fuzzing, and `examples/` holds demo decks; neither is in the gem. Card databases belong
  outside it. See
  [docs/guides/card-data-format.md](docs/guides/card-data-format.md).

## How to add a mechanic

Follow [docs/guides/adding-a-mechanic.md](docs/guides/adding-a-mechanic.md). In short:

1. Write a primitive in `lib/enjine/mechanics/<category>/<mechanic>.rb` with its description,
   parameters, example and CR rule numbers.
2. Change game state only through engine methods that emit events.
3. If you add state, update `State`, `Snapshot` (build and validation) and `View`.
4. Run `bundle exec rake docs` to regenerate `SUPPORTED.md` and `docs/reference/`.
   Never edit those files by hand.
5. Add tests at all three levels:
   - **Unit** (`spec/unit`): data validation and error paths.
   - **Integration** (`spec/integration`): build a board with the scenario DSL
     (`build_game`), then assert the legal options, submit a decision, and assert
     the resulting state and events.
   - **End-to-end:** add a card using the mechanic to the sample pool so
     `rake fuzz` exercises it.

## Ground rules

- **Cite the rules.** Use `# CR 704.5a`-style comments in code and rule numbers in
  spec names, against the version pinned in `lib/enjine/version.rb`.
  `spec/unit/cr_citations_spec.rb` fails if a cited number doesn't exist in that
  version (its rule numbers are vendored in `spec/fixtures/cr/rule_numbers.txt`).
  To re-pin, run `bundle exec rake "cr_citations[path/to/MagicCompRules.txt]"`,
  renumber what moved, then regenerate the list with
  `ruby script/check_cr_citations.rb --extract path/to/MagicCompRules.txt`.
- **Keep it deterministic.** Use only the game's `Rng`, never `Kernel#rand` or wall
  clock time, and never depend on hash ordering you don't control.
- **Keep decisions atomic.** Expose each choice as its own small decision with an
  explicit option list. Don't add hidden automation or "smart" defaults.
- **Keep cards as data.** A card never needs Ruby code. If one would, the engine is
  missing a primitive.
- **Make changes atomic.** An illegal call raises and leaves the game untouched.
- **Fail loudly.** Unknown card data is an error with a path, never silently ignored.

## Pull requests

- Keep each pull request to one mechanic or fix, with tests and regenerated docs.
- `bundle exec rake` must pass. CI also runs a short fuzz.
- Describe the rules involved (with rule numbers) and any edge cases you chose not
  to handle yet.

## License

By contributing, you agree that your contributions are licensed under the MIT
License (see [LICENSE.txt](LICENSE.txt)).
