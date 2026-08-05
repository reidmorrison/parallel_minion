---
layout: default
---

## Implementation Approach

Before implementing minions to parallelize existing code the following information
needs to be gathered

1. Identify how long existing parts of the code are taking to run.

2. Determine dependencies between the blocks of code. For example, which blocks
of code must be completed before the current block can be run.

### Measuring duration

To measure the time it takes to complete blocks of code Semantic Logger has a great
API for just this purpose. It measures how long the block takes to run and then logs
it to your log file.

If running rails, add the `rails_semantic_logger` gem to your Gemfile, then:

```ruby
Rails.logger.benchmark_info('Counting rows') do
   MyTable.where('created_at <= ?', date).count
end
```

If not running Rails, then install the `semantic_logger` gem, then:

```ruby
require 'semantic_logger'

# Set the global default log level
SemanticLogger.default_level = :trace

# Log to a file, and use the colorized formatter
SemanticLogger.add_appender('development.log', &SemanticLogger::Appender::Base.colorized_formatter)

# Create an instance of a logger
# Add the application/class name to every log message
logger = SemanticLogger['MyClass']

logger.benchmark_info('Counting rows') do
   # Put code here that is being measured to determine if it should be parallelized
end
```

### Tuning with metrics

Measuring duration tells you which blocks are worth moving into a minion. Metrics tell you
whether the split you chose was the right one.

Supply the `:metric` option and Parallel Minion forwards the execution time of every minion
to Semantic Logger as a named metric:

```ruby
ParallelMinion::Minion.new(
  address,
  description: 'Cleanse address',
  metric:      'inquiry/address_cleansing'
) do |address|
  AddressCleanser.call(address)
end
```

Two metrics come out of the call above:

- `inquiry/address_cleansing` is how long the minion itself took.
- `inquiry/address_cleansing/wait` is how long the calling thread was blocked in `#result`
  waiting for that minion to finish.

The second metric is the one that drives tuning. A wait is only recorded when the minion is
still running at the moment its result is requested, so a well balanced request records
little or no wait time at all.

### Running experiments

In production these metrics were forwarded to Splunk and rendered on dashboards, which turned
every change in how work was divided among minions into an experiment with a measurable result
rather than a guess.

The objective is to have all of the minions complete at about the same time. That balances two
opposing failure modes:

- A minion that finishes early has consumed a thread without buying any latency. It could have
  been given more work, or the work could have stayed on the calling thread.
- A minion that finishes late holds up everything else. It shows up as a large `/wait` on the
  metric for that minion, and is a candidate for being split into several smaller minions.

So the target is to drive the total `/wait` time toward zero while handing off as much work as
possible into concurrent threads. Neither number is useful alone. Wait time on its own can
always be reduced by doing less work in parallel.

Tuned this way, some products ended up launching as many as 40 minions to service a single
inbound request. Coordinating that by hand is not practical, which is the reason Parallel Minion
generates these metrics automatically. Every minion is measured the same way, with no
instrumentation code beyond naming the metric.
