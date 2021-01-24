require "semantic_logger"

module ParallelMinion
  autoload :Minion, "parallel_minion/minion"
end

require "parallel_minion/railtie" if defined?(Rails)
