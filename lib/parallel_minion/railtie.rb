module ParallelMinion # :nodoc:
  class Railtie < Rails::Railtie # :nodoc:
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
    #     # Change the log level for the started log messages to :debug,
    #     # so that they do not show up in production when log level is :info.
    #     config.parallel_minion.started_log_level = :debug
    #
    #     # Change the log level for the completed log messages to :debug,
    #     # so that they do not show up in production when log level is :info.
    #     config.parallel_minion.completed_log_level = :debug
    #
    #     # Add a model so that its current scope is copied to the Minion
    #     config.after_initialize do
    #       # Perform in an after_initialize so that the model has been loaded
    #       config.parallel_minion.scoped_classes << MyScopedModel
    #     end
    #   end
    config.parallel_minion = ::ParallelMinion::Minion

    # Run every Minion inside the application executor, so that the thread it runs in gets
    # the same reloading and ActiveRecord connection handling as the request cycle.
    #
    # Assigned here rather than at load time because the executor only exists once the
    # application has been built. Set `ParallelMinion::Minion.executor = nil` afterwards to
    # opt out.
    initializer "parallel_minion.executor" do |app|
      ::ParallelMinion::Minion.executor = app.executor
    end
  end
end
