---
layout: default
---

Minions are short-lived tasks defined using blocks of code in Ruby. Their only
purpose is to run a block of code in a separate thread and then to return its result
on completion.

Parallel Minion is a pragmatic approach to handing work off to minions (threads) so that tasks
that would normally be performed sequentially can now be executed in parallel.
This allows Ruby and Rails applications to quickly perform several tasks at the same
time so that latency (overall processing time) is reduced.

Parallel Minion was created for a large Rails application that had been running for
quite some time. The business needed the application to reduce latency times.
The time to process key requests has already been reduced by over 30%. Latency will
be reduced further as minions are used throughout the code-base.

### Example

```ruby
minion = ParallelMinion::Minion.new(10.days.ago, description: 'Doing something else in parallel', timeout: 1000) do |date|
  MyTable.where('created_at <= ?', date).count
end

# Do other work here...

# Retrieve the result of the minion
count = minion.result

puts "Found #{count} records"
```

### Installation

    gem install parallel_minion

### Notes:

- Generally it makes sense to move a block of code into a minion if it takes longer
than 30ms to run. This due to the overhead of moving the block of code into
a separate thread.

- On JRuby it takes about 10ms to create a new thread, to reduce this time, enable
JRuby's built-in thread-pooling by adding the following line to .jrubyrc,
or setting the appropriate command line option:

```ruby
thread.pool.enabled=true
```

### Upgrading to v2.0

Most applications need no changes. Two behaviour changes are worth knowing about, and one
new setting is worth applying deliberately.

**`#completed?` no longer reports a blocked minion as finished.** It previously returned true
for a thread that was dead *or sleeping*, so a minion waiting on a database call or an HTTP
request looked completed while it was still running. It is now the exact opposite of
`#working?`. Code that treated `completed?` as "safe to read the result" was reading it too
early, most visibly in the pattern `use(minion.result) if minion.completed? && !minion.failed?`.

**Under Rails, minions now run inside the application executor.** The railtie configures this,
so reloading is held off while a minion runs and ActiveRecord connections are returned the way
Rails does it. See [The Rails executor](api.html#the-rails-executor) to opt out.

**Register any context your scoping depends on.** Thread local state has never crossed into a
minion, and libraries whose scope is conditional on it fail *open*, silently returning rows
they should not. v2 adds `register_context` to carry it across. If the application uses
`ActiveSupport::CurrentAttributes`, `ActsAsTenant`, `RequestStore`, or its own
`Thread.current[...]` for anything a query scopes on, read
[Carrying application context into a minion](api.html#carrying-application-context-into-a-minion)
and register a handler.

Also new: `#timed_out?` distinguishes a `nil` returned because the minion timed out from a
`nil` the minion itself produced. See [Detecting a timeout](api.html#detecting-a-timeout).

### Dependencies

Parallel Minion uses Semantic Logger due to it's high concurrency logging capabilities
and built-in benchmarking api's

- `semantic_logger`

### Compatibility

ParallelMinion requires Ruby 3.2 or greater, and is tested against Ruby 3.2, 3.3, 3.4 and 4.0.

Rails is optional. When present, Rails 7.2, 8.0 and 8.1 are tested.
