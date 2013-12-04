module ParallelMinion #:nodoc:
  class Railtie < Rails::Railtie #:nodoc:
    #
    # Make the ParallelMinion config available in the Rails application config
    #
    # Example: Make debugging easier
    #    in file config/environments/development.rb
    #
    #   Rails::Application.configure do
    #
    #     # Run Minions in the current thread to make debugging easier
    #     config.parallel_minion.enabled = false
    #
    #     # Add a model so that its current scope is copied to the Minion
    #     config.parallel_minion.scoped_classes << MyScopedModel
    #   end
    config.parallel_minion = ::ParallelMinion::Minion

  end
end
