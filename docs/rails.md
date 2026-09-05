---
layout: default
title: Rails
description: >-
  Rails integration: the railtie, carrying request context into a minion,
  ActiveRecord scopes, database connections, the Rails executor, and testing.
---


**Contents**

* TOC
{:toc}

Parallel Minion works without Rails, but when Rails is present a railtie wires up the pieces that
make minions behave like the rest of your application. This page covers what that does, and the
one thing you should configure yourself.

## Setup

Add the gem to your `Gemfile`:

<!-- doc-test: skip Gemfile fragment, not executable Ruby -->
~~~ruby
gem "parallel_minion"
~~~

That is all. The railtie is loaded automatically and does two things:

1. Exposes every Parallel Minion setting through `config.parallel_minion`.
2. Runs every minion inside the Rails executor.

`config.parallel_minion` **is** the `ParallelMinion::Minion` class, so anything you can set on the
class you can set through the configuration:

<!-- doc-test: skip needs a Rails application -->
~~~ruby
# config/environments/development.rb
Rails.application.configure do
  config.parallel_minion.enabled            = false
  config.parallel_minion.started_log_level  = :debug
  config.parallel_minion.completed_log_level = :debug
end
~~~

## Carrying request context into a minion

This is the one thing worth configuring deliberately, and the one most likely to cause a subtle
bug if you skip it.

A minion runs on a new thread, and **a new thread starts with empty thread local state**. So
anything your application keeps there is missing inside a minion:

* `ActiveSupport::CurrentAttributes`, so `Current.user` and friends are `nil`
* `ActsAsTenant.current_tenant`, and equivalent multi-tenancy state
* `RequestStore`, and any `Thread.current[...]` set by your code or a gem

### Why this matters more than it looks

If that state only affected display, a `nil` would be obvious. The problem is that scoping is
often **conditional** on it, and conditional scoping fails *open*.

A multi-tenancy library that applies its tenant scope only when a current tenant is set applies
**no scope at all** when there is not one. So:

~~~ruby
ParallelMinion::Minion.new(description: "Invoices") { Invoice.where(status: "open").to_a }.result
~~~

returns the current tenant's invoices when run in the calling thread, and **every tenant's**
invoices when run in a minion.

Worse, tests do not catch it. With minions disabled the block runs inline in the calling thread,
where the context is intact and the scope applies correctly. The suite passes and production
leaks.

### Registering a handler

Tell Parallel Minion what to carry across:

~~~ruby
# config/initializers/parallel_minion.rb
ParallelMinion::Minion.register_context(
  capture: -> { ActsAsTenant.current_tenant },
  around:  ->(tenant, &block) { ActsAsTenant.with_tenant(tenant, &block) }
)
~~~

`capture` runs in the thread creating the minion and returns the value to carry across. `around`
runs inside the minion with that value, and **must yield**: the minion's task runs in the block
it is given.

For Rails `Current` attributes:

~~~ruby
ParallelMinion::Minion.register_context(
  capture: -> { Current.attributes },
  around:  ->(attributes, &block) { Current.set(**attributes, &block) }
)
~~~

For a plain thread local:

~~~ruby
ParallelMinion::Minion.register_context(
  capture: -> { Thread.current[:request_id] },
  around:  lambda { |request_id, &block|
    previous                     = Thread.current[:request_id]
    Thread.current[:request_id]  = request_id
    begin
      block.call
    ensure
      Thread.current[:request_id] = previous
    end
  }
)
~~~

Register handlers once at startup, in an initializer, so that every minion is covered.

### How handlers behave

* They run in registration order, with the first registered outermost.
* They run on the **inline path too**, even though the context is already correct there. That
  keeps both paths identical, so a broken handler shows up whether or not minions are enabled.
* An exception raised by `capture` propagates out of `Minion.new`. A broken handler is a
  configuration error, not a task failure, so it fails loudly and immediately.
* An `around` that never yields raises, rather than leaving `#result` to return `nil` for a task
  that never ran.

