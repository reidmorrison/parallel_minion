---
layout: default
---

## Guide
{:.no_toc}

**Contents**

* TOC
{:toc}

This guide starts with a single minion and builds up to a request served by several at once.
Each step adds one idea, so work through them in order the first time.

Every example runs as written. If you want to follow along in `irb`:

<!-- doc-test: skip adds a $stdout appender, which would interleave with the test output -->
~~~ruby
require "parallel_minion"
require "semantic_logger"

SemanticLogger.add_appender(io: $stdout, formatter: :color)
SemanticLogger.default_level = :info
~~~

## Step 1: Run a block on another thread

Create a minion with a block. It starts running immediately, on its own thread:

~~~ruby
minion = ParallelMinion::Minion.new(description: "Slow task") do
  sleep 1
  "done"
end
~~~

There is no separate `start` method. By the time `Minion.new` returns, the block is already
running. The calling thread carries straight on to the next line.

`:description` names the minion. It appears in every log entry the minion writes, and becomes the
name of its thread, so it is worth making it specific. It defaults to `"Minion"`.

## Step 2: Collect the result

Call `#result` to get the block's return value:

~~~ruby
minion = ParallelMinion::Minion.new(description: "Slow task") do
  sleep 1
  "done"
end

# Other work happens here, taking its own time...

minion.result   # => "done"
~~~

`#result` waits for the minion to finish, so **where you call it decides what you gain**. Call it
immediately and you simply wait, having gained nothing:

~~~ruby
# Pointless: this is just sleep 1 with extra steps
ParallelMinion::Minion.new { sleep 1 }.result
~~~

The pattern that pays off is: start the minion early, do other work, call `#result` late.

`#result` can be called more than once. Later calls return the same value without waiting again.

## Step 3: Pass data in as arguments

Anything the block needs should be passed as an argument to `Minion.new`, and arrives as a block
parameter in the same order:

~~~ruby
minion = ParallelMinion::Minion.new(user.id, "FL", description: "Count") do |user_id, state|
  Person.where(user_id: user_id, state: state).count
end
~~~

### What the block can see

The block runs with `self` set to the minion itself, not the object you wrote it in. That has
consequences which are worth knowing precisely, because only some of them are obvious:

| Written inside the block                     | What happens                                    |
| :------------------------------------------- | :---------------------------------------------- |
| A local variable from the enclosing method    | **Still visible.** Blocks capture locals         |
| A method on the enclosing object              | `NameError`                                      |
| An instance variable of the enclosing object  | **Silently `nil`**                               |
| `description`, `timeout`, `enabled?`          | The minion's own readers                         |

The last two are the ones that catch people out.

An instance variable is the sharper edge. `self` is the minion, which has no `@customer` of its
own, so it evaluates to `nil` rather than raising:

~~~ruby
class OrderService
  def process
    @customer = Customer.find(1)

    # @customer is nil in here. No error, just nil.
    ParallelMinion::Minion.new { @customer.name }
  end
end
~~~

Pass it in instead:

~~~ruby
ParallelMinion::Minion.new(@customer) { |customer| customer.name }
~~~

Local variables *are* still reachable, so nothing stops you writing this:

~~~ruby
totals = {count: 0}

# Works, and is a data race waiting to happen
ParallelMinion::Minion.new { totals[:count] += 1 }
~~~

Passing arguments explicitly is a convention rather than something the language enforces here. It
is worth following anyway, because it makes what crosses the thread boundary visible in one place.

### Arguments are passed by reference

Parallel Minion does not duplicate arguments for you. If you pass something both threads might
modify, copy or freeze it yourself:

~~~ruby
# Risky: both threads now hold the same Hash
ParallelMinion::Minion.new(options) { |opts| opts[:count] += 1 }

# Safe: the minion gets its own copy
ParallelMinion::Minion.new(options.dup) { |opts| opts[:count] += 1 }

# Also safe: nobody can modify it
ParallelMinion::Minion.new(options.freeze) { |opts| opts[:count] }
~~~

Read-only access to shared data is fine. It is writing from two threads that causes trouble.

## Step 4: Let exceptions surface

An exception raised inside the block does not crash the minion's thread silently. It is captured,
and re-raised in your thread when you call `#result`:

