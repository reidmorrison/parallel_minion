---
layout: default
---

## Reference
{:.no_toc}

**Contents**

* TOC
{:toc}

Complete reference for `ParallelMinion::Minion`. For a step by step introduction, start with the
[Guide](guide.html).

## Creating a minion

~~~
ParallelMinion::Minion.new(*arguments, **options) { |*arguments| ... }
~~~

The block is required, and starts running immediately. There is no separate `start` method.

Any positional arguments are passed through to the block, in the order given:

~~~ruby
ParallelMinion::Minion.new(user_id, state, description: "Count") do |user_id, state|
  Person.where(user_id: user_id, state: state).count
end
~~~

Arguments are passed **by reference**. Parallel Minion does not copy them. Duplicate or freeze
anything that both threads might modify.

The block is evaluated in the scope of the minion instance, not where it was written, so it
cannot use local variables from the surrounding method. This is deliberate. A consequence is that
the minion's own readers, such as `description`, `timeout` and `enabled?`, are visible inside the
block.

### Options

#### `:description` `[String]`

Names the minion. Appears in its log entries and becomes its thread name.

Default: `"Minion"`

#### `:timeout` `[Integer]`

How many **milli-seconds** `#result` will wait before giving up.

Default: `ParallelMinion::Minion::INFINITE` (wait forever)

* Limits how long `#result` waits, **not** how long the minion runs. The minion keeps going after
  the timeout and is not killed, unless `:on_timeout` is also supplied.
* On timeout, `#result` returns `nil` and `#timed_out?` becomes true.
* Ignored when the minion is not enabled, since the block has already finished by the time
  `#result` is called.

#### `:on_timeout` `[Class]`

An exception class to raise **on the minion's own thread** when `#result` times out, ending it.

Default: `nil`, the minion keeps running

The `#result` call that times out still returns `nil`. Because the minion then ends with that
exception, any later `#result` raises it.

Only use this for work that is safe to abandon part way through. The exception can arrive at any
point in the block.

Has no effect when the minion is not enabled.

#### `:metric` `[String]`

Name of the metric to forward to Semantic Logger for this minion's execution time.

Default: `nil`, no metrics are generated

Supplying it generates a second metric with `/wait` appended, recording how long the calling
thread was blocked in `#result`. See [Tuning](tuning.html).

~~~ruby
ParallelMinion::Minion.new(
  address,
  description: "Cleanse address",
  metric:      "inquiry/address_cleansing"
) do |address|
  AddressCleanser.call(address)
end
# Emits: inquiry/address_cleansing        how long the minion took
#        inquiry/address_cleansing/wait   how long the caller waited
~~~

#### `:wait_metric` `[String]`

Overrides the name of the wait metric above. Only applies when `:metric` is supplied.

Default: `"#{metric}/wait"`

#### `:enabled` `[Boolean]`

Whether this minion runs on its own thread. When false the block runs in the calling thread,
immediately, before `Minion.new` returns.

Default: `ParallelMinion::Minion.enabled?`

#### `:log_exception` `[Symbol]`

How an exception raised in the block is logged.

| Value      | Logged                                    |
| :--------- | :---------------------------------------- |
| `:full`    | Exception class, message, and backtrace    |
| `:partial` | Exception class and message                |
| `:off`     | Nothing                                    |

Default: `:partial`

#### `:on_exception_level` `[Symbol]`

Log level used only when the block raises. One of `:trace`, `:debug`, `:info`, `:warn`, `:error`,
`:fatal`.

Default: `ParallelMinion::Minion.completed_log_level`

Useful for a minion whose result is ignored, where a failure would otherwise go unnoticed:

~~~ruby
ParallelMinion::Minion.new(
  customer,
  description:        "Save customer",
  log_exception:      :full,
  on_exception_level: :error
) do |customer|
  customer.save!
end
~~~

## Instance methods

### `#result`

Waits for the minion to finish and returns the block's return value.

* Re-raises in the calling thread any exception raised inside the block.
* Returns `nil` if `:timeout` elapsed first. Check `#timed_out?` to tell that apart from a block
  that returned `nil` itself.
* Can be called repeatedly. Later calls return the same value without waiting again.

