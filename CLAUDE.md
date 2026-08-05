# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`parallel_minion` is a small Ruby gem that wraps a block of code in a "Minion" so it runs on a
parallel thread, re-raising any exception in the caller's thread when the result is requested.
See `docs/` (published to http://reidmorrison.github.io/parallel_minion) for user-facing docs.

## Commands

```sh
appraisal install                  # Install gems for every supported Rails version, regenerates gemfiles/
rake                               # Default: all appraisals + rubocop
rake test                          # Tests against the top-level Gemfile only
rake rubocop                       # Lint
rake rubocop:autocorrect           # Safe autocorrect only

appraisal rails_8.0 rake           # Tests for one Rails version
appraisal rails_8.0 ruby test/minion_test.rb                          # One file
appraisal rails_8.0 ruby test/minion_test.rb -n "/raise exception/"   # One test case
```

Tests write to `test.log` (SemanticLogger at `:trace`) rather than stdout, so check that file when
diagnosing a failure.

## Architecture

### Two execution paths, chosen at construction

`Minion#initialize` runs the block **immediately**; there is no separate start step. It dispatches to
one of two private methods based on `enabled`:

- `run` spawns a `Thread` and is the real concurrency path.
- `run_inline` executes in the caller's thread and renames the logger to `Inline` so logs make the
  difference obvious.

`enabled` is resolved per instance from the `enabled:` keyword, defaulting to the global
`Minion.enabled?`. Turning it off globally is a supported production/debug mode, not just a test
hook, so **any change to one path must be mirrored in the other**.

### Blocks run via `instance_exec`, not as closures

The block is evaluated in the scope of the Minion instance. This is deliberate: it forces data to be
passed in explicitly as arguments (by copy, to avoid cross-thread mutation) rather than captured. A
side effect the tests depend on is that Minion's own readers (`description`, `timeout`, `enabled?`)
are visible inside the block.

### What gets carried across the thread boundary

`run` captures three things from the parent thread before spawning, because none of them propagate
automatically:

1. SemanticLogger tags (`capture_tags`)
2. SemanticLogger named tags (`capture_named_tags`)
3. ActiveRecord scopes for `Minion.scoped_classes` (`self.class.current_scopes`)

`run_in_scope` rebuilds the scope chain inside the new thread by nesting a `.scoping` block per
class, since `.scoping` only accepts one class at a time. The thread's `ensure` calls `cleanup`,
which returns AR connections to the pool via `connection_handler.clear_active_connections!` (the
non-deprecated form as of Rails 7).

`cleanup` runs under `Thread.handle_interrupt(Exception => :never)`. An `ensure` is a valid
interrupt checkpoint, so the `Thread#raise` behind `:on_timeout` can otherwise abort cleanup
partway and hand a connection back to the pool mid-transaction. Anything that ends up masked
surfaces from `cleanup`'s own `rescue` and is recorded in `@exception`.

### Error and timeout semantics live in `#result`

The worker thread stores its exception rather than raising; `#result` re-raises it in the caller's
thread. Both paths intentionally `rescue Exception` (with scoped `rubocop:disable
Lint/RescueException`) so nothing escapes the thread unreported. Do not narrow these to
`StandardError`.

`:timeout` bounds how long **`#result` waits**, not how long the minion runs. A timed-out `#result`
returns `nil` and the minion keeps going, unless `:on_timeout` is set, in which case that exception
class is raised *on the worker thread* to terminate it.

That `nil` is ambiguous, since a minion may return `nil` itself, so `#result` also sets
`timed_out`, cleared again by any later call that does get a result. Callers deciding anything on
the result need `#timed_out?` or `:on_timeout`, otherwise a slow minion reads as a real answer.

### ActiveRecord and Rails are optional

The gemspec depends only on `semantic_logger`. AR and Rails support is guarded by `defined?` checks
throughout, and `railtie.rb` is required only `if defined?(Rails)`. The railtie sets
`config.parallel_minion` to the `Minion` class itself, so Rails config assigns straight onto class
attributes.

This split is mirrored in the tests, and should be preserved:
- `test/minion_test.rb` deliberately never requires Rails or AR, proving the gem stands alone.
- `test/minion_scope_test.rb` requires `active_record` and exercises scope copying against sqlite3.

## Gotchas

- **Both execution paths are covered.** `minion_test.rb` line 13 iterates `[false, true]`, so every
  test runs inline and threaded. Keep it that way: narrowing it to `[false]` silently turns every
  `if enabled` branch in the file, including both timeout tests, into dead code while the suite
  stays green.
- **A test asserting on thread state must first let the minion block.** Checking `completed?` or
  `working?` immediately after construction races the scheduler, and the assertion passes whether or
  not the code is correct. Sleep until the minion has actually reached its blocking call.
- **`#result` must join the thread on every path, including when the minion has already finished.**
  The join is the only happens-before edge publishing `@result`/`@exception` to the caller. Dropping
  it looks harmless on CRuby, where the GVL hides the race, and breaks on JRuby/TruffleRuby.
- **`completed?` uses `!alive?`, deliberately not `Thread#stop?`.** `stop?` is true for a dead *or
  sleeping* thread, so it reports a minion blocked on I/O as completed.
- `.rubocop.yml` softens several metric limits on purpose. Prefer a targeted, commented
  `rubocop:disable` or a config change over contorting code, which is the pattern already in use.
- Running `bundle exec` can rewrite the `gemfiles/*.gemfile` files as a side effect. Check `git
  status` before committing so unintended regeneration is not swept into a commit.
