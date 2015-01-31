$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

require 'minitest/autorun'
require 'minitest/reporters'
require 'minitest/stub_any_instance'
require 'shoulda/context'
require 'parallel_minion'
require 'semantic_logger'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

# Register an appender if one is not already registered
SemanticLogger.default_level = :trace
SemanticLogger.add_appender('test.log', &SemanticLogger::Appender::Base.colorized_formatter) if SemanticLogger.appenders.size == 0

# Setup global callback for metric so that it can be tested below
SemanticLogger.on_metric do |log_struct|
  $log_struct = log_struct.dup
end
