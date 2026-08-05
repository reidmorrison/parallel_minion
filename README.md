# Parallel Minion
[![Gem Version](https://img.shields.io/gem/v/parallel_minion.svg)](https://rubygems.org/gems/parallel_minion) [![Build Status](https://github.com/reidmorrison/parallel_minion/workflows/build/badge.svg)](https://github.com/reidmorrison/parallel_minion/actions?query=workflow%3Abuild) [![Downloads](https://img.shields.io/gem/dt/parallel_minion.svg)](https://rubygems.org/gems/parallel_minion) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg)

Run slow steps at the same time and cut request latency. For Ruby and Rails.

## Description

Parallel Minion allows you to take existing blocks of code and wrap them in a minion
so that they can run asynchronously in a separate thread.
The minion then passes back the result to the caller when or if requested.
If any exceptions were thrown during the minion processing, it will be re-raised
in the callers thread so that no additional work needs to be done when converting
existing code to use minions.

## Example

```ruby
# Starts running immediately, on its own thread
minion = ParallelMinion::Minion.new(
  product_id,
  description: 'Inventory lookup',
  timeout:     1_000
) do |id|
  InventorySupplier.check(id)
end

# Do other work here, while the minion runs...

# Collect the result
inventory = minion.result
```

Because the two run at the same time, the elapsed time is that of the slower one rather than the
sum of both.

## Documentation

For complete documentation see: http://reidmorrison.github.io/parallel_minion

* [Guide](http://reidmorrison.github.io/parallel_minion/guide.html), a step by step introduction
* [Tuning](http://reidmorrison.github.io/parallel_minion/tuning.html), metrics and dashboards for
  dividing up the work
* [Rails](http://reidmorrison.github.io/parallel_minion/rails.html), executor, request context and
  ActiveRecord scopes
* [Reference](http://reidmorrison.github.io/parallel_minion/api.html), every option and method
* [Upgrading](http://reidmorrison.github.io/parallel_minion/upgrading.html), moving from v1 to v2

## When do minions help?

Minions help when code is **waiting on something**: a database query, an HTTP call, an external
service. CRuby releases the GVL while a thread waits on I/O, so those waits genuinely overlap.

Minions do not speed up pure Ruby computation on CRuby, since that holds the GVL. JRuby and
TruffleRuby have no GVL and do run such work in parallel.

## Production Use

Parallel Minion is used in high performance, highly concurrent production environments running
Ruby on Rails. Moving existing blocks of code into minions has produced significant reductions in
request processing time, over 30% on one large application.

## Installation

    gem install parallel_minion

## Compatibility

Ruby 3.2 or greater, tested against Ruby 3.2, 3.3, 3.4 and 4.0.

Rails is optional. When present, Rails 7.2, 8.0 and 8.1 are tested.

## Meta

* Code: `git clone git://github.com/reidmorrison/parallel_minion.git`
* Home: <https://github.com/reidmorrison/parallel_minion>
* Bugs: <http://github.com/reidmorrison/parallel_minion/issues>
* Gems: <https://rubygems.org/gems/parallel_minion>

This project uses [Semantic Versioning](http://semver.org/).

## Author

[Reid Morrison](https://github.com/reidmorrison) :: @reidmorrison

## License

Copyright 2013-2026 Reid Morrison

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
