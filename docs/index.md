---
layout: default
heading: What is Parallel Minion?
---


**Contents**

* TOC
{:toc}

Parallel Minion runs a block of Ruby code on another thread, and gives you its result when you
ask for it.

A **minion** is one such block. You hand it work, carry on with something else, and collect the
answer later:

~~~ruby
minion = ParallelMinion::Minion.new(description: "Count people") { Person.count }

# Do other work here, while the minion counts...

count = minion.result
~~~

That is the whole idea. Work that used to run one step after another now overlaps, so the total
time is closer to the slowest single step than to the sum of all of them.

## Why use it?

### It is ordinary code, moved

Wrapping existing code in a minion does not change how that code behaves:

* The block returns its value through `#result`, exactly as it did before.
* An exception raised inside the block is re-raised in your thread when you call `#result`, so
  existing `rescue` handlers keep working.
* There are no actors, channels, supervisors, or callbacks to learn.

That is the difference between Parallel Minion and a general concurrency framework. There is one
class and one method to learn, so moving a slow block into a minion is usually a two line change
that any Ruby developer can review.

### Slow steps stop blocking each other

A request that makes three calls of 300 ms, 500 ms and 800 ms takes 1,600 ms when they run one
after another. Run them as minions and it takes about 800 ms, the time of the slowest one.

### A slow dependency does not sink the whole request

Give a minion a `:timeout` and `#result` stops waiting after that long. The request can return a
partial answer instead of hanging or failing outright, while the minion carries on in the
background and finishes its work.

### It tells you where the time went

Every minion logs how long it took, and how long the calling thread had to wait for it. Turn on
metrics and that data drives dashboards, which is what turns dividing up the work from guesswork
into something you can measure. See [Tuning](tuning.html).

## When do minions help?

Minions help when your code is **waiting on something else**: a database query, an HTTP call to
an external service, a file read, a cache lookup. CRuby releases the Global VM Lock while a
thread waits on I/O, so those waits genuinely overlap and the elapsed time drops.

Minions do **not** speed up pure Ruby computation on CRuby. Sorting a large array, rendering
templates, or doing arithmetic in Ruby all hold the GVL, so running two of them on two threads
takes the same total time as running them one after another. JRuby and TruffleRuby have no GVL
and do run such work in parallel.

A useful rule of thumb:

| The block spends its time...                        | Will a minion help? |
| :-------------------------------------------------- | :------------------ |
| Waiting on a database query                          | Yes                 |
| Waiting on an HTTP or gRPC call                      | Yes                 |
| Waiting on a file, socket, or cache                  | Yes                 |
| Running Ruby code, on CRuby                          | No                  |
| Running Ruby code, on JRuby or TruffleRuby           | Yes                 |

Creating a minion and immediately asking for its result costs roughly 0.1 ms more than running
the block in-line, measured on CRuby 3.4. So a block is worth moving into a minion once it takes
appreciably longer than that. In practice, anything that regularly takes more than a few
milliseconds is a candidate.

## Installation

Add it to your `Gemfile`:

<!-- doc-test: skip Gemfile fragment, not executable Ruby -->
~~~ruby
gem "parallel_minion"
~~~

Then:

~~~
bundle install
~~~

Or install it directly:

~~~
gem install parallel_minion
~~~

Parallel Minion depends only on
[Semantic Logger](https://logger.reidmorrison.com), which it uses for its logging and its built-in
timing and metrics.

Under Rails, that is all that is needed. A railtie wires up the configuration and the Rails
executor for you. See the [Rails guide](rails.html).

## Your first minion

Move one slow call onto a minion, and collect it after doing other work:

~~~ruby
# Start the slow call first, so it runs while we do everything else
inventory_minion = ParallelMinion::Minion.new(
  product_id,
  description: "Inventory lookup",
  timeout:     2_000
) do |id|
  InventorySupplier.check(id)
end

# Meanwhile, on this thread
person_count = Person.where(state: "FL").count

# Now collect the minion's answer
inventory = inventory_minion.result
~~~

Three things to notice, all covered step by step in the [Guide](guide.html):

1. **The minion is created and starts immediately.** There is no separate `start` call.
2. **`product_id` is passed in as an argument**, not captured from the surrounding code. That is
   deliberate, and the Guide explains why it matters.
3. **`#result` is called last**, after the other work. Calling it straight away would simply
   wait, and you would gain nothing.

## Where to go next

* **[Guide](guide.html)** builds up from a single minion to a request served by several, one
  step at a time. Start here.
* **[Tuning](tuning.html)** covers measuring minions in production, and using metrics and
  dashboards to work out how to divide up the work.
* **[Rails](rails.html)** covers the executor, carrying request context into a minion,
  ActiveRecord scopes, and testing.
* **[Reference](api.html)** documents every option and method.
* **[Upgrading](upgrading.html)** covers moving from v1 to v2.

## Compatibility

Parallel Minion requires Ruby 3.2 or greater, and is tested against Ruby 3.2, 3.3, 3.4 and 4.0,
on both CRuby and JRuby.

Rails is optional. When present, Rails 7.2, 8.0 and 8.1 are tested. Parallel Minion works
without Rails or ActiveRecord, in which case the Rails specific behaviour is simply not used.
