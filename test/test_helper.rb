require "minitest/autorun"
require "amazing_print"
require "semantic_logger"
require "parallel_minion"

SemanticLogger.default_level = :trace
SemanticLogger.add_appender(file_name: "test.log", formatter: :color)
