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
