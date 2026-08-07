require_relative "test_helper"
require "active_support"
require "active_support/executor"
require "active_support/current_attributes"

# Must be a named constant, ActiveSupport::CurrentAttributes keys its instances by class name
class ExecutorTestCurrent < ActiveSupport::CurrentAttributes
  attribute :tenant
end

# Exercises the Rails executor integration without loading Rails, by supplying an executor
# directly. Under Rails the railtie assigns Rails.application.executor to the same setting.
class MinionExecutorTest < Minitest::Test
  describe ParallelMinion::Minion do
    # Anonymous is fine here, ActiveSupport::ExecutionWrapper keys itself by object_id
    let(:executor) { Class.new(ActiveSupport::Executor) }

    before do
      ParallelMinion::Minion.enabled = true
    end

    after do
      ParallelMinion::Minion.executor         = nil
      ParallelMinion::Minion.context_handlers = []
      ExecutorTestCurrent.reset
    end

    def drain(queue)
      Array.new(queue.size) { queue.pop }
    end

    it "run the minion inside the executor" do
      events = Queue.new
      executor.to_run { events << :run }
      executor.to_complete { events << :complete }
      ParallelMinion::Minion.executor = executor

      minion = ParallelMinion::Minion.new(description: "Test") do
        events << :task
        42
      end

      assert_equal 42, minion.result
      assert_equal %i[run task complete], drain(events)
    end

    it "complete the executor when the minion raises" do
      events = Queue.new
      executor.to_complete { events << :complete }
      ParallelMinion::Minion.executor = executor

      minion = ParallelMinion::Minion.new(description: "Test") { raise "An exception" }

      assert_raises RuntimeError do
        minion.result
      end
      assert_equal %i[complete], drain(events)
    end

    it "use the executor configured when the minion was created, not a later one" do
      events = Queue.new
      executor.to_complete { events << :complete }

      # A new thread does not necessarily reach the body of the minion before `Minion.new`
      # returns. Reading the executor setting in there rather than in the calling thread
      # swept a minion created without an executor into one configured moments later.
      minion = ParallelMinion::Minion.new(description: "Test") { 42 }
      ParallelMinion::Minion.executor = executor

      assert_equal 42, minion.result
      assert_empty drain(events)
    end

    it "apply context handlers inside the executor" do
      # Rails resets CurrentAttributes from both executor hooks, so a handler applied
      # outside the executor would have its value wiped before the task ever saw it.
      executor.to_run { ExecutorTestCurrent.reset }
      executor.to_complete { ExecutorTestCurrent.reset }
      ParallelMinion::Minion.executor = executor

      ParallelMinion::Minion.register_context(
        capture: -> { ExecutorTestCurrent.attributes },
        around:  ->(attributes, &block) { ExecutorTestCurrent.set(**attributes, &block) }
      )
      ExecutorTestCurrent.tenant = "acme"

      minion = ParallelMinion::Minion.new(description: "Test") { ExecutorTestCurrent.tenant }

      assert_equal "acme", minion.result
    end

    it "run without an executor when none is configured" do
      assert_nil ParallelMinion::Minion.executor

      minion = ParallelMinion::Minion.new(description: "Test") { 42 }

      assert_equal 42, minion.result
    end

    it "not wrap an inline minion, whose thread already has the caller's context" do
      events = Queue.new
      executor.to_run { events << :run }
      ParallelMinion::Minion.executor = executor

      minion = ParallelMinion::Minion.new(description: "Test", enabled: false) { 42 }

      assert_equal 42, minion.result
      assert_empty drain(events)
    end

    it "permit concurrent loads while waiting for the minion" do
      ParallelMinion::Minion.executor = executor
      permitted = false
      permit    = lambda do |&block|
        permitted = true
        block.call
      end

      ActiveSupport::Dependencies.interlock.stub(:permit_concurrent_loads, permit) do
        ParallelMinion::Minion.new(description: "Test") { sleep 0.1 }.result
      end

      assert permitted, "Expected #result to wait inside interlock.permit_concurrent_loads"
    end
  end
end
