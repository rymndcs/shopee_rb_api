# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- **Check:** `bundle exec rake` runs unit tests, the conformance suite, RuboCop and `conformance:verify`. It makes no network call; `rake test:live` is opt-in (credentials in `test/live/live_helper.rb`).
- **Sibling gems share files.** `CONTRACT.md`, `.rubocop.yml`, `Rakefile`, `Gemfile`, `test/support/fake_transport.rb` and everything in `test/conformance/` are byte-identical in `lazada_rb_api` and `tiktok_shop_rb_api`; this gem is the canonical copy. Never edit one alone: follow "Changing the contract" in `CONTRACT.md`, then `rake conformance:manifest`. The per-gem half of the suite is `test/conformance_adapter.rb`.
- **Public surface is enforced.** `test/conformance/contract.rb` lists every public constant and method with its exact parameters; anything extra must be declared in `lib/shopee_rb_api/extensions.rb`. Internal helpers are `private_constant`.
- **Hosts live only in `ENDPOINTS`** (`lib/shopee_rb_api/endpoints.rb`); no other URL literal belongs in `lib/`. Nothing scans for one; `test/conformance/hosts_test.rb` checks behaviourally that custom hosts are the only hosts reached.
- **Errors are classified by `(error, message)`** in `lib/shopee_rb_api/error_table.rb`; `test/fixtures/error_list.json` holds every documented pair and every one must map to a subclass.
- **Fixtures name their source** in `_source` (doc URL and pull date, or "recorded live <date>").
- **Never publish to RubyGems and never tag 1.0** until the live recording round has replaced the doc fixtures.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
