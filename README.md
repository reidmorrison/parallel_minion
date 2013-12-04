parallel_minion
===============

Parallel Minion supports easily handing work off to minions (threads) so that tasks
that would normally be performed sequentially can easily be executed in parallel.
This allows Ruby and Rails applications to very easily do many tasks at the same
time so that results are returned more quickly.

Our use-case for minions is where an application grew to a point where it would
be useful to run some of the steps in fulfilling a single request in parallel.

## Features:

Exceptions

- Any exceptions raised in minions are captured and propagated back to the
  calling thread when #result is called
- Makes exception handling simple with a drop-in replacement for existing code
- Avoids having to implement more complex actors and supervisors required
  by some concurrency frameworks

Timeouts

- Timeout when a minion does not return within a specified time
- Timeouts are a useful feature when one of the minions fails to respond in a
  reasonable amount of time. For example when a call to a remote service hangs
  we can send back a partial response of other work that was completed rather
  than just "hanging" or failing completely.

Logging

- Built-in support to log the duration of all minion tasks to make future analysis
  of performance issues much easier
- Logs any exceptions thrown to assist with problem diagnosis
- Logging tags from the current thread are propagated to the minions thread
- The name of the thread in log entries is set to the description supplied for
  the minion to make it easy to distinguish log entries by minion / thread

Rails Support

- When used in a Rails environment the current scope of specified models can be
  propagated to the minions thread

## Example

Simple example

```ruby
minion = ParallelMinion::Minion.new(10.days.ago, description: 'Doing something else in parallel', timeout: 1000) do |date|
  MyTable.where('created_at <= ?', date).count
end

# Do other work here...

# Retrieve the result of the minion
count = minion.result

puts "Found #{count} records"
```

## Example

For example, in the code below there are several steps that are performed
sequentially and does not yet use minions:

```ruby
# Contrived example to show how to do parallel code execution
# with (unreal) sample durations in the comments

def process_request(request)
  # Count number of entries in a table.
  #   Average response time 150ms
  person_count = Person.where(state: 'FL').count

  # Count the number of requests for this user (usually more complex with were clauses etc.)
  #   Average response time 320ms
  request_count = Requests.where(user_id: request.user.id).count

  # Call an external provider
  #   Average response time 1800ms ( Sometimes "hangs" when supplier does not respond )
  inventory = inventory_supplier.check_inventory(request.product.id)

  # Call another provider for more info on the user
  #   Average response time 1500ms
  user_info = user_supplier.more_info(request.user.name)

  # Build up the reply
  reply = MyReply.new(user_id: request.user.id)

  reply.number_of_people   = person_count
  reply.number_of_requests = request_count
  reply.user_details       = user_info.details
  if inventory.product_available?
    reply.available        = true
    reply.quantity         = 100
  else
    reply.available = false
  end

  reply
end
```
The average response time when calling #process_request is around 3,780 milli-seconds.

The first step could be to run the supplier calls in parallel.
Through log analysis we have determined that the first supplier call takes on average
1,800 ms and we have decided that it should not wait longer than 2,200 ms for a response.

```ruby
# Now with a single parallel call

def process_request(request)
  # Count number of entries in a table.
  #   Average response time 150ms
  person_count = Person.where(state: 'FL').count

  # Count the number of requests for this user (usually more complex with were clauses etc.)
  #   Average response time 320ms
  request_count = Requests.where(user_id: request.user.id).count

  # Call an external provider
  #   Average response time 1800ms ( Sometimes "hangs" when supplier does not respond )
  inventory_minion = ParallelMinion::Minion.new(request.product.id, description: 'Inventory Lookup', timeout: 2200) do |product_id|
    inventory_supplier.check_inventory(product_id)
  end

  # Call another provider for more info on the user
  #   Average response time 1500ms
  user_info = user_supplier.more_info(request.user.name)

  # Build up the reply
  reply = MyReply.new(user_id: request.user.id)

  reply.number_of_people   = person_count
  reply.number_of_requests = request_count
  reply.user_details       = user_info.details

  # Get inventory result from Inventory Lookup minion
  inventory = inventory_minion.result

  if inventory.product_available?
    reply.available        = true
    reply.quantity         = 100
  else
    reply.available = false
  end

  reply
end
```

The above changes drop the average processing time from 3,780 milli-seconds to
2,280 milli-seconds.

By moving the supplier call to the top of the function call it can be optimized
to about 1,970 milli-seconds.

We can further parallelize the processing to gain even greater performance.

```ruby
# Now with two parallel calls

def process_request(request)
  # Call an external provider
  #   Average response time 1800ms ( Sometimes "hangs" when supplier does not respond )
  inventory_minion = ParallelMinion::Minion.new(request.product.id, description: 'Inventory Lookup', timeout: 2200) do |product_id|
    inventory_supplier.check_inventory(product_id)
  end

  # Count the number of requests for this user (usually more complex with were clauses etc.)
  #   Average response time 320ms
  request_count_minion = ParallelMinion::Minion.new(request.user.id, description: 'Request Count', timeout: 500) do |user_id|
    Requests.where(user_id: user_id).count
  end

  # Leave the current thread some work to do too

  # Count number of entries in a table.
  #   Average response time 150ms
  person_count = Person.where(state: 'FL').count

  # Call another provider for more info on the user
  #   Average response time 1500ms
  user_info = user_supplier.more_info(request.user.name)

  # Build up the reply
  reply = MyReply.new(user_id: request.user.id)

  reply.number_of_people   = person_count
  # The request_count is retrieved from the request_count_minion first since it
  # should complete before the inventory_minion
  reply.number_of_requests = request_count_minion.result
  reply.user_details       = user_info.details

  # Get inventory result from Inventory Lookup minion
  inventory = inventory_minion.result

  if inventory.product_available?
    reply.available        = true
    reply.quantity         = 100
  else
    reply.available = false
  end

  reply
end
```

The above #process_request method should now take on average 1,810 milli-seconds
which is significantly faster than the 3,780 milli-seconds it took to perform
the exact same request prior to using minions.

The exact breakdown of which calls to do in the main thread versus a minion is determined
through experience and trial and error over time. The key is logging the duration
of each call which minion does by default so that the exact processing breakdown
can be fine-tuned over time.

## Disabling Minions

In the event that strange problems are occurring in production and no one is
sure if it is due to running the minion tasks in parallel, it is simple to make
all minion tasks run in the calling thread.

It may also be useful to disable minions on a single production server to compare
its performance to that of the servers running with minions active.

To disable minions / make them run in the calling thread, add the following
lines to config/environments/production.rb:

```ruby
  # Make minions run immediately in the current thread
  config.parallel_minion.enabled = false
```

## Notes:

- When using JRuby it is important to enable it's built-in thread-pooling by
  adding the following line to .jrubyrc, or setting the appropriate command line option:

```ruby
thread.pool.enabled=true
```

Meta
----

* Code: `git clone git://github.com/reidmorrison/parallel_minion.git`
* Home: <https://github.com/reidmorrison/parallel_minion>
* Bugs: <http://github.com/reidmorrison/parallel_minion/issues>
* Gems: <http://rubygems.org/gems/parallel_minion>

This project uses [Semantic Versioning](http://semver.org/).

Author
-------

Reid Morrison :: reidmo@gmail.com :: @reidmorrison

Contributors
------------


License
-------

Copyright 2013 Reid Morrison

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