~~~ruby
minion = ParallelMinion::Minion.new(description: "Risky") { raise "Something failed" }

begin
  minion.result
rescue RuntimeError => e
  puts e.message   # => "Something failed"
end
~~~

This is what makes moving existing code into a minion safe. Your existing `rescue` handlers
around the call site keep working, because the exception still arrives on your thread.

To check without raising:

~~~ruby
minion.failed?     # => true
minion.exception   # => #<RuntimeError: Something failed>
~~~

If you never call `#result`, the exception is still written to the log, so a fire-and-forget
minion cannot fail completely silently.

## Step 5: Give the wait a deadline

`:timeout` sets how many milliseconds `#result` will wait:

~~~ruby
minion = ParallelMinion::Minion.new(description: "Slow supplier", timeout: 500) do
  sleep 5
  "too late"
end

minion.result   # => nil, after about 500 ms
~~~

The most important thing to understand about `:timeout`:

> It limits **how long `#result` waits**, not how long the minion runs.

The minion is still running after the timeout. It is not killed. That is usually what you want
from an external call: return a partial answer to the user now, and let the minion finish writing
whatever it retrieved. Without a `:timeout`, `#result` waits forever.

## Step 6: Tell a timeout apart from a real nil

A timed out `#result` returns `nil`. So does a minion whose block returned `nil`. Use
`#timed_out?` to tell them apart:

~~~ruby
minion = ParallelMinion::Minion.new(order, description: "Risk score", timeout: 500) do |order|
  RiskEngine.score(order)
end

score = minion.result

if minion.timed_out?
  # The risk engine did not answer in time. Decide deliberately.
  raise "Risk engine too slow"
end
~~~

This matters whenever something is decided on the result. Code like this:

<!-- doc-test: skip deliberately wrong example, `approve!` is undefined -->
~~~ruby
# Wrong: a timeout silently becomes a score of zero
approve! if minion.result.to_i < THRESHOLD
~~~

turns a slow dependency into an approval, at exactly the moment the system is under load. Either
check `#timed_out?`, or use `:on_timeout` in the next step.

## Step 7: Stop a minion that has timed out

Sometimes letting the minion carry on is wrong, and you want it to stop. Pass an exception class
as `:on_timeout` and it is raised **on the minion's own thread**, ending it:

<!-- doc-test: skip raises Timeout::Error by design -->
~~~ruby
minion = ParallelMinion::Minion.new(description: "Slow supplier", timeout: 500, on_timeout: Timeout::Error) do
  sleep 5
end

minion.result       # => nil, after about 500 ms, and the minion is now being terminated
minion.result       # raises Timeout::Error, since the minion ended with it
~~~

The first `#result` still returns `nil`. The minion ends with that exception, so any later
`#result` raises it.

Use `:on_timeout` only for work that is safe to abandon part way through. The exception can arrive
at any point in the block, so a minion that writes to several places may stop between two of them.
For work with side effects, prefer a plain `:timeout` and let it finish.

## Step 8: Run several minions at once

Nothing changes when you use more than one. Start them all, then collect them:

~~~ruby
minions = [
  ParallelMinion::Minion.new(product_id, description: "Inventory") { |id| InventorySupplier.check(id) },
  ParallelMinion::Minion.new(user_name, description: "User info") { |name| UserSupplier.more_info(name) },
  ParallelMinion::Minion.new(user_id, description: "Requests") { |id| Request.where(user_id: id).count }
]

inventory, user_info, request_count = minions.map(&:result)
~~~

Because they run at the same time, the elapsed time is roughly that of the **slowest** minion, not
the sum.

## Step 9: A worked example

Here is a request that does four things in sequence. The comments give each step's average
duration:

~~~ruby
def process_request(request)
  # 150 ms
  person_count = Person.where(state: "FL").count

  # 320 ms
  request_count = Request.where(user_id: request.user.id).count

  # 1,800 ms, and sometimes hangs when the supplier does not respond
  inventory = InventorySupplier.check_inventory(request.product.id)

  # 1,500 ms
  user_info = UserSupplier.more_info(request.user.name)

  build_reply(person_count, request_count, inventory, user_info)
end
~~~

That totals about **3,770 ms**.

### Move the slowest call to a minion

The supplier call is both the slowest and the least reliable, so it goes first:

