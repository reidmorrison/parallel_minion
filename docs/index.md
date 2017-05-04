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

- Rails 4.0, 4.1 users need to apply a patch in order to fix a performance
problem in the Active Record connection pooling logic. Include
the following [Code](https://gist.github.com/reidmorrison/e5e6b0bf01d6837624d4)
before Rails starts. A good place is in application.rb

### Dependencies

Parallel Minion uses Semantic Logger due to it's high concurrency logging capabilities
and built-in benchmarking api's

- `semantic_logger`

### Compatibility

ParallelMinion works with Ruby 1.9, Ruby 2.0, Ruby 2.1, JRuby 1.7
