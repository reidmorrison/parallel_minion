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

    # Give an infinite amount of time to wait for a Minion to complete a task
    INFINITE = -1

    # Sets whether to run in Synchronous mode
    #
    # By Setting synchronous to true all Minions that have not yet been started
    # will run in the thread from which they are started and not in their own
    # threads
    #
    # This is useful:
    # - to run tests under the Capybara gem
    # - when debugging code so that all code is run sequentially in the current thread
    #
    # Note: Do not set this setting to true in Production
    def self.synchronous=(synchronous)
      @@synchronous = synchronous
    end

    # Returns whether running in Synchronous mode
    def self.synchronous?
      @@synchronous
    end

    # The list of classes for which the current scope must be copied into the
    # new Minion (Thread)
    #
    # Example:
    #   ...
    def self.scoped_classes
      @@scoped_classes
    end

    # Create a new thread and
    #   Log the time for the thread to complete processing
    #   The exception without stack trace is logged whenever an exception is
    #   thrown in the thread
    #   Re-raises any unhandled exception in the calling thread when it call #result
    #   Copy the logging tags and specified ActiveRecord scopes to the new thread
    #
    # Parameters
    #   :description [String]
    #     Description for this task that the Minion is performing
    #     Put in the log file along with the time take to complete the task
    #
    #   :timeout [Integer]
    #     Maximum amount of time in milli-seconds that the task may take to complete
    #     before #result times out
    #     Set to Minion::INFINITE to give the thread an infinite amount of time to complete
    #     Default: Minion::INFINITE
    #
    #     Notes:
    #     - :timeout does not affect what happens to the Minion running the
    #       the task, it only affects how long #result will take to return.
    #     - The Minion will continue to run even after the timeout has been exceeded
    #     - If :synchronous is true, or ParallelMinion::Minion.synchronous is
    #       set to true, then :timeout is ignored and assumed to be Minion::INFINITE
    #       since the code is run in the calling thread when the Minion is created
    #
    #   :synchronous [Boolean]
    #     Whether the Minion should run in the current thread
    #     Not recommended in Production, but is useful for debugging purposes
    #     Default: false
    #
    #   *args
    #     Any number of arguments can be supplied that are passed into the block
    #     in the order they are listed
    #     It is recommended to duplicate and/or freeze objects passed as arguments
    #     so that they are not modified at the same time by multiple threads
    #
    #   Proc / lambda
    #     A block of code must be supplied that the Minion will execute
    #     NOTE: This block will be executed within the scope of the created minion
    #           instance and _not_ within the scope of where the Proc/lambda was
    #           originally created.
    #           This is done to force all parameters to be passed in explicitly
    #           and should be read-only or duplicates of the original data
    #
    # The overhead for moving the task to a Minion (separate thread) vs running it
    # sequentially is about 0.3 ms if performing other tasks in-between starting
    # the task and requesting its result.
    #
    # The following call adds 0.5 ms to total processing time vs running the
    # code in-line:
    #   ParallelMinion::Minion.new(description: 'Count', timeout: 5) { 1 }.result
    #
    # NOTE:
    #   On JRuby it is very important to add the following setting to .jrubyrc
    #       thread.pool.enabled=true
    #
    # Example:
    #   ParallelMinion::Minion.new(10.days.ago, description: 'Doing something else in parallel', timeout: 1000) do |date|
    #     MyTable.where('created_at <= ?', date).count
    #   end
    def initialize(*args, &block)
      raise "Missing mandatory block that Minion must perform" unless block
      @start_time = Time.now
      @exception = nil

      options = self.class.extract_options!(args).dup

      @timeout  = (options.delete(:timeout) || Minion::INFINITE).to_f
      @description   = (options.delete(:description) || 'Minion').to_s
      @log_exception = options.delete(:log_exception)
      @synchronous   = options.delete(:synchronous) || self.class.synchronous?

      # Warn about any unknown options.
      options.each_pair { |key,val| logger.warn "Ignoring unknown option: #{key.inspect} => #{val.inspect}" }

      # Run the supplied block of code in the current thread for testing or
      # debugging purposes
      if @synchronous == true
        begin
          logger.info("Started synchronously #{@description}")
          logger.benchmark_info("Completed synchronously #{@description}", log_exception: @log_exception) do
            @result = instance_exec(*args, &block)
          end
        rescue Exception => exc
          @exception = exc
        end
        return
      end

      tags = (logger.tags || []).dup

      # Copy current scopes for new thread. Only applicable for AR models
      scopes = self.class.current_scopes.dup if defined?(ActiveRecord::Base)

      @thread = Thread.new(*args) do
        # Copy logging tags from parent thread
        logger.tagged(*tags) do
          # Set the current thread name to the description for this Minion
          # so that all log entries in this thread use this thread name
          Thread.current.name = "#{@description}-#{Thread.current.object_id}"
          logger.info("Started #{@description}")

          begin
            logger.benchmark_info("Completed #{@description}", log_exception: @log_exception) do
              # Use the current scope for the duration of the task execution
              if scopes.nil? || (scopes.size == 0)
                @result = instance_exec(*args, &block)
              else
                # Each Class to scope requires passing a block to .scoping
                proc = Proc.new { instance_exec(*args, &block) }
                first = scopes.shift
                scopes.each {|scope| proc = Proc.new { scope.scoping(&proc) } }
                @result = first.scoping(&proc)
              end
            end
          rescue Exception => exc
            @exception = exc
            nil
          ensure
            # Return any database connections used by this thread back to the pool
            ActiveRecord::Base.clear_active_connections! if defined?(ActiveRecord::Base)
          end
        end
      end
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
        return if @thread.join(ms.nil? ? nil: ms / 1000).nil?
      end

      # Return the exception, if any, otherwise the task result
      exception.nil? ? @result : Kernel.raise(exception)
    end

    # Returns [Boolean] whether the minion is still working on the assigned task
    def working?
      synchronous? ? false : @thread.alive?
    end

    # Returns [Boolean] whether the minion has completed working on the task
    def completed?
      synchronous? ? true : @thread.stop?
    end

    # Returns [Boolean] whether the minion failed while performing the assigned task
    def failed?
      !exception.nil?
    end

    # Returns the amount of time left in milli-seconds that this Minion has to finish its task
    # Returns 0 if no time is left
    # Returns nil if their is no time limit. I.e. :timeout was set to Minion::INFINITE (infinite time left)
    def time_left
      return nil if @timeout == INFINITE
      duration = @timeout - (Time.now - @start_time) * 1000
      duration <= 0 ? 0 : duration
    end

    # Returns [Boolean] whether synchronous mode has been enabled for this minion instance
    def synchronous?
      @synchronous
    end

    # Returns the current scopes for each of the models for which scopes will be
    # copied to the Minions
    def self.current_scopes
      # Apparently #scoped is deprecated, but its replacement #all does not behave the same
      @@scoped_classes.collect {|klass| klass.scoped.dup}
    end

    protected

    @@synchronous = false
    @@scoped_classes = []

    # Extract options from a hash.
    def self.extract_options!(args)
      args.last.is_a?(Hash) ? args.pop : {}
    end

  end
end