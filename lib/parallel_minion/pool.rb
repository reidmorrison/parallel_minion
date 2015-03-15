module ParallelMinion
  # Create a pool for minions to swim in!
  class Pool
    # Returns [Fixnum] maximum number of Minions this pool can have
    attr_reader :maximum

    # Returns [Array<Object>] list of Minions
    attr_reader :pool

    # Returns [Array<Object>] results from each Minion
    attr_reader :results

    # Parameters
    #   :maximum [Fixnum]
    #     The maximum number of minions your pool can hold
    # NOTE:
    #     PLease see parameters for ParallelMinion::Minion#initalize
    #     They should be passed to the ParallelMinion::Pool#initalize
    #     Each minion in the pool will receive these options.
    def initialize(*args)
      @arguments = args.dup
      options    = ParallelMinion::Minion.extract_options!(@arguments)
      @maximum   = options.delete(:maximum)
      fail 'Missing required maximum minions' if @maximum.nil?
      @pool    = Queue.new
      @results = []
    end

    # Returns [Fixnum] current number of minions in the pool
    def count
      pool.length
    end

    # Parameters
    #   :&block
    #     The block for the minion worker to execute
    # Creates a new minion and adds it to the pool
    def worker(&block)
      fail 'Missing mandatory block that Minion Pool must perform' unless block

      # If the current pool count is greather than or equal to our maximum
      # minions allowed wait for the lifeguard to pull a minion from the pool
      if count >= maximum
        lifeguard
        worker(&block)
      else
        pool << ParallelMinion::Minion.new(*@arguments, &block)
      end
    end

    # Returns the results from the pool
    # Wait for all threads in the pool to return a result
    # Drain the pool into the results
    def drain
      results << lifeguard while count > 0
    end

    # Remove from the front of the queue. First in first out.
    # Append the minions result into results.
    # Return the minions result
    def lifeguard
      (results << pool.shift.result).last if count > 0
    end
  end
end
