---
layout: default
---

## Tuning
{:.no_toc}

**Contents**

* TOC
{:toc}

Deciding what to move into a minion, and how to split the work between them, is the part that
actually determines how fast a request gets. It is also the part most often done by guesswork.

It does not have to be. Every minion already records how long it took and how long it kept the
calling thread waiting. Send those numbers to a dashboard and each change you make becomes an
experiment with a measurable outcome.

## Step 1: Measure before you parallelize

Start by finding out where the time actually goes. There is no point moving a 4 ms call onto a
thread.

Semantic Logger measures a block and logs how long it took:

~~~ruby
logger = SemanticLogger["Inventory"]

logger.measure_info("Counting rows") do
  Person.where(state: "FL").count
end
~~~

Under Rails, with the
[rails_semantic_logger](https://github.com/reidmorrison/rails_semantic_logger) gem, use
`Rails.logger`:

<!-- doc-test: skip needs rails_semantic_logger to define Rails.logger -->
~~~ruby
Rails.logger.measure_info("Counting rows") do
  Person.where(state: "FL").count
end
~~~

Outside Rails, set up a logger first:

<!-- doc-test: skip adds a file appender, which would leave a stray development.log -->
~~~ruby
require "semantic_logger"

SemanticLogger.default_level = :trace
SemanticLogger.add_appender(file_name: "development.log", formatter: :color)

logger = SemanticLogger["MyClass"]

logger.measure_info("Counting rows") do
  Person.where(state: "FL").count
end
~~~

Work through the request measuring each step. You are looking for two things:

1. **Which steps are slow enough to be worth moving.** Anything consistently over a few
   milliseconds is a candidate. Below that, the roughly 0.1 ms cost of a minion is not worth it.
2. **Which steps depend on each other.** A step that needs the output of another cannot run
   beside it. Those dependencies decide what is possible before any measurement does.

## Step 2: Name a metric on each minion

Once minions are in place, give each one a `:metric`:

~~~ruby
ParallelMinion::Minion.new(
  address,
  description: "Cleanse address",
  metric:      "inquiry/address_cleansing"
) do |address|
  AddressCleanser.call(address)
end
~~~

That is the only instrumentation needed. No timing code, no counters. Naming the metric is
enough, and it is worth using a consistent naming scheme such as `request_type/step_name` so that
related minions group together on a dashboard.

## Step 3: Understand the two numbers

A single `:metric` produces **two** metrics:

| Metric                             | What it measures                                                   |
| :--------------------------------- | :----------------------------------------------------------------- |
| `inquiry/address_cleansing`        | How long the minion itself took                                     |
| `inquiry/address_cleansing/wait`   | How long the calling thread sat in `#result` waiting for it         |

The second one is the one that drives tuning, and it is worth being precise about what it means.

Wait time is only recorded when the minion is **still running** at the moment its result is
requested. A minion that finished before you asked records no wait at all. So:

* **High wait** means the calling thread reached `#result` and then sat there. That minion is
  holding up the request.
* **Zero wait** means the minion had already finished. It cost the request nothing in elapsed
  time.

Rename the wait metric with `:wait_metric` if the default name does not suit your scheme.

## Step 4: Send the metrics to a dashboard

Metrics go nowhere until a subscriber is registered. Parallel Minion emits metrics through
Semantic Logger, so any backend it supports will do, including Statsd, New Relic, SignalFx, and
via ordinary log appenders, Elasticsearch and Splunk.

Registering one is a single line at startup, for example:

<!-- doc-test: skip needs a live statsd backend -->
~~~ruby
SemanticLogger.add_appender(metric: :statsd, url: "udp://localhost:8125")
~~~

The full list of backends, and their individual options, are covered in the
[Semantic Logger metrics documentation](https://logger.reidmorrison.com/metrics.html). Everything
below applies whichever one you use.

Build a dashboard with, per minion:

* **Duration**, as a percentile rather than a mean. The 95th and 99th percentiles are what your
  slowest users experience, and averages hide exactly the tail you are trying to fix.
* **Wait time**, on the same axis, so you can see the gap between the two.

And for the request as a whole:

* **Total elapsed time**, the number you are actually trying to reduce.
* **Total wait time across all minions**, which is how much of that elapsed time was spent
  blocked.

## Step 5: Read the dashboard

The goal is simple to state: **every minion should finish at about the same time**.

That balance sits between two failure modes, and the dashboard tells them apart at a glance.

**A minion that finishes early.** Its duration is well below the others and its wait is zero. It
consumed a thread but bought no time, because the request was never waiting on it. Give it more
work, merge it into another minion, or move it back to the calling thread.

**A minion that finishes late.** Its duration is the largest and it shows a big `/wait`.
Everything else is done and the request is sitting there waiting for this one. It sets the floor
for the whole request. Either split it into several smaller minions, or make the underlying call
faster.

So there are two numbers to move, and they pull against each other:

1. Drive **total wait time toward zero**.
2. While moving **as much work as possible** off the calling thread.

Neither is useful alone. Wait time can always be driven to zero by running everything
sequentially, which is the slowest possible arrangement. Work moved off the calling thread can
always be increased by spawning minions that nobody waits for. It is the pair together that
describes a well balanced request.

## Step 6: Run an experiment

With those numbers on a dashboard, changing how the work is divided stops being a guess:

1. **Form a hypothesis.** "The inventory minion sets our floor at 1,800 ms. Splitting it into
   three regional lookups should bring it to about 600 ms."
2. **Change one thing.** One split, one merge, one call moved. Changing several at once makes the
   result impossible to attribute.
3. **Deploy and let it settle.** Wait for enough traffic that the percentiles are stable, not the
   first few requests after a deploy when caches are cold.
4. **Compare the same panels.** Did total elapsed time fall? Did total wait fall, or simply move
   to a different minion?
5. **Keep it or revert it,** then repeat.

The common surprise is a change that reduces one minion's wait while total elapsed time stays
flat, because the wait moved to whichever minion is now the slowest. That is still useful
information: it tells you that you have found the real floor, and that the next improvement has
to come from the critical path rather than from rearranging what is around it.

## Step 7: Split a minion that sets the floor

When one minion is consistently the slowest, splitting it is usually the next move:

~~~ruby
# Before: one minion, setting a 1,800 ms floor
inventory_minion = ParallelMinion::Minion.new(regions, description: "Inventory") do |regions|
  regions.map { |region| InventorySupplier.check(region) }
end

# After: one minion per region, running side by side
inventory_minions = regions.map do |region|
  ParallelMinion::Minion.new(region, description: "Inventory #{region}", metric: "inventory/check") do |r|
    InventorySupplier.check(r)
  end
end

inventory = inventory_minions.map(&:result)
~~~

Each region now runs beside the others, so the group takes as long as the slowest region rather
than the sum of all of them.

Note that all of the split minions share one metric name here. That is often what you want: the
percentiles then describe the regional lookup as an operation, rather than producing a separate
panel per region.

Two limits worth knowing before splitting aggressively:

* **Every minion is a real thread**, and each one calling the database needs its own connection
  from the pool. Splitting one minion into ten can exhaust a pool sized for a single connection
  per request. Size the pool for the concurrency you actually create.
* **Splitting only helps work that waits.** Splitting a CPU-bound block into four minions on
  CRuby produces four minions contending for the same GVL and no improvement at all.

## Step 8: Prove the benefit

Minions can be turned off globally, which makes a direct comparison possible:

~~~ruby
ParallelMinion::Minion.enabled = false
~~~

Every minion then runs inline in the calling thread, in the order it was created, as though the
minions were never there. Nothing else changes: results, exceptions, and log entries all behave
the same.

Run one production server with minions disabled and compare its latency against the rest. That
gives a real measurement of what minions are buying, on real traffic, rather than a benchmark.

It is also the first thing to try when something is behaving strangely in production and you are
not sure whether concurrency is involved. If the problem persists with minions disabled, it was
never a concurrency problem.

## How far this goes

Tuned this way, some production request types ended up running as many as 40 minions to service a
single inbound request. Coordinating that by hand would not be practical, which is precisely why
Parallel Minion generates these metrics automatically: every minion is measured identically, and
the dashboard shows which one is setting the floor.

The result on one large Rails application was a latency reduction of over 30%, arrived at by
repeating the loop in Step 6 rather than by any single change.
