# Change Log

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [2.0.0] 2026-08-05

### Breaking changes

- `Minion#completed?` no longer reports a minion that is merely blocked as finished. It was
  implemented with `Thread#stop?`, which is true for a thread that is dead *or sleeping*, so a
  minion waiting on a database call or an HTTP request looked completed while it was still
  running, with `#failed?` false and `#exception` nil. It is now the exact complement of
  `#working?`. Code of the form `use(minion.result) if minion.completed? && !minion.failed?`
  was acting on a result the minion had not produced yet.
- Under Rails, minions now run inside the application executor, which the railtie assigns. The
  minion thread gets the framework's own semantics: reloading is held off while it runs, and
  ActiveRecord connections and the query cache are returned the way Rails does it. Set
  `ParallelMinion::Minion.executor = nil` after initialization to opt out.
- Ruby 3.2 is now the minimum supported runtime, up from 2.5 in v1.4. Earlier versions are end of
  life and are no longer tested. Ruby 3.2, 3.3, 3.4 and 4.0 are tested, on CRuby and JRuby.
- Rails 5.1 through 7.1 are no longer tested. Rails 7.2, 8.0 and 8.1 are.

### Added

- `ParallelMinion::Minion.register_context(capture:, around:)` carries application context held
  in thread local state into a minion. A minion runs in a new thread, which starts with empty
  thread local state, so `ActiveSupport::CurrentAttributes`, `ActsAsTenant.current_tenant`,
  `RequestStore` and any `Thread.current[...]` were all missing inside it. Scoping that is
  conditional on such state fails *open* when the state is absent, so a query that is tenant
  scoped in the calling thread could return every tenant's rows inside a minion. `capture` runs
  in the thread creating the minion, `around` re-establishes the context inside it and must
  yield. Handlers nest, first registered outermost, and run on the inline path too.
- `Minion#timed_out?` reports whether the most recent `#result` gave up waiting. Previously a
  timeout returned `nil`, indistinguishable from a minion that returned `nil` itself, so code
  that treated the value as an answer failed open exactly when the system was slow.
- `ParallelMinion::Minion.executor` sets the executor to run each minion in.

### Fixed

- `#result` now joins the minion thread on every path. The join was skipped when the minion had
  already finished, leaving `@result` and `@exception` to be read with no synchronization, since
  the join is what establishes the happens-before edge between the two threads. The GVL hides
  this on CRuby; on JRuby and TruffleRuby a stale read could drop an exception raised inside the
  minion, so `#result` returned instead of re-raising.
- The cleanup that returns ActiveRecord connections to the pool now runs with asynchronous
  interrupts masked. `:on_timeout` terminates a minion with `Thread#raise`, which fires at the
  next interrupt checkpoint, and an unguarded `ensure` is itself a valid checkpoint. An interrupt
  landing there aborted cleanup partway and returned a connection to the pool with its
  transaction still open, for the next request that checked it out to inherit.
- `Minion.current_scopes` is defined unconditionally. Guarding the definition with
  `if defined?(ActiveRecord)` decided at load time whether the method existed, while its caller
  tests `defined?(ActiveRecord::Base)` at run time, so whenever ActiveRecord finished loading
  after this class did, every threaded minion raised `NoMethodError`.
- `#result` waits inside `ActiveSupport::Dependencies.interlock.permit_concurrent_loads`, so a
  minion that autoloads while its caller is blocked on it cannot deadlock against it. Applies to
  Rails 7.2; from Rails 8.1 the loading interlock no longer exists.

### Security

- Pin the GitHub Actions used by CI to commit SHAs rather than mutable tags, and replace the
  retired `actions/checkout@v2`. Add `persist-credentials: false`, since nothing after checkout
  talks to the remote, and a top-level `permissions: contents: read`.
- Serve the documentation webfont over https. It was an http subresource on an https page.

### Documentation

