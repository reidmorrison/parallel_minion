parallel_minion
===============

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

## Documentation

For complete documentation see: http://reidmorrison.github.io/parallel_minion

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

License
-------

Copyright 2013, 2014 Reid Morrison

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
