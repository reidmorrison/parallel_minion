# Instruct a Minion to perform a specific task in a separate thread
module ParallelMinion
  class Minion
    include SemanticLogger::Loggable

    # Returns [String] the description supplied on the initializer
    attr_reader :description

    # Returns [Exception] the exception that was raised otherwise nil
    attr_reader :exception

    # Returns [Integer] the maximum duration in milli-seconds that the Minion may take to complete the task
    attr_reader :timeout

    # Returns [Array<Object>] list of arguments in the order they were passed into the initializer
    attr_reader :arguments

    # Returns [Float] the number of milli-seconds the the minion took to complete
    # Returns nil if the minion is still running
    attr_reader :duration

    # Metrics [String]
    attr_reader :metric, :wait_metric

    attr_reader :on_timeout, :log_exception, :start_time, :on_exception_level

    # Returns [Boolean] whether the last call to #result gave up waiting for the minion.
    #
    # Distinguishes a nil returned by #result because the minion timed out from a nil that
    # the minion itself returned. Cleared when a subsequent #result does not time out.
    attr_reader :timed_out

    alias timed_out? timed_out

    # Give an infinite amount of time to wait for a Minion to complete a task
    INFINITE = 0

    # Sets whether Minions should run in a separate thread.
    #
    # By Setting _enabled_ to false all Minions that have not yet been created
    # will run in the thread in which it is created.
    # - Development:
    #    Use a debugger, since the code will run in the current thread.
    # - Test:
    #     Keep test execution in the current thread.
    #     Supports rolling back database changes after each test, since all changes are
    #     performed on the same database connection.
    # - Production:
    #     Batch processing in Rocket Job where throughput is more important than latency.
    #       http://rocketjob.io
    class << self
      attr_writer :enabled
    end

    # Returns whether minions are enabled to run in their own threads
    def self.enabled?
      @enabled
    end

    # The list of classes for which the current scope must be copied into the
    # new Minion (Thread)
    #
    # Example:
    #   ...
    class << self
      attr_reader :scoped_classes
    end

    def self.scoped_classes=(scoped_classes)
      @scoped_classes = scoped_classes.dup
    end

    # The registered application context handlers.
    #
    # Returns [Array<Array(Proc, Proc)>] the capture and around proc for each handler
    class << self
      attr_reader :context_handlers
    end

    def self.context_handlers=(context_handlers)
      @context_handlers = context_handlers.dup.freeze
    end

    # Carry application context that lives in thread local state into every Minion.
    #
    # A Minion runs in a new thread, which starts with empty thread local state. Anything
    # held there is therefore missing inside the Minion: `ActiveSupport::CurrentAttributes`,
    # `ActsAsTenant.current_tenant`, `RequestStore`, and any `Thread.current[...]` the
    # application sets. Whatever reads that state inside the Minion sees nothing.
    #
    # This is not only a correctness problem. Scoping that is conditional on such state
    # fails *open* when the state is missing. A multi-tenancy library that applies its
    # tenant scope only when a current tenant is set applies no scope at all inside a
    # Minion, so a query that is tenant scoped in the calling thread returns every tenant's
    # rows in the Minion. Register a handler for any context that scoping depends on.
    #
    # Parameters
    #   :capture [Proc]
    #     Called in the thread creating the Minion, before it starts. Returns the value to
    #     carry across, which is passed to `around`.
    #
    #   :around [Proc]
    #     Called in the Minion with the captured value, and *must* yield. The Minion's task
    #     runs in the supplied block, so re-establish the context around the yield.
    #
    # Handlers run in the order they were registered, with the first registered outermost,
    # and run on both the threaded and the inline path so that both behave identically.
    #
    # An exception raised by `capture` propagates out of `Minion.new` in the calling thread,
    # since a broken handler is a configuration error and must not be reported as a task
    # failure. An `around` that never yields raises, rather than quietly returning nil.
    #
    # Example: acts_as_tenant
    #   ParallelMinion::Minion.register_context(
    #     capture: -> { ActsAsTenant.current_tenant },
    #     around:  ->(tenant, &block) { ActsAsTenant.with_tenant(tenant, &block) }
    #   )
    #
    # Example: Rails Current attributes
    #   ParallelMinion::Minion.register_context(
    #     capture: -> { Current.attributes },
    #     around:  ->(attributes, &block) { Current.set(**attributes, &block) }
    #   )
    def self.register_context(capture:, around:)
      @context_handlers += [[capture, around].freeze]
    end

    # Change the log level for the Started log message.
    #
    # Default: :info
    #
    # Valid levels:
    #   :trace, :debug, :info, :warn, :error, :fatal
    def self.started_log_level=(level)
      raise(ArgumentError, "Invalid log level: #{level}") unless SemanticLogger::LEVELS.include?(level)

      @started_log_level = level
    end

    class << self
      attr_reader :started_log_level
    end

    # Change the log level for the Completed log message.
    #
    # Default: :info
    #
    # Valid levels:
    #   :trace, :debug, :info, :warn, :error, :fatal
    def self.completed_log_level=(level)
      raise(ArgumentError, "Invalid log level: #{level}") unless SemanticLogger::LEVELS.include?(level)

      @completed_log_level = level
    end

    class << self
      attr_reader :completed_log_level
    end

    self.started_log_level   = :info
    self.completed_log_level = :info
    self.enabled             = true
    self.scoped_classes      = []
    self.context_handlers    = []

    # Create a new Minion
    #
    #   Creates a new thread and logs the time for the supplied block to complete processing.
    #   The exception without stack trace is logged whenever an exception is thrown in the thread.
    #
    #   Re-raises any unhandled exception in the calling thread when `#result` is called.
    #   Copies the logging tags and specified ActiveRecord scopes to the new thread.
    #
    # Parameters
    #   *arguments
    #     Any number of arguments can be supplied that are passed into the block
    #     in the order they are listed.
    #
    #     Note:
    #       All arguments must be supplied by copy and not by reference.
    #       For example, use `#dup` to create copies of passed data.
    #       Pass by copy is critical to prevent concurrency issues when multiple threads
    #       attempt to update the same object at the same time.
    #
    #   Proc / lambda
    #     A block of code must be supplied that the Minion will execute.
    #
    #     Note:
    #       This block will be executed within the scope of the created minion instance
    #       and _not_ within the scope of where the Proc/lambda was originally created.
    #       This is done to force all parameters to be passed in explicitly
    #       and should be read-only or duplicates of the original data.
    #
    #   :description [String]
    #     Description for this task that the Minion is performing.
    #     Written to the log file along with the time take to complete the task.
    #
    #   :timeout [Integer]
    #     Maximum amount of time in milli-seconds that the task may take to complete
    #     before #result times out.
    #     Set to 0 to give the thread an infinite amount of time to complete.
    #     Default: 0 ( Wait forever )
    #
    #     Notes:
    #     - :timeout does not affect what happens to the Minion running the
    #       the task, it only affects how long #result will take to return.
    #     - The Minion will continue to run even after the timeout has been exceeded
    #     - If :enabled is false, or ParallelMinion::Minion.enabled is false,
    #       then :timeout is ignored and assumed to be Minion::INFINITE
    #       since the code is run in the calling thread when the Minion is created
    #     - On timeout #result returns nil, which is indistinguishable from a minion that
    #       returned nil. Use #timed_out? to tell them apart, or set :on_timeout.
    #       Code that treats the nil as an answer fails open, so a minion computing a
    #       security or risk decision must check one of the two.
    #
    #   :on_timeout [Exception]
    #     The class to raise on the minion when the minion times out.
    #     By raising the exception on the running thread it ensures that the thread
    #     ends due to the exception, rather than continuing to execute.
    #     The exception is only raised on the running minion when #result is called.
    #     The current call to #result will complete with a result of nil, future
    #     calls to #result will raise the supplied exception on the current thread
    #     since the thread will have terminated with that exception.
    #
    #     Note: :on_timeout has no effect if not #enabled?
    #
    #   :metric [String]
    #     Name of the metric to forward to Semantic Logger when measuring the minion execution time.
    #     Example: inquiry/address_cleansing
    #
    #     When a metric is supplied the following metrics will also be generated:
    #     - wait
    #         Duration waiting for a minion to complete.
    #
    #     The additional metrics are added to the supplied metric name. For example:
    #     - inquiry/address_cleansing/wait
    #
    #   :log_exception [Symbol]
    #     Control whether or how an exception thrown in the block is
    #     reported by Semantic Logger. Values:
    #      :full
    #        Log the exception class, message, and backtrace
    #      :partial
    #        Log the exception class and message. The backtrace will not be logged
    #      :off
    #        Any unhandled exception raised in the block will not be logged
    #      Default: :partial
    #
    #   :on_exception_level [:trace | :debug | :info | :warn | :error | :fatal]
    #     Override the log level only when an exception occurs.
    #     Default: ParallelMinion::Minion.completed_log_level
    #
    #   :enabled [Boolean]
    #     Override the global setting: `ParallelMinion::Minion.enabled?` for this minion instance.
    #
    # The overhead for moving the task to a Minion (separate thread) vs running it
    # sequentially is about 0.3 ms if performing other tasks in-between starting
    # the task and requesting its result.
    #
    # The following call adds 0.5 ms to total processing time vs running the
    # code in-line:
    #   ParallelMinion::Minion.new(description: 'Count', timeout: 5) { 1 }.result
    #
    # Note:
    #   On JRuby it is recommended to add the following setting to .jrubyrc
    #     thread.pool.enabled=true
    #
    # Example:
    #   ParallelMinion::Minion.new(
    #     10.days.ago,
    #     description: 'Doing something else in parallel',
    #     timeout:     1000
    #   ) do |date|
    #     MyTable.where('created_at <= ?', date).count
    #   end
    #
    # Example, when the result is being ignored, log full exception as an error:
    #   ParallelMinion::Minion.new(
    #     customer,
    #     description:        "We don't care about the result",
    #     log_exception:      :full,
    #     on_exception_level: :error
    #   ) do |customer|
    #     customer.save!
    #   end
    def initialize(*arguments,
                   description: "Minion",
                   metric: nil,
                   log_exception: nil,
                   on_exception_level: self.class.completed_log_level,
                   enabled: self.class.enabled?,
                   timeout: INFINITE,
                   on_timeout: nil,
                   wait_metric: nil,
                   &block)
      raise "Missing mandatory block that Minion must perform" unless block

      @start_time         = Time.now
      @exception          = nil
      @timed_out          = false
      @arguments          = arguments
      @timeout            = timeout.to_f
      @description        = description.to_s
      @metric             = metric
      @log_exception      = log_exception
      @on_exception_level = on_exception_level
      @enabled            = enabled
      @on_timeout         = on_timeout

      @wait_metric        = wait_metric || "#{metric}/wait" if @metric

      # When minion is disabled make it obvious in the logs by setting the name to 'Inline' instead of 'Minion'.
      unless @enabled
        l           = self.class.logger.dup
        l.name      = "Inline"
        self.logger = l
      end

      # Captured here rather than in `run` so that it always happens in the calling thread,
      # on both paths, and so a handler that raises does so from `Minion.new`.
      contexts = capture_contexts

      @enabled ? run(contexts, &block) : run_inline(contexts, &block)
    end

    # Returns the result when the thread completes
    # Returns nil if the thread has not yet completed
    # Raises any unhandled exception in the thread, if any
    #
    # Note:
    #   A nil result is ambiguous on its own, since it is also what a minion that has not
    #   completed within :timeout returns. Check `#timed_out?` to tell the two apart.
    #   Treating a timed out nil as an answer fails open when the minion is computing a
    #   security decision, so check `#timed_out?` or set :on_timeout for that work.
    def result
      # Return nil if Minion is still working and has time left to finish
      if working?
        ms = time_left
        logger.measure(
          self.class.completed_log_level,
          "Waited for Minion to complete: #{description}",
          min_duration: 0.01,
          metric:       wait_metric
        ) do
          if @thread.join(ms.nil? ? nil : ms / 1000).nil?
            @timed_out = true
            @thread.raise(@on_timeout.new("Minion: #{description} timed out")) if @on_timeout
            logger.warn("Timed out waiting for: #{description}")
            return
          end
        end
      elsif enabled?
        # The minion has already terminated, but the join is still required since it is the
        # only thing that publishes `@result` and `@exception` to this thread. Without it,
        # Ruby implementations with a relaxed memory model (JRuby, TruffleRuby) can read
        # stale values here, silently dropping an exception raised inside the minion.
        # Joining an already dead thread returns immediately.
        @thread.join
      end

      @timed_out = false

      # Return the exception, if any, otherwise the task result
      exception.nil? ? @result : Kernel.raise(exception)
    end

    # Returns [Boolean] whether the minion is still working on the assigned task
    def working?
      enabled? ? @thread.alive? : false
    end

    # Returns [Boolean] whether the minion has completed working on the task
    #
    # Note: Do not use `Thread#stop?` here. It returns true when the thread is dead _or_
    #       sleeping, so a minion blocked on I/O, a mutex, or a database call would be
    #       reported as completed while it is still running.
    def completed?
      enabled? ? !@thread.alive? : true
    end

    # Returns [Boolean] whether the minion failed while performing the assigned task
    def failed?
      !exception.nil?
    end

    # Returns the amount of time left in milli-seconds that this Minion has to finish its task
    # Returns 0 if no time is left
    # Returns nil if their is no time limit. I.e. :timeout was set to Minion::INFINITE (infinite time left)
    def time_left
      return nil if timeout.zero? || (timeout == -1)

      duration = timeout - ((Time.now - start_time) * 1000)
      [duration, 0].max
    end

    # Returns [Boolean] whether this minion is enabled to run in a separate thread
    def enabled?
      @enabled
    end

    # Returns the current scopes for each of the models for which scopes will be
    # copied to the Minions
    if defined?(ActiveRecord)
      def self.current_scopes
        scoped_classes.collect(&:all)
      end
    end

    private

    # rubocop:disable Lint/RescueException

    # Run the supplied block of code in the current thread.
    # Useful for debugging, testing, and when running in batch environments.
    def run_inline(contexts, &block)
      logger.public_send(self.class.started_log_level, "Started #{description}")
      logger.measure(
        self.class.completed_log_level,
        "Completed #{description}",
        log_exception:      log_exception,
        on_exception_level: on_exception_level,
        metric:             metric
      ) do
        # The context is already correct in this thread, but the handlers still run so that
        # both paths behave identically and a broken handler shows up in either.
        run_in_context(contexts) { @result = instance_exec(*arguments, &block) }
      end
    rescue Exception => e
      @exception = e
    ensure
      @duration = Time.now - start_time
    end

    # rubocop:enable Lint/RescueException

    def run(contexts, &block)
      # Capture tags from current thread
      tags       = capture_tags
      named_tags = capture_named_tags

      # Captures scopes from current thread. Only applicable for AR models
      scopes     = self.class.current_scopes if defined?(ActiveRecord::Base)

      @thread = Thread.new(*arguments) do
        Thread.current.name = "#{description}-#{Thread.current.object_id}"

        # Copy logging tags from parent thread, if any
        SemanticLogger.tagged(*tags) do
          SemanticLogger.named_tagged(named_tags) do
            logger.public_send(self.class.started_log_level, "Started #{description}")
            # rubocop:disable Lint/RescueException
            begin
              proc = proc { run_in_context(contexts) { run_in_scope(scopes, &block) } }
              logger.measure(
                self.class.completed_log_level,
                "Completed #{description}",
                log_exception:      log_exception,
                on_exception_level: on_exception_level,
                metric:             metric,
                &proc
              )
            rescue Exception => e
              @exception = e
              nil
            ensure
              cleanup
            end
            # rubocop:enable Lint/RescueException
          end
        end
      end
    end

    # rubocop:disable Lint/RescueException

    # Release the resources held by the minion thread once its task has ended.
    #
    # Runs with asynchronous interrupts masked. `:on_timeout` terminates a minion with
    # `Thread#raise`, which fires at the next interrupt checkpoint, and an unguarded `ensure`
    # is itself a valid checkpoint. An interrupt landing here would abort cleanup partway,
    # returning an ActiveRecord connection to the pool while its transaction is still open,
    # for the next request that checks it out to inherit.
    def cleanup
      Thread.handle_interrupt(Exception => :never) do
        @duration = Time.now - start_time
        # Return any database connections used by this thread back to the pool
        ActiveRecord::Base.connection_handler.clear_active_connections! if defined?(ActiveRecord::Base)
      end
    rescue Exception => e
      # A masked interrupt is delivered once the mask ends, and cleanup can fail on its own.
      # Either way record it as the minion's exception rather than letting it escape the
      # thread unreported, without clobbering an exception raised by the block itself.
      @exception ||= e
    end

    # rubocop:enable Lint/RescueException

    # Capture the registered application context in the thread creating the Minion.
    def capture_contexts
      self.class.context_handlers.map { |capture, around| [around, capture.call] }
    end

    # Re-establish the captured application context inside the Minion.
    #
    # Each `around` handler wraps a single block, so they are nested one inside the next,
    # the same way `run_in_scope` nests `.scoping`. The first registered ends up outermost.
    def run_in_context(contexts, &block)
      return block.call if contexts.empty?

      reached = false
      inner   = lambda do
        reached = true
        block.call
      end

      contexts.reverse_each do |around, value|
        outer = inner
        inner = -> { around.call(value) { outer.call } }
      end
      result = inner.call

      # A handler that forgets to yield would otherwise leave the task silently unrun, with
      # #result returning nil as though the block had produced it.
      raise("A ParallelMinion::Minion context handler did not yield, #{description} never ran") unless reached

      result
    end

    def capture_tags
      tags = SemanticLogger.tags
      tags.nil? || tags.empty? ? nil : tags.dup
    end

    def capture_named_tags
      named_tags = SemanticLogger.named_tags
      named_tags.nil? || named_tags.empty? ? nil : named_tags.dup
    end

    def run_in_scope(scopes, &block)
      if scopes.nil? || scopes.empty?
        @result = instance_exec(*@arguments, &block)
      else
        # Use the captured scope when running the block.
        # Each Class to scope requires passing a block to .scoping.
        proc  = proc { instance_exec(*@arguments, &block) }
        first = scopes.shift
        scopes.each { |scope| proc = proc { scope.scoping(&proc) } }
        @result = first.scoping(&proc)
      end
    end
  end
end
