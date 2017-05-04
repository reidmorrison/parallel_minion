---
layout: default
---

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
