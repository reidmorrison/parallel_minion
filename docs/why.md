---
layout: default
---

## Why Parallel Minion?

We recently re-wrote a Golang service in Ruby. The service worked well, but we had
no one to support it since our Golang engineers left to run Golang conferences.

The first iteration in Ruby used a single thread and was about twice as slow
as the Go service. The Go service was creating upwards of 30 go-routines to perform
concurrent database calls, and then perform subsequent calculations with all the results.

The go service made extensive use of channels and go routines. Since our application
runs on JRuby it made sense to keep this concurrency.

Several concurrency frameworks were considered:

- [Celluloid](http://celluloid.io)
- [Agent](https://github.com/igrigorik/agent)
- [Qwirk](https://github.com/bpardee/qwirk)
- [jruby-go](https://gist.github.com/michaelfairley/4140714)

All of the above approaches did not meet our requirement for a pragmatic solution
to simple concurrency.

For significantly more complex scenarios where Software Engineers are intimately
familiar with concurrency and it's challenges the above frameworks do offer a viable solution.

To meet the pragmatic requirement we built a thin layer on top of the Thread class,
called Parallel Minion. JRuby already has extensive support for thread pooling,
so we did not have to write our own.

In practice we have found that minions can be used by just about any Rails developer.

Parallel Minion allows you to take existing blocks of code and wrap them in a minion
so that they can run asynchronously in a separate thread. The minion then passes
back the result to the caller when or if requested. If any exceptions were
thrown during the minion processing, it will be re-raised in the callers thread
so that no additional work needs to be done when converting existing code to use minions.

```ruby
minion = ParallelMinion::Minion.new(10.days.ago, description: 'Doing something else in parallel', timeout: 1000) do |date|
  MyTable.where('created_at <= ?', date).count
end

# Do other work here...

# Retrieve the result of the minion
count = minion.result

puts "Found #{count} records"
```

After changing the Ruby replacement to use minions to break out many different
code blocks to run concurrently from a single method, it ended up running faster
than the equivalent Go service. We are not sure why it ran faster other than by
using Parallel Minion it gave us greater visibility through its built-in logging to
make re-organizing blocks of code for greatest efficiency very straight forward.

The processing time is significantly reduced since the various blocks within the code
can be run at the same time. No understanding of channels, go-routines,
inter-thread communication, or even threads is required to use minions.

To ensure that the minions work seamlessly in Rails applications Parallel Minion
also performs the following transparently:

- any logging tags defined in the current thread are passed onto the minion's thread
- Active Record scopes are copied to the new thread, to ensure that dynamic scoping
  within Rails is honored by minions.
- minion processing times are logged to help with refining which blocks to run in
  which order, or even to break blocks up into multiple blocks each in their own minion.
- if the main thread has to wait for one or more minions to complete the name of the
  minion and the wait time are logged.
- the name of the minion is assigned to its thread name so that any log entries
  written during the execution of the minion are immediately identifiable as coming
  from that minion.
- returns Active Record database connections to it's connection pool when the
  minion is done with the connection.

Something that is very important to us is the ability to timeout waiting for a minion
to complete. If for example a minion is responsible for communicating with an
external vendor, those calls can sometimes take too long, so we want the application
to be able to continue with a sub-set of the information available rather than fail
entirely. When the minion eventually completes it can still save any information
returned even though it may not be used by the current call. As a result the minion
is not killed or stopped when we timeout waiting for it, although it could be killed
if required.

Parallel Minion does not enforce "pass-by-copy" for all data passed to a minion
so it is possible to have two threads operate on the same data. It is therefore
highly recommended to copy all data passed to minions, or freezing them so that
minions do not have the ability to write to the same objects at the same time.

In this way locking is removed, and converting existing code to minions is very easy.

Parallel Minion runs on both Ruby and JRuby, allowing for development using Ruby
and then testing and deploying on JRuby for greatest performance and concurrency.

We are now using minions in several key processing intensive parts of our production
application and have already seen a 30% reduction in processing time.
Over time we expect further reductions as we adopt minions throughout our extensive code-base.

The key with minions is that they make it very simple to introduce concurrency
without re-writing existing code, or having to train Ruby developers on complex
concurrency frameworks. The level of risk with implementing minions is very low
because it returns existing return values and exceptions from blocks of code.

For an in-depth example of how minions can reduce latency: [Example](example.html)
