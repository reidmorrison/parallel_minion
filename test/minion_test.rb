# Allow test to be run in-place without requiring a gem install
$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

require 'test/unit'
require 'shoulda'
require 'parallel_minion'

# Register an appender if one is not already registered
SemanticLogger.default_level = :trace
SemanticLogger.add_appender('test.log', &SemanticLogger::Appender::Base.colorized_formatter) if SemanticLogger.appenders.size == 0

# Setup global callback for metric so that it can be tested below
SemanticLogger.on_metric do |log_struct|
  $log_struct = log_struct.dup
end

# Test ParallelMinion standalone without Rails
# Run this test standalone to verify it has no Rails dependencies
class MinionTest < Test::Unit::TestCase
  include SemanticLogger::Loggable

  context ParallelMinion::Minion do

    [false, true].each do |enabled|
      context ".new with enabled: #{enabled.inspect}" do
        setup do
          ParallelMinion::Minion.enabled = enabled
          $log_struct = nil
        end

        should 'without parameters' do
          minion = ParallelMinion::Minion.new { 196 }
          assert_equal 196, minion.result
        end

        should 'with a description' do
          minion = ParallelMinion::Minion.new(description: 'Test') { 197 }
          assert_equal 197, minion.result
        end

        should 'with an argument' do
          p1 = { name: 198 }
          minion = ParallelMinion::Minion.new(p1, description: 'Test') do |v|
            v[:name]
          end
          assert_equal 198, minion.result
        end

        should 'raise exception' do
          minion = ParallelMinion::Minion.new(description: 'Test') { raise "An exception" }
          assert_raise RuntimeError do
            minion.result
          end
        end

        # TODO Blocks still have access to their original scope if variables cannot be
        #      resolved first by the parameters, then by the values in Minion itself
        #        should 'not have access to local variables' do
        #          name = 'Jack'
        #          minion = ParallelMinion::Minion.new(description: 'Test') { puts name }
        #          assert_raise NameError do
        #            minion.result
        #          end
        #        end

        should 'run minion' do
          hash = { value: 23 }
          value = 47
          minion = ParallelMinion::Minion.new(hash, description: 'Test') do |h|
            value = 321
            h[:value] = 123
            456
          end
          assert_equal 456, minion.result
          assert_equal 123, hash[:value]
          assert_equal 321, value
        end

        should 'copy across logging tags' do
          minion = nil
          logger.tagged('TAG') do
            assert_equal 'TAG', logger.tags.last
            minion = ParallelMinion::Minion.new(description: 'Tag Test') do
              logger.tags.last
            end
          end
          assert_equal 'TAG', minion.result
        end

        should 'include metric' do
          metric_name = '/Custom/metric'
          hash = { value: 23 }
          value = 47
          minion = ParallelMinion::Minion.new(hash, description: 'Test', metric: metric_name) do |h|
            value = 321
            h[:value] = 123
            456
          end
          assert_equal 456, minion.result
          assert_equal 123, hash[:value]
          assert_equal 321, value
          SemanticLogger.flush
          assert_equal metric_name, $log_struct.metric
        end

        should 'handle multiple minions concurrently' do
          # Start 10 minions
          minions = 10.times.collect do |i|
            # Each Minion returns its index in the collection
            ParallelMinion::Minion.new(i, description: "Minion:#{i}") {|counter| counter }
          end
          assert_equal 10, minions.count
          # Fetch the result from each Minion
          minions.each_with_index do |minion, index|
            assert_equal index, minion.result
          end
        end

        should 'timeout' do
          minion = ParallelMinion::Minion.new(description: 'Test', timeout: 100) { sleep 1 }
          # Only Parallel Minions time-out when they exceed the timeout
          if enabled
            assert_equal nil, minion.result
          end
        end

        should 'make description instance variable available' do
          minion = ParallelMinion::Minion.new(description: 'Test') do
            description
          end
          assert_equal 'Test', minion.result
        end

        should 'make timeout instance variable available' do
          minion = ParallelMinion::Minion.new(description: 'Test', timeout: 1000 ) do
            timeout
          end
          assert_equal 1000, minion.result
        end

        should 'make enabled? method available' do
          minion = ParallelMinion::Minion.new(description: 'Test') do
            enabled?
          end
          assert_equal enabled, minion.result
        end

      end

    end

  end
end