require 'thread'
require 'semantic_logger'

module ParallelMinion
  autoload :Minion,  'parallel_minion/minion'
  autoload :Pool,    'parallel_minion/pool'
end

require 'parallel_minion/railtie' if defined?(Rails)