- Rewrite the documentation site from an end user's perspective. The six overlapping pages are
  replaced by Home, a step by step Guide, Tuning, Rails, Reference and Upgrading, with the menu
  reorganised to match.
- Add a Tuning guide covering the `:metric` and `/wait` metrics, reading them on a dashboard, and
  running experiments to work out how to divide up the work.
- Every code example in the documentation is now executed as part of verification. Fixed the
  examples this found to be broken, including a `SemanticLogger.add_appender` call using an API
  removed several major versions ago, and an example that captured values the block could not see.
- Correct `#duration`, which is documented in seconds rather than milli-seconds, and correct the
  claim that a minion's block cannot close over local variables. `instance_exec` changes `self`,
  so a method call on the enclosing object raises and an instance variable reads as `nil`, but
  local variables are still captured.
- Replace the measured overhead figures, which dated from JRuby and were roughly 5 times the
  current cost, and frame minions around I/O bound work and the GVL.
- Correct the stated compatibility, which still claimed Ruby 1.9 through 2.1 and JRuby 1.7, and
  drop the Rails 4.0/4.1 connection pool patch note.
- Refresh the documentation site styling, and fill in the empty `scoped_classes` example in the
  source.
- Make the gem readable by AI coding assistants. The site now serves `llms.txt`, an index of the
  documentation following the llmstxt.org convention, and `llms-full.txt`, every page concatenated
  into one file and generated by `rake llms_full`. The `docs/*.md` sources ship inside the gem
  package, so an agent working in an application can read the manual locally, and `AGENTS.md`
  points agents at `CLAUDE.md`.

### Internal

- Raise test coverage to 100%, enforced with SimpleCov.
- Wire RuboCop into the default rake task and CI, and fix the outstanding offenses.
- Remove the stale generated gemfiles for Rails 5.1 through 7.0.

## [1.4.0] 2026-04-10

### Added

- Rails 7.2 support.

### Fixed

- CI, JRuby and Ruby 3.4 test failures.

### Changed

- Move CI from Travis to GitHub Actions.
- Update the rubygems source url.

## [1.3.0] 2018-03-28

### Added

- `:on_exception_level` to override the log level used when the block raises.

### Fixed

- Tagged logging.

## [1.2.1] 2017-05-10

### Added

- Tests for named tags.

### Changed

- Move the documentation to the master branch from `gh-pages`.

## [1.2.0] 2017-03-24

### Added

- `:wait_metric` to override the name of the generated wait metric.
- `started_log_level` and `completed_log_level` to make the started and completed message log
  levels configurable.

### Changed

- Only log tags when they are already present.
- Use Appraisal to manage the gemfile for each supported Rails version.

## [1.1.0] 2015-02-01

### Added

- `:on_timeout` to terminate a minion by raising the supplied exception class on its thread when
  it times out, rather than leaving it running.
- `#duration` is now set when the minion completes.

## [1.0.0] 2014-11-03

### Added

- `#arguments` to access the arguments a minion was created with after it has completed.

### Removed

- Support for Rubinius, which still lacked basic support for `Sync`.

## [0.4.1] 2014-04-16

### Fixed

- Include the metric name when calling Semantic Logger.

## [0.4.0] 2014-04-14

### Added

- Log a warning when a timeout occurs waiting for a minion.
- Additional logging when returning a result from a minion takes longer than 0.01 seconds.

## [0.3.0] 2014-04-11

### Added

- Support for the Semantic Logger `:metric` option.

### Changed

- Remove the dependency on ActiveRecord.

## [0.2.1] 2013-12-20

### Fixed

- Capture the current ActiveRecord scope with `Model.scoped` on Rails 3, since `Model.all` only
  returns the current scope on Rails 4 and above.

## [0.2.0] 2013-12-17

### Changed

- Use a different method to determine the current ActiveRecord scope.

## [0.1.0] 2013-12-04

### Changed

- Rename the `synchronous` option to `enabled`.

## [0.0.1] 2013-12-03

### Added

- Initial release.
