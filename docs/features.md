---
layout: default
---

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
  the minion to make it easy to distinguish any log entries written in the minion

Rails Support

- When used in a Rails environment the current scope of specified Active Record
  models can be propagated to the minions thread
- Returns any used database connections to their relevant pools when the minion
  completes
