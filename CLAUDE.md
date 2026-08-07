# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`parallel_minion` is a small Ruby gem that wraps a block of code in a "Minion" so it runs on a
parallel thread, re-raising any exception in the caller's thread when the result is requested.
See `docs/` (published to https://minion.reidmorrison.com, via the `CNAME` in that directory) for
user-facing docs. Pages: Home, Guide, Tuning, Rails, Reference, Upgrading. The nav is generated
from the `nav_items` list in `docs/_layouts/default.html`, so a new page must be added there too.

## Docs

The site also serves two files for AI assistants: `docs/llms.txt`, a hand-maintained index of the
pages (update it when adding or renaming one), and `docs/llms-full.txt`, every page concatenated.
**After editing any `docs/*.md` page, re-run `bundle exec rake llms_full`** and commit the result;
never edit `llms-full.txt` by hand. A new page also goes in `LLMS_PAGES` in the `Rakefile`, which
sets the order; the task raises if a `docs/*.md` page is missing from it. The
`docs/*.md` sources also ship inside the gem package (see `spec.files` in the gemspec) so coding
agents inside applications can read them locally.

`AGENTS.md` exists only to point other agents at this file. Keep guidance here, not there.

`test/docs_test.rb` verifies the Ruby examples in `docs/*.md`: every example must parse, and every
example that can stand on its own is executed against doubles, one test per example. Before it
existed several examples had been wrong for years, including a `SemanticLogger.add_appender` call
using an API removed several major versions earlier.

An example that genuinely cannot run standalone is exempted in the markdown itself, on the line
directly above its fence:

```markdown
<!-- doc-test: skip needs a Rails application -->
~~~ruby
```

Reach for that last. A skip drops the example back to syntax checking only, which is the state
that let them drift. Prefer making the example runnable, usually by adding a double to
`DocsTest::DocExamples` or by letting `teardown` put a global setting back. Markers are stripped
from `llms-full.txt`, and the test fails if one drifts away from its fence.

Examples in the `lib/` comments are **not** covered, and have to be checked by hand.

The sister project `semantic_logger` (same author, `../semantic_logger`) is the reference for
anything structural: gemspec layout, `CHANGELOG.md` format, the docs site theme, the `llms.txt` /
`llms-full.txt` / `AGENTS.md` set, and the Rakefile tasks. Look there first and stay diffable with
it rather than inventing a second convention.

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

### Blocks run via `instance_exec`

The block is evaluated with `self` set to the Minion instance, to push callers toward passing data
in explicitly as arguments rather than reaching out of the block. Be precise about what that
actually does, since only `self` changes and the block is still a closure:

| Inside the block                             | Result                                    |
|----------------------------------------------|-------------------------------------------|
| Local from the enclosing scope                | **Still visible**, captured lexically     |
| Method on the enclosing object                | `NameError`                                |
| Instance variable of the enclosing object     | **Silently `nil`**, `self` is the Minion  |
| `description`, `timeout`, `enabled?`          | The Minion's own readers, tests rely on it |

So `instance_exec` is a convention, not an enforcement: a local variable can still be captured and
mutated from both threads. The commented-out "not have access to local variables" test in
`minion_test.rb` documents this, and would fail if uncommented. Do not describe the block as
non-closing over its scope, in code comments or docs.

### What gets carried across the thread boundary

A new thread starts with empty thread local state, so nothing propagates automatically. Five things
are captured in the calling thread and rebuilt inside the minion:

1. SemanticLogger tags (`capture_tags`)
2. SemanticLogger named tags (`capture_named_tags`)
3. ActiveRecord scopes for `Minion.scoped_classes` (`self.class.current_scopes`)
4. The Rails executor, `Minion.executor`, into `@executor`
5. Application context registered via `Minion.register_context` (`capture_contexts`)

The first four are captured in `run`, so they only apply to the threaded path. Contexts are
captured in `initialize` instead, so that capture always happens in the calling thread, applies to
both paths, and a handler raising during capture surfaces from `Minion.new` rather than as a task
failure. `run_in_context` nests one `around` per handler, first registered outermost, and raises if
a handler never yields rather than letting `#result` return nil for a task that never ran.

Anything **not** in that list is absent inside a minion: `CurrentAttributes`, `ActsAsTenant`,
`RequestStore`, bare `Thread.current[...]`. That is a fail-open, not just a correctness gap, since
scoping conditional on such state applies no scope when the state is missing. It is also invisible
to tests, because the inline path runs in the calling thread where the context is intact. Handlers
therefore run on the inline path too, so a broken one cannot hide there.

`run_in_scope` rebuilds the scope chain inside the new thread by nesting a `.scoping` block per
class, since `.scoping` only accepts one class at a time. The thread's `ensure` calls `cleanup`,
which returns AR connections to the pool via `connection_handler.clear_active_connections!` (the
non-deprecated form as of Rails 7).

`cleanup` runs under `Thread.handle_interrupt(Exception => :never)`. An `ensure` is a valid
interrupt checkpoint, so the `Thread#raise` behind `:on_timeout` can otherwise abort cleanup
partway and hand a connection back to the pool mid-transaction. Anything that ends up masked
surfaces from `cleanup`'s own `rescue` and is recorded in `@exception`.

### The Rails executor wraps the threaded path

`Minion.executor` is assigned `Rails.application.executor` by a railtie initializer, and `run`
wraps the thread body in it. That is what gives a thread Rails knows nothing about the framework's
own semantics: reloading held off for the duration, connections and query cache returned at the end.

Two ordering constraints, both load-bearing:

- The executor must be **outside** `run_in_context`. It calls `CurrentAttributes.clear_all` from
  both its run and complete hooks, so contexts applied outside it are wiped before the task runs.
  `test/minion_executor_test.rb` locks this in and fails if the nesting is swapped.
- `#result` waits inside `interlock.permit_concurrent_loads`. The waiting thread is usually in the
  executor itself holding the interlock, and a minion that autoloads while the caller blocks on it
  deadlocks. Real on Rails 7.2, a no-op from 8.1 where Zeitwerk retired the loading interlock.

`with_executor` uses `@executor`, captured by `run`, and must not read `Minion.executor` itself. A
new thread reaches the minion body whenever it is first scheduled, which can be well after
`Minion.new` returned, so reading the class setting in there binds the minion to whatever executor
happens to be set at that later moment. That surfaced as a rare CI failure where a fire-and-forget
minion from an earlier test fired the *next* test's `to_complete` hook.

Only the threaded path is wrapped. Inline minions run in the caller's thread, which already has the
caller's execution context, and wrapping it would reset that thread's `CurrentAttributes` when the
minion finished. This is a deliberate exception to the mirror rule above.

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
- **Do not guard a method definition on `defined?(SomeGem)`.** That decides at load time whether
  the method exists, while callers test `defined?` at run time. `self.current_scopes` was declared
  inside `if defined?(ActiveRecord)` and vanished whenever ActiveRecord finished loading after this
  class did, so every threaded minion raised `NoMethodError`. Define the method and guard the call.
- `.rubocop.yml` softens several metric limits on purpose. Prefer a targeted, commented
  `rubocop:disable` or a config change over contorting code, which is the pattern already in use.
- Running `bundle exec` can rewrite the `gemfiles/*.gemfile` files as a side effect. Check `git
  status` before committing so unintended regeneration is not swept into a commit.

## Releasing

`rake publish` tags, pushes the tag, and pushes the gem. It deliberately does **not** run the
tests: the gate is GitHub Actions going green on `main` across the whole matrix, not whichever
single Ruby and Rails pair happens to be installed locally. Do not add a test dependency to it.
