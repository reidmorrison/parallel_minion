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

    # Sets whether minions are enabled to run in their own threads
    #
    # By Setting _enabled_ to false all Minions that have not yet been started
    # will run in the thread from which it is created and not on its own thread
    #
    # This is useful:
    # - to run tests under the Capybara gem
    # - when debugging code so that all code is run sequentially in the current thread
    #
    # Note: Not recommended to set this setting to false in Production
    def self.enabled=(enabled)
      @@enabled = enabled
    end

    # Returns whether minions are enabled to run in their own threads
    def self.enabled?
      @@enabled
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
    #     - If :enabled is false, or ParallelMinion::Minion.enabled is false,
    #       then :timeout is ignored and assumed to be Minion::INFINITE
    #       since the code is run in the calling thread when the Minion is created
    #
    #   :enabled [Boolean]
    #     Whether the minion should run in a separate thread
    #     Not recommended in Production, but is useful for debugging purposes
    #     Default: ParallelMinion::Minion.enabled?
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

      @timeout       = (options.delete(:timeout) || Minion::INFINITE).to_f
      @description   = (options.delete(:description) || 'Minion').to_s
      @log_exception = options.delete(:log_exception)
      @enabled       = options.delete(:enabled)
      @enabled       = self.class.enabled? if @enabled.nil?

      # Warn about any unknown options.
      options.each_pair do |key,val|
        logger.warn "Ignoring unknown option: #{key.inspect} => #{val.inspect}"
        warn "ParallelMinion::Minion Ignoring unknown option: #{key.inspect} => #{val.inspect}"
      end

      # Run the supplied block of code in the current thread for testing or
      # debugging purposes
      if @enabled == false
        begin
          logger.info("Started in the current thread: #{@description}")
          logger.benchmark_info("Completed in the current thread: #{@description}", log_exception: @log_exception) do
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
      return nil if @timeout == INFINITE
      duration = @timeout - (Time.now - @start_time) * 1000
      duration <= 0 ? 0 : duration
    end

    # Returns [Boolean] whether this minion is enabled to run in a separate thread
    def enabled?
      @enabled
    end

    # Returns the current scopes for each of the models for which scopes will be
    # copied to the Minions
    def self.current_scopes
      # Apparently #scoped is deprecated, but its replacement #all does not behave the same
      @@scoped_classes.collect {|klass| klass.scoped.dup}
    end

    protected

    @@enabled = true
    @@scoped_classes = []

    # Extract options from a hash.
    def self.extract_options!(args)
      args.last.is_a?(Hash) ? args.pop : {}
    end

  end
end