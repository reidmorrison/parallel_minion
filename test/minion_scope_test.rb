# Allow test to be run in-place without requiring a gem install
$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

require 'semantic_logger'
# Register an appender if one is not already registered
SemanticLogger.default_level = :trace
SemanticLogger.add_appender('test.log', &SemanticLogger::Appender::Base.colorized_formatter) if SemanticLogger.appenders.size == 0

require 'rubygems'
require 'erb'
require 'test/unit'
# Since we want both the AR and Mongoid extensions loaded we need to require them first
require 'active_record'
require 'active_record/relation'
# Should redefines Proc#bind so must include after Rails
require 'shoulda'
require 'parallel_minion'

ActiveRecord::Base.logger = SemanticLogger[ActiveRecord]
ActiveRecord::Base.configurations = YAML::load(ERB.new(IO.read('test/config/database.yml')).result)
ActiveRecord::Base.establish_connection('test')

ActiveRecord::Schema.define :version => 0 do
  create_table :people, :force => true do |t|
    t.string :name
    t.string :state
    t.string :zip_code
  end
end

class Person < ActiveRecord::Base
end

class MinionScopeTest < Test::Unit::TestCase

  context ParallelMinion::Minion do
    [false, true].each do |enabled|
      context ".new with enabled: #{enabled.inspect}" do
        setup do
          Person.create(name: 'Jack', state: 'FL', zip_code: 38729)
          Person.create(name: 'John', state: 'FL', zip_code: 35363)
          Person.create(name: 'Jill', state: 'FL', zip_code: 73534)
          Person.create(name: 'Joe',  state: 'NY', zip_code: 45325)
          Person.create(name: 'Jane', state: 'NY', zip_code: 45325)
          Person.create(name: 'James', state: 'CA', zip_code: 123123)
          # Instruct Minions to adhere to any dynamic scopes for Person model
          ParallelMinion::Minion.scoped_classes << Person
          ParallelMinion::Minion.enabled = enabled
        end

        teardown do
          Person.destroy_all
          ParallelMinion::Minion.scoped_classes.clear
          SemanticLogger.flush
        end

        should 'copy across model scope' do
          assert_equal 6, Person.count

          Person.unscoped.where(state: 'FL').scoping { Person.count }

          Person.unscoped.where(state: 'FL').scoping do
            assert_equal 3, Person.count
            minion = ParallelMinion::Minion.new(description: 'Scope Test', log_exception: :full) do
              Person.count
            end
            assert_equal 3, minion.result
          end
        end

      end
    end
  end
end