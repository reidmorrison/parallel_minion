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

    attr_reader :on_timeout, :log_exception, :start_time

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
    def self.enabled=(enabled)
      @enabled = enabled
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
    def self.scoped_classes
      @scoped_classes
    end

    def self.scoped_classes=(scoped_classes)
      @scoped_classes = scoped_classes.dup
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

    def self.started_log_level
      @started_log_level
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

    def self.completed_log_level
      @completed_log_level
    end

    self.started_log_level   = :info
    self.completed_log_level = :info
    self.enabled             = true
    self.scoped_classes      = []
    logger.name              = 'Minion'

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
    #   ParallelMinion::Minion.new(10.days.ago, description: 'Doing something else in parallel', timeout: 1000) do |date|
    #     MyTable.where('created_at <= ?', date).count
    #   end
    def initialize(*arguments, description: 'Minion', metric: nil, log_exception: nil, enabled: self.class.enabled?, timeout: INFINITE, on_timeout: nil, wait_metric: nil, &block)
      raise 'Missing mandatory block that Minion must perform' unless block
      @start_time    = Time.now
      @exception     = nil
      @arguments     = arguments
      @timeout       = timeout.to_f
      @description   = description.to_s
      @metric        = metric
      @log_exception = log_exception
      @enabled       = enabled
      @on_timeout    = on_timeout

      @wait_metric   = (wait_metric || "#{metric}/wait") if @metric

      # When minion is disabled it is obvious in the logs since the name will now be 'Inline' instead of 'Minion'
      self.logger    = SemanticLogger['Inline'] unless @enabled

      @enabled ? run(&block) : run_inline(&block)
    end

    # Returns the result when the thread completes
    # Returns nil if the thread has not yet completed
    # Raises any unhandled exception in the thread, if any
    #
    # Note: The result of any thread cannot be nil
    def result
      # Return nil if Minion is still working and has time left to finish
      if working?
        ms = time_left
        logger.measure(self.class.completed_log_level, "Waited for Minion to complete: #{description}", min_duration: 0.01, metric: wait_metric) do
          if @thread.join(ms.nil? ? nil : ms / 1000).nil?
            @thread.raise(@on_timeout.new("Minion: #{description} timed out")) if @on_timeout
            logger.warn("Timed out waiting for: #{description}")
            return
          end
        end
      end

      # Return the exception, if any, otherwise the task result
      exception.nil? ? @result : Kernel.raise(exception)
    end

    # Returns [Boolean] whether the minion is still working on the assigned task
    def working?
      enabled? ? @thread.alive? : false
    end

    # Returns [Boolean] whether the minion has completed working on the task
    def completed?
      enabled? ? @thread.stop? : true
    end

    # Returns [Boolean] whether the minion failed while performing the assigned task
    def failed?
      !exception.nil?
    end

    # Returns the amount of time left in milli-seconds that this Minion has to finish its task
    # Returns 0 if no time is left
    # Returns nil if their is no time limit. I.e. :timeout was set to Minion::INFINITE (infinite time left)
    def time_left
      return nil if (timeout == 0) || (timeout == -1)
      duration = timeout - (Time.now - start_time) * 1000
      duration <= 0 ? 0 : duration
    end

    # Returns [Boolean] whether this minion is enabled to run in a separate thread
    def enabled?
      @enabled
    end

    # Returns the current scopes for each of the models for which scopes will be
    # copied to the Minions
    if defined?(ActiveRecord)
      if ActiveRecord::VERSION::MAJOR >= 4
        def self.current_scopes
          scoped_classes.collect { |klass| klass.all }
        end
      else
        def self.current_scopes
          scoped_classes.collect { |klass| klass.scoped }
        end
      end
    end

    private

    # Run the supplied block of code in the current thread.
    # Useful for debugging, testing, and when running in batch environments.
    def run_inline(&block)
      begin
        logger.public_send(self.class.started_log_level, "Started #{@description}")
        logger.measure(self.class.completed_log_level, "Completed #{@description}", log_exception: @log_exception, metric: metric) do
          @result = instance_exec(*arguments, &block)
        end
      rescue Exception => exc
        @exception = exc
      ensure
        @duration = Time.now - start_time
      end
    end

    def run(&block)
      # Capture tags from current thread
      tags = SemanticLogger.tags
      tags = tags.nil? || tags.empty? ? nil : tags.dup

      named_tags = SemanticLogger.named_tags
      named_tags = named_tags.nil? || named_tags.empty? ? nil : named_tags.dup

      # Captures scopes from current thread. Only applicable for AR models
      scopes     = self.class.current_scopes if defined?(ActiveRecord::Base)

      @thread = Thread.new(*arguments) do
        Thread.current.name = "#{description}-#{Thread.current.object_id}"

        # Copy logging tags from parent thread, if any
        proc                = Proc.new { run_in_scope(scopes, &block) }
        proc2               = tags ? Proc.new { SemanticLogger.tagged(*tags, &proc) } : proc
        proc3               = named_tags ? Proc.new { SemanticLogger.named_tagged(named_tags, &proc2) } : proc2

        logger.public_send(self.class.started_log_level, "Started #{description}")
        begin
          logger.measure(self.class.completed_log_level, "Completed #{description}", log_exception: log_exception, metric: metric, &proc3)
        rescue Exception => exc
          @exception = exc
          nil
        ensure
          @duration = Time.now - start_time
          # Return any database connections used by this thread back to the pool
          ActiveRecord::Base.clear_active_connections! if defined?(ActiveRecord::Base)
        end
      end
    end

    def run_in_scope(scopes, &block)
      if scopes.nil? || scopes.empty?
        @result = instance_exec(*@arguments, &block)
      else
        # Use the captured scope when running the block.
        # Each Class to scope requires passing a block to .scoping.
        proc  = Proc.new { instance_exec(*@arguments, &block) }
        first = scopes.shift
        scopes.each { |scope| proc = Proc.new { scope.scoping(&proc) } }
        @result = first.scoping(&proc)
      end
    end

  end
end