~~~ruby
def process_request(request)
  # Started first, so it runs while everything else happens
  inventory_minion = ParallelMinion::Minion.new(
    request.product.id,
    description: "Inventory lookup",
    timeout:     2_200
  ) do |product_id|
    InventorySupplier.check_inventory(product_id)
  end

  person_count  = Person.where(state: "FL").count                       # 150 ms
  request_count = Request.where(user_id: request.user.id).count         # 320 ms
  user_info     = UserSupplier.more_info(request.user.name)             # 1,500 ms

  # Collected last, after everything else is done
  inventory = inventory_minion.result

  build_reply(person_count, request_count, inventory, user_info)
end
~~~

The calling thread now does 150 + 320 + 1,500 = 1,970 ms of work while the minion spends 1,800 ms
on the supplier. They overlap, so the request takes about **1,970 ms**, down from 3,770 ms.

Notice that the minion was started at the very top and collected at the very bottom. That is the
single most important habit in this guide.

We also gave it a 2,200 ms timeout. If the supplier hangs, the request returns without inventory
data rather than hanging with it.

### Move a second call

The calling thread is now the slow side at 1,970 ms, so move some of its work off too:

~~~ruby
def process_request(request)
  inventory_minion = ParallelMinion::Minion.new(
    request.product.id,
    description: "Inventory lookup",
    timeout:     2_200
  ) do |product_id|
    InventorySupplier.check_inventory(product_id)
  end

  request_count_minion = ParallelMinion::Minion.new(
    request.user.id,
    description: "Request count",
    timeout:     500
  ) do |user_id|
    Request.where(user_id: user_id).count
  end

  # Leave the calling thread some work to do as well
  person_count = Person.where(state: "FL").count                        # 150 ms
  user_info    = UserSupplier.more_info(request.user.name)              # 1,500 ms

  request_count = request_count_minion.result
  inventory     = inventory_minion.result

  build_reply(person_count, request_count, inventory, user_info)
end
~~~

Now the calling thread does 1,650 ms of work, the inventory minion 1,800 ms, and the request
count minion 320 ms. The request takes about **1,800 ms**, set by the slowest of the three.

Down from 3,770 ms to 1,800 ms, with the same code doing the same work.

### What to notice

* **The floor is the slowest single piece.** No amount of extra minions gets below 1,800 ms while
  the inventory call takes that long. To go faster, that call has to be split up or made faster.
* **The calling thread should carry work too.** Leaving it idle while three minions run wastes a
  thread you already have.
* **Balance beats quantity.** The aim is for everything to finish at about the same moment.

Working out that balance is a measurement problem, not a guessing one, which is what
[Tuning](tuning.html) is about.

## Step 10: Turn minions off while debugging

Set `:enabled` to `false` and the block runs in the calling thread, immediately, before
`Minion.new` returns:

~~~ruby
ParallelMinion::Minion.new(description: "Debug me", enabled: false) { Person.count }
~~~

Everything else behaves the same: `#result` returns the value, exceptions are re-raised, and the
log entries appear as usual, but named `Inline` instead of `Minion` so you can tell them apart.
This puts a breakpoint inside the block back on your own stack.

To turn every minion off at once:

~~~ruby
ParallelMinion::Minion.enabled = false
~~~

Under Rails, use the configuration setting instead, as covered in the
[Rails guide](rails.html#disabling-minions).

Because `:timeout` only ever limited how long `#result` waited, and an inline minion has already
finished by then, `:timeout` and `:on_timeout` have no effect when disabled.

## Step 11: Check on a minion without waiting

To look at a minion's state without blocking:

~~~ruby
minion.working?     # true while it is still running
minion.completed?   # true once it has finished
minion.failed?      # true if it ended with an exception
minion.time_left    # milliseconds left before #result would give up, nil if no timeout
minion.duration     # how long it took, once finished
~~~

`#working?` and `#completed?` are exact opposites. A minion blocked on a database call is still
`working?`, not `completed?`.

Bear in mind that a minion which is `completed?` may still have failed, so check `#failed?` too,
or just call `#result` and let it raise.

## Next steps

* **[Tuning](tuning.html)** for measuring minions and dividing the work using real numbers.
* **[Rails](rails.html)** for the executor, request context, ActiveRecord scopes, and testing.
* **[Reference](api.html)** for every option and method.