## ActiveRecord scopes

Scopes carried on an ActiveRecord relation are handled separately, because they live on the
relation rather than in thread local state.

List the classes whose current scope should be copied into every minion:

<!-- doc-test: skip needs a Rails application -->
~~~ruby
# config/initializers/parallel_minion.rb
Rails.application.config.after_initialize do
  ParallelMinion::Minion.scoped_classes = [Account, Invoice]
end
~~~

Use `after_initialize` so the models are loaded by the time they are referenced.

With that in place, a scope applied around a minion is applied inside it too:

~~~ruby
Account.where(active: true).scoping do
  # Runs as Account.where(active: true).count inside the minion
  ParallelMinion::Minion.new(description: "Active accounts") { Account.count }.result
end
~~~

Without registering `Account`, the same minion would return the count of **all** accounts, since
`Account.all` in a new thread is unscoped.

## Database connections

Each minion that talks to the database checks out its own connection from the pool, and returns
it when the minion finishes.

This has a direct consequence for pool sizing. A request that runs five minions, each querying
the database, can hold six connections at once, including the calling thread's. Size the pool for
the concurrency you actually create:

~~~yaml
# config/database.yml
production:
  pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5).to_i * 6 %>
~~~

A pool that is too small does not raise immediately. Minions block waiting for a connection,
which shows up as a large `/wait` on their metrics and looks like a slow query. If splitting a
minion makes things slower rather than faster, check the pool first.

## The Rails executor

Every minion runs inside `Rails.application.executor`, which the railtie configures for you.

A minion runs outside the request cycle, on a thread the framework knows nothing about. The
executor is what gives that thread the framework's own semantics: reloading is held off while the
minion runs, and ActiveRecord connections and the query cache are managed the way Rails manages
them for a request.

Nothing needs configuring. To opt out:

~~~ruby
ParallelMinion::Minion.executor = nil
~~~

Two details worth knowing:

* Only minions that run on their own thread are wrapped. An inline minion runs in the calling
  thread, which already has the caller's execution context.
* Context handlers registered with `register_context` run **inside** the executor. The executor
  resets `CurrentAttributes` when it starts, so a handler carrying `Current` across has to run
  inside it to survive. Parallel Minion arranges this for you.

## Disabling minions

To make every minion run in the calling thread:

<!-- doc-test: skip needs a Rails application -->
~~~ruby
# config/environments/development.rb
Rails.application.configure do
  # Run minions in the current thread to make debugging easier
  config.parallel_minion.enabled = false
end
~~~

This is worth doing in development. The block runs on your own stack, so a breakpoint inside a
minion behaves normally and backtraces make sense.

It is also useful in production, for two things covered in [Tuning](tuning.html#step-8-prove-the-benefit):
proving what minions are actually buying you, and ruling concurrency in or out when something is
behaving strangely.

## Testing

Most test suites should run with minions disabled:

<!-- doc-test: skip needs a Rails application -->
~~~ruby
# config/environments/test.rb
Rails.application.configure do
  config.parallel_minion.enabled = false
end
~~~

The reason is transactional tests. A test wrapped in a transaction that is rolled back afterwards
only works if every query runs on the same connection. A minion uses a different connection, so
it cannot see uncommitted data written by the test, and its own writes are not rolled back with
the test's transaction.

Running inline keeps everything on one connection and one thread, and results and exceptions
behave identically.

### Testing that minions themselves work

Disabling minions everywhere means the threaded path is never exercised. For the code where
concurrency actually matters, turn them back on for specific tests:

~~~ruby
def test_inventory_lookup_runs_in_parallel
  ParallelMinion::Minion.enabled = true

  result = service.process_request(request)

  assert_equal expected, result
ensure
  ParallelMinion::Minion.enabled = false
end
~~~

Bear in mind that these tests need committed data rather than transactional fixtures, since the
minion runs on its own connection.

This applies to context handlers too. A handler that is broken only on the threaded path will
pass every inline test, so it is worth having at least one test per handler that runs enabled.
