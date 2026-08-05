---
layout: default
---

## Upgrading
{:.no_toc}

**Contents**

* TOC
{:toc}

## Upgrading to v2.0

Most applications need no code changes. The minimum Ruby version has gone up, two behaviours
changed, and one new setting is worth applying deliberately.

### Ruby 3.2 is now the minimum

v1.4 ran on Ruby 2.5 and later. v2.0 requires **Ruby 3.2 or greater**.

**Who is affected.** Anyone on Ruby 3.1 or earlier. Bundler will refuse to install v2.0 rather
than failing at runtime, so this surfaces immediately.

**What to do.** Upgrade Ruby to 3.2 or later, or stay on v1.4. Every Ruby before 3.2 is now past
its end of life and no longer receives security fixes.

Both CRuby and JRuby are tested, on Ruby 3.2, 3.3, 3.4 and 4.0.

### `#completed?` no longer reports a blocked minion as finished

Previously `#completed?` was true for a thread that was dead **or sleeping**. A minion waiting on
a database call or an HTTP request therefore looked completed while it was still running, with
`#failed?` false and `#exception` `nil`.

It is now the exact opposite of `#working?`.

**Who is affected.** Code that used `#completed?` to decide whether a result was ready:

~~~ruby
# This was acting on a result the minion had not produced yet
use(minion.result) if minion.completed? && !minion.failed?
~~~

**What to do.** In most cases, nothing: the new behaviour is what the code intended. If you were
relying on `#completed?` returning true early, that was a bug being masked. To wait for a result,
just call `#result`, which waits for you.

### Minions now run inside the Rails executor

Under Rails, every minion now runs inside `Rails.application.executor`, configured by the railtie.
Reloading is held off while a minion runs, and ActiveRecord connections and the query cache are
managed the way Rails manages them during a request.

**Who is affected.** Rails applications. There is nothing to configure, and for most applications
this only removes surprises rather than creating them.

**What to do.** Nothing, unless you have a reason to opt out:

~~~ruby
ParallelMinion::Minion.executor = nil
~~~

### Register any context your scoping depends on

This is not a behaviour change. It is a gap that has always existed and now has a fix, and it is
worth acting on because when it bites, it fails *open*.

Thread local state has never crossed into a minion. Libraries whose scope is conditional on that
state apply **no scope at all** inside a minion, so a query that is correctly scoped in the
calling thread can return rows it should not.

**Who is affected.** Applications using `ActiveSupport::CurrentAttributes`, `ActsAsTenant`,
`RequestStore`, or their own `Thread.current[...]` for anything a query scopes on.

**What to do.** Register a handler at startup:

~~~ruby
# config/initializers/parallel_minion.rb
ParallelMinion::Minion.register_context(
  capture: -> { Current.attributes },
  around:  ->(attributes, &block) { Current.set(**attributes, &block) }
)
~~~

Note that your test suite will not tell you whether you needed this. With minions disabled the
block runs inline, where the context is intact. See
[Carrying request context into a minion](rails.html#carrying-request-context-into-a-minion).

### Rails 5.1 through 7.1 are no longer tested

Rails 7.2, 8.0 and 8.1 are tested. Rails remains optional.

### New in v2.0

* **`#timed_out?`** distinguishes a `nil` returned because the minion timed out from a `nil` the
  block itself produced. See [Step 6](guide.html#step-6-tell-a-timeout-apart-from-a-real-nil).
* **`register_context`** carries thread local application context into a minion, described above.
* **`Minion.executor`** exposes the executor setting.

### Fixed in v2.0

* `#result` now joins the minion's thread on every path. The join was previously skipped when the
  minion had already finished, which on JRuby and TruffleRuby could drop an exception raised
  inside the minion, so `#result` returned instead of re-raising.
* The cleanup that returns ActiveRecord connections to the pool now runs with asynchronous
  interrupts masked, so an `:on_timeout` exception can no longer abort it part way and return a
  connection to the pool mid-transaction.
* `Minion.current_scopes` is now defined unconditionally. It was previously defined only if
  ActiveRecord had already loaded, so an application that loaded ActiveRecord later raised
  `NoMethodError` on every threaded minion.
