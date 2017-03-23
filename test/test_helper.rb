$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

require 'minitest/autorun'
require 'minitest/reporters'
require 'parallel_minion'
require 'semantic_logger'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

SemanticLogger.default_level = :trace
SemanticLogger.add_appender(file_name: 'test.log', formatter: :color)

# Setup global callback for metric so that it can be tested below
SemanticLogger.on_metric do |log_struct|
  $log_struct = log_struct.dup
end