### `#timed_out?`

Whether the most recent `#result` gave up waiting. Cleared by a later `#result` that does get a
value.

~~~ruby
score = minion.result
raise "Too slow" if minion.timed_out?
~~~

### `#working?`

Whether the minion is still running. Always false when not enabled.

### `#completed?`

Whether the minion has finished. The exact opposite of `#working?`. Always true when not enabled.

A minion blocked on a database call or an HTTP request is still `working?`, not `completed?`.

### `#failed?`

Whether the minion ended with an exception.

### `#exception`

The exception raised inside the block, or `nil`.

### `#duration`

How long the minion took, in **seconds**. `nil` while it is still running.

Note that `:timeout` and `#time_left` are in milli-seconds, while `#duration` is in seconds.

### `#time_left`

Milli-seconds remaining before `#result` would give up. `0` when none is left, and `nil` when
`:timeout` was not supplied.

### `#arguments`

The arguments the minion was created with.

### `#description`, `#timeout`, `#enabled?`, `#metric`, `#wait_metric`, `#on_timeout`, `#log_exception`, `#on_exception_level`, `#start_time`

Readers for the values the minion was created with.

## Class settings

### `.enabled` / `.enabled?`

Whether new minions run on their own thread.

~~~ruby
ParallelMinion::Minion.enabled = false
~~~

Default: `true`

Only affects minions created after it is set. Under Rails, prefer
`config.parallel_minion.enabled`.

### `.register_context(capture:, around:)`

Carries application context held in thread local state into every minion. A minion's thread
starts with empty thread local state, so `CurrentAttributes`, `ActsAsTenant`, `RequestStore` and
any `Thread.current[...]` are otherwise missing inside it.

~~~ruby
ParallelMinion::Minion.register_context(
  capture: -> { ActsAsTenant.current_tenant },
  around:  ->(tenant, &block) { ActsAsTenant.with_tenant(tenant, &block) }
)
~~~

* `capture` runs in the thread creating the minion and returns the value to carry across.
* `around` runs inside the minion with that value and **must yield**.

Handlers run in registration order, first registered outermost, and run on the inline path too.
An exception raised by `capture` propagates out of `Minion.new`. An `around` that never yields
raises.

See [Rails](rails.html#carrying-request-context-into-a-minion) for why this matters.

### `.context_handlers` / `.context_handlers=`

The registered handlers. Assign `[]` to clear them, which is mainly useful in tests.

### `.scoped_classes` / `.scoped_classes=`

ActiveRecord classes whose current scope is copied into every minion.

~~~ruby
ParallelMinion::Minion.scoped_classes = [Account, Invoice]
~~~

Default: `[]`

Covers scopes carried on an ActiveRecord relation. Scoping that depends on thread local state
needs `register_context` instead. See [Rails](rails.html#activerecord-scopes).

### `.executor` / `.executor=`

The Rails executor each minion runs inside. Assigned automatically by the railtie.

~~~ruby
ParallelMinion::Minion.executor = nil   # opt out
~~~

Default: `nil` without Rails, `Rails.application.executor` with it

### `.started_log_level` / `.completed_log_level`

Log levels for the "Started" and "Completed" messages. One of `:trace`, `:debug`, `:info`,
`:warn`, `:error`, `:fatal`.

~~~ruby
ParallelMinion::Minion.started_log_level = :debug
~~~

Default: `:info` for both

Setting an invalid level raises `ArgumentError`.

### `.current_scopes`

The current scope for each class in `scoped_classes`. Called internally when a minion is created.

## Constants

### `ParallelMinion::Minion::INFINITE`

The default `:timeout`, meaning wait forever. Equal to `0`.

## Logging

Every minion writes two log entries, "Started" and "Completed", the second carrying the duration.
A minion that had to be waited for writes a third recording the wait.

The minion's thread is named after its `:description`, so every log entry written inside the block
is attributable to that minion. Semantic Logger tags and named tags from the calling thread are
carried across automatically, so a request id set with `SemanticLogger.tagged` appears on the
minion's entries too.

An inline minion logs under the name `Inline` rather than `Minion`, so the two are easy to tell
apart in a log file.
