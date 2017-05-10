#$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

require 'minitest/autorun'
require 'parallel_minion'
require 'semantic_logger'

SemanticLogger.default_level = :trace
SemanticLogger.add_appender(file_name: 'test.log', formatter: :color)

# Setup global callback for metric so that it can be tested below
$log_structs = []
SemanticLogger.on_metric do |log_struct|
  $log_structs << log_struct.dup
end
