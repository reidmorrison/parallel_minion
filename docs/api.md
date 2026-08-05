---
layout: default
---

## ParallelMinion::Minion

### Create a new minion

Create a new thread in which to run the minion and then:

- log the time for the thread to complete processing
- log the exception without stack trace whenever an exception is thrown in the thread
- Re-raise any unhandled exception in the calling thread when it retrieves the result
- copy the logging tags from the current thread
- copy the specified ActiveRecord scopes to the new thread

#### Any number of arguments can be passed to the initializer
These arguments are passed into the supplied block in the order they are listed
   It is recommended to duplicate and/or freeze objects passed as arguments
   so that they are not modified at the same time by multiple threads

The _last_ parameter passed to the initializer must be a hash consisting of:

- `:description` `[String]`
    - Description for this task that the Minion is performing
    - Put in the log file along with the time take to complete the task

- `:timeout` `[Integer]`
    - Maximum amount of time in milli-seconds that the task may take to complete
      before #result times out
    - Set to `Minion::INFINITE` to give the thread an infinite amount of time to complete
    - Default: `Minion::INFINITE`
    - Notes:
        - `:timeout` does not affect what happens to the Minion running the
           the task, it only affects how long #result will take to return.
        - The Minion will continue to run even after the timeout has been exceeded
        - If `:enabled` is false, or ParallelMinion::Minion.enabled is false,
          then :timeout is ignored and assumed to be Minion::INFINITE
          since the code is run in the calling thread when the Minion is created
        - On timeout `#result` returns `nil`, which is indistinguishable from a minion
          that returned `nil` of its own accord. See
          [Detecting a timeout](#detecting-a-timeout) below

- `:metric` `[String]`
    - Name of the metric to forward to Semantic Logger when measuring the minion execution time
    - Example: `inquiry/address_cleansing`
    - Supplying a metric also generates a second metric with `/wait` appended, for example
      `inquiry/address_cleansing/wait`, which records how long the calling thread was blocked
      in `#result` waiting for the minion to complete
    - The wait is only recorded when the minion is still running at the time its result is
      requested, so a minion that has already completed records no wait at all
    - Default: none, no metrics are generated
    - See [How to implement](implement.html) for using these metrics to tune how work is
      divided among minions

- `:wait_metric` `[String]`
    - Override the name of the wait metric described above
    - Only applies when `:metric` has been supplied
    - Default: `"#{metric}/wait"`

- `:enabled` `[Boolean]`
    - Whether the minion should run in a separate thread
    - Not recommended in Production, but is useful for debugging purposes
    - Default: ParallelMinion::Minion.enabled?

- Proc / lambda
    - A block of code must be supplied that the Minion will execute
    - This block will be executed within the scope of the minion
      instance and _not_ within the scope of where the Proc/lambda was
      originally created.
    - This is done to force all parameters to be passed in explicitly
      and should be read-only or copies of the original data to prevent
      multiple minions from trying to write to the same objects

The overhead for moving the task to a Minion (separate thread) vs running it
sequentially is about 0.3 ms if performing other tasks in-between starting
the task and requesting its result.

The following call adds 0.5 ms to total processing time vs running the
same code in-line:

```ruby
   ParallelMinion::Minion.new(description: 'Count', timeout: 5) { 1 }.result
```

Note: The above timings are based on JRuby with it's thread-pool enabled

#### Example:

```ruby
ParallelMinion::Minion.new(10.days.ago, description: 'Doing something else in parallel', timeout: 1000) do |date|
  MyTable.where('created_at <= ?', date).count
end
```

### Carrying application context into a minion

A minion runs in a new thread, and a new thread starts with empty thread local state.
Anything the application keeps there is missing inside the minion:

- `ActiveSupport::CurrentAttributes`, so `Current.user` and friends are `nil`
- `ActsAsTenant.current_tenant` and equivalent multi-tenancy state
- `RequestStore`, and any `Thread.current[...]` set by the application or its gems

This is easy to miss because it is not only a correctness problem, and because it does not
show up in tests. Scoping that is *conditional* on such state fails **open** when the state
is missing. A multi-tenancy library that applies its tenant scope only when a current tenant
is set applies no scope at all inside a minion, so:

```ruby
ParallelMinion::Minion.new(description: 'Invoices') { Invoice.where(status: 'open').to_a }.result
```

returns the current tenant's invoices in the calling thread, and **every tenant's** invoices
inside a minion. Tests will not catch it: with minions disabled the block runs inline in the
calling thread, where the context is intact and the scope applies correctly.

Register a handler for any context that scoping depends on:

```ruby
ParallelMinion::Minion.register_context(
  capture: -> { ActsAsTenant.current_tenant },
  around:  ->(tenant, &block) { ActsAsTenant.with_tenant(tenant, &block) }
)
```

`capture` runs in the thread creating the minion and returns the value to carry across.
`around` runs inside the minion with that value and **must yield**, with the minion's task
running in the block it is given.

For Rails `Current` attributes:

```ruby
ParallelMinion::Minion.register_context(
  capture: -> { Current.attributes },
  around:  ->(attributes, &block) { Current.set(**attributes, &block) }
)
```

Register these during initialization, for example in an initializer or an `after_initialize`
block, so that every minion is covered.

Notes:

- Handlers run in registration order, with the first registered outermost
- Handlers run on the inline path too, so both paths behave identically and a broken handler
  shows up whether or not minions are enabled
- An exception raised by `capture` propagates out of `Minion.new`, since a broken handler is a
  configuration error rather than a task failure
- An `around` that never yields raises, rather than leaving `#result` to return `nil`
- ActiveRecord scopes are handled separately by `ParallelMinion::Minion.scoped_classes`, which
  copies a relation into the minion rather than re-establishing thread local state

### The Rails executor

Under Rails every minion runs inside the application executor, which the railtie configures
automatically. A minion runs outside the request cycle in a thread the framework knows nothing
about, and the executor is what gives that thread Rails' own semantics: reloading is held off
while the minion runs, and ActiveRecord connections and the query cache are returned when it
finishes.

Nothing needs configuring. To opt out, clear the setting after initialization:

```ruby
ParallelMinion::Minion.executor = nil
```

Notes:

- Only minions running in their own thread are wrapped. An inline minion runs in the calling
  thread, which already has the caller's execution context
- Context handlers registered with `register_context` run *inside* the executor, so Rails
  `Current` attributes carried across survive the reset the executor performs when it starts
- `#result` waits inside `ActiveSupport::Dependencies.interlock.permit_concurrent_loads`, so a
  minion that autoloads while the calling thread is blocked on it cannot deadlock against it.
  This matters on Rails 7.2; from Rails 8.1 the loading interlock no longer exists

### Detecting a timeout

When a minion does not finish within `:timeout`, `#result` gives up waiting and returns `nil`.
That `nil` says nothing about the minion, which is still running, and it is the same `nil` a
minion returns when its block legitimately produced no answer.

Use `#timed_out?` to tell them apart. It reports whether the most recent call to `#result` gave
up waiting, and is cleared once a later call does get a result:

```ruby
minion = ParallelMinion::Minion.new(order, description: 'Risk score', timeout: 500) do |order|
  RiskEngine.score(order)
end

score = minion.result
raise 'Risk engine too slow' if minion.timed_out?
```

This matters whenever the minion computes something a decision depends on. Code along the lines
of `score = minion.result.to_i` silently turns a timeout into a score of zero, so the check is
skipped at exactly the moment the system is under load and the check is most needed. Either test
`#timed_out?`, or set `:on_timeout` so the wait raises instead of returning.

### Disabling Minions

In the event that strange problems are occurring in production and no one is
sure if it is due to running the minion tasks in parallel, a simple configuration
setting can disable minions. This setting will make all minion tasks run in
the same thread that they were called from. When disabled, the block supplied
to the minion will be executed inline before continuing to process subsequent steps.

It may also be useful to disable minions on a single production server to compare
its performance to that of the servers running with minions active. Great for
proving the performance benefits of minions.

To disable minions / make them run in the calling thread, add the following
lines to config/environments/production.rb:

```ruby
  # Make minions run immediately in the current thread
  config.parallel_minion.enabled = false
```

If running outside of Rails, add the following line in you code:

```ruby
  # Make minions run immediately in the current thread
  ParallelMinion::Minion.enabled = false
```
