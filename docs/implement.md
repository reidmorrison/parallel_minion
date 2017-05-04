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
