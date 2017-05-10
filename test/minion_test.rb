require_relative './test_helper'

# Test ParallelMinion standalone without Rails
# Run this test standalone to verify it has no Rails dependencies
class MinionTest < Minitest::Test
  include SemanticLogger::Loggable

  describe ParallelMinion::Minion do

    [false, true].each do |enabled|
      describe enabled ? 'enabled' : 'disabled' do
        before do
          ParallelMinion::Minion.enabled = enabled
          $log_structs                   = []
        end

        it 'without parameters' do
          minion = ParallelMinion::Minion.new { 196 }
          assert_equal 196, minion.result
        end

        it 'with a description' do
          minion = ParallelMinion::Minion.new(description: 'Test') { 197 }
          assert_equal 197, minion.result
        end

        it 'with an argument' do
          p1     = {name: 198}
          minion = ParallelMinion::Minion.new(p1, description: 'Test') do |v|
            v[:name]
          end
          assert_equal 198, minion.result
        end

        it 'raise exception' do
          minion = ParallelMinion::Minion.new(description: 'Test') { raise "An exception" }
          assert_raises RuntimeError do
            minion.result
          end
        end

        it 'has correct logger name' do
          minion = ParallelMinion::Minion.new { 196 }
          name   = enabled ? 'Minion' : 'Inline'
          assert_equal name, minion.logger.name
        end

        # TODO Blocks still have access to their original scope if variables cannot be
        #      resolved first by the parameters, then by the values in Minion itself
        #        it 'not have access to local variables' do
        #          name = 'Jack'
        #          minion = ParallelMinion::Minion.new(description: 'Test') { puts name }
        #          assert_raises NameError do
        #            minion.result
        #          end
        #        end

        it 'run minion' do
          hash   = {value: 23}
          value  = 47
          minion = ParallelMinion::Minion.new(hash, description: 'Test') do |h|
            value     = 321
            h[:value] = 123
            456
          end
          assert_equal 456, minion.result
          assert_equal 123, hash[:value]
          assert_equal 321, value
        end

        it 'copy across logging tags' do
          minion = nil
          SemanticLogger.tagged('TAG') do
            assert_equal 'TAG', SemanticLogger.tags.last
            minion = ParallelMinion::Minion.new(description: 'Tag Test') do
              logger.info "Tag Test"
              logger.tags.last
            end
          end
          assert_equal 'TAG', minion.result
        end

        it 'copy across named tags' do
          minion = nil
          SemanticLogger.named_tagged(tag: 'TAG') do
            assert_equal({tag: 'TAG'}, SemanticLogger.named_tags)
            minion = ParallelMinion::Minion.new(description: 'Named Tags Test') do
              logger.info "Named Tags Test"
              SemanticLogger.named_tags
            end
          end
          assert_equal({tag: 'TAG'}, minion.result)
        end

        it 'copy across tags & named tags' do
          minion = nil
          SemanticLogger.tagged('TAG') do
            SemanticLogger.named_tagged(tag: 'TAG') do
              assert_equal({tag: 'TAG'}, SemanticLogger.named_tags)
              assert_equal 'TAG', SemanticLogger.tags.last
              minion = ParallelMinion::Minion.new(description: 'Tags Test') do
                logger.info "Tags Test"
                [SemanticLogger.named_tags, SemanticLogger.tags.last]
              end
            end
          end

          assert_equal({tag: 'TAG'}, minion.result.first)
          assert_equal 'TAG', minion.result.last
        end

        it 'include metric' do
          metric_name = 'model/method'
          hash        = {value: 23}
          value       = 47
          minion      = ParallelMinion::Minion.new(hash, description: 'Test', metric: metric_name) do |h|
            value     = 321
            h[:value] = 123
            sleep 1
            456
          end
          assert_equal 456, minion.result
          assert_equal 123, hash[:value]
          assert_equal 321, value
          SemanticLogger.flush
          assert log = $log_structs.first, -> { $log_structs.ai }
          if enabled
            # Completed log message
            assert_equal metric_name, log.metric, -> { $log_structs.ai }
            # Wait log message
            assert log = $log_structs.last, -> { $log_structs.ai }
            assert_equal "#{metric_name}/wait", log.metric, -> { $log_structs.ai }
          else
            # Timeout and wait has no effect when run inline
            assert_equal metric_name, log.metric, -> { $log_structs.ai }
          end
        end

        it 'handle multiple minions concurrently' do
          # Start 10 minions
          minions = 10.times.collect do |i|
            # Each Minion returns its index in the collection
            ParallelMinion::Minion.new(i, description: "Minion:#{i}") { |counter| counter }
          end
          assert_equal 10, minions.count
          # Fetch the result from each Minion
          minions.each_with_index do |minion, index|
            assert_equal index, minion.result
          end
        end

        it 'timeout' do
          if enabled
            minion = ParallelMinion::Minion.new(description: 'Test', timeout: 100) { sleep 1 }
            assert_nil minion.result
          end
        end

        it 'timeout and terminate thread with Exception' do
          if enabled
            minion = ParallelMinion::Minion.new(description: 'Test', timeout: 100, on_timeout: Timeout::Error) { sleep 1 }
            assert_nil minion.result
            # Give time for thread to terminate
            sleep 0.1
            assert_equal Timeout::Error, minion.exception.class
            assert_equal false, minion.working?
            assert_equal true, minion.completed?
            assert_equal true, minion.failed?
            assert_equal 0, minion.time_left
          end
        end

        it 'make description instance variable available' do
          minion = ParallelMinion::Minion.new(description: 'Test') do
            description
          end
          assert_equal 'Test', minion.result
        end

        it 'make timeout instance variable available' do
          minion = ParallelMinion::Minion.new(description: 'Test', timeout: 1000) do
            timeout
          end
          assert_equal 1000, minion.result
        end

        it 'make enabled? method available' do
          minion = ParallelMinion::Minion.new(description: 'Test') do
            enabled?
          end
          assert_equal enabled, minion.result
        end

        it 'keep the original arguments' do
          minion = ParallelMinion::Minion.new(1, 'data', 14.1, description: 'Test') do |num, str, float|
            num + float
          end
          assert_equal 15.1, minion.result
          assert_equal [1, 'data', 14.1], minion.arguments
        end
      end

    end

  end
end
