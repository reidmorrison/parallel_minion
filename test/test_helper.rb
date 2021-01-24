# $LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

require "minitest/autorun"
require "parallel_minion"
require "semantic_logger"
require "amazing_print"

SemanticLogger.default_level = :trace
SemanticLogger.add_appender(file_name: "test.log", formatter: :color)
