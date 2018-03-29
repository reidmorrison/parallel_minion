# Parallel Minion
[![Build Status](https://secure.travis-ci.org/reidmorrison/parallel_minion.png?branch=master)](http://travis-ci.org/reidmorrison/parallel_minion)
[![Gem Version](https://img.shields.io/gem/v/parallel_minion.svg)](https://rubygems.org/gems/parallel_minion) [![Build Status](https://travis-ci.org/reidmorrison/parallel_minion.svg?branch=master)](https://travis-ci.org/reidmorrison/parallel_minion) [![Downloads](https://img.shields.io/gem/dt/parallel_minion.svg)](https://rubygems.org/gems/parallel_minion) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg)

Wrap Ruby code with a minion so that it is run on a parallel thread.

## Description

Parallel Minion allows you to take existing blocks of code and wrap them in a minion
so that they can run asynchronously in a separate thread.
The minion then passes back the result to the caller when or if requested.
If any exceptions were thrown during the minion processing, it will be re-raised
in the callers thread so that no additional work needs to be done when converting
existing code to use minions.

## Example

```ruby
minion = ParallelMinion::Minion.new(
  10.days.ago,
  description: 'Doing something else in parallel',
  timeout:     1000
) do |date|
  MyTable.where('created_at <= ?', date).count
end

# Do other work here...

# Retrieve the result of the minion
count = minion.result

puts "Found #{count} records"
```

## Documentation

For complete documentation see: http://reidmorrison.github.io/parallel_minion

## Production Use

Parallel Minion is being used in a high performance, highly concurrent
production environment running JRuby with Ruby on Rails on a Puma web server.
Significant reduction in the time it takes to complete rails request processing
has been achieved by moving existing blocks of code into Minions.

## Installation

    gem install parallel_minion

## Meta

* Code: `git clone git://github.com/reidmorrison/parallel_minion.git`
* Home: <https://github.com/reidmorrison/parallel_minion>
* Bugs: <http://github.com/reidmorrison/parallel_minion/issues>
* Gems: <http://rubygems.org/gems/parallel_minion>

This project uses [Semantic Versioning](http://semver.org/).

## Author

[Reid Morrison](https://github.com/reidmorrison) :: @reidmorrison

## License

Copyright 2013, 2014, 2015, 2016, 2017 Reid Morrison

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
