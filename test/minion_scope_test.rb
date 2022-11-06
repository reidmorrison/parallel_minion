require_relative "test_helper"
require "erb"
require "active_record"

ActiveRecord::Base.logger         = SemanticLogger[ActiveRecord]
ActiveRecord::Base.configurations = YAML.safe_load(ERB.new(File.read("test/config/database.yml")).result)
ActiveRecord::Base.establish_connection(:test)

ActiveRecord::Schema.define version: 0 do
  create_table :people, force: true do |t|
    t.string :name
    t.string :state
    t.string :zip_code
  end
end

class Person < ActiveRecord::Base
end

class MinionScopeTest < Minitest::Test
  describe ParallelMinion::Minion do
    [false, true].each do |enabled|
      describe ".new with enabled: #{enabled.inspect}" do
        before do
          Person.create(name: "Jack", state: "FL", zip_code: 38_729)
          Person.create(name: "John", state: "FL", zip_code: 35_363)
          Person.create(name: "Jill", state: "FL", zip_code: 73_534)
          Person.create(name: "Joe", state: "NY", zip_code: 45_325)
          Person.create(name: "Jane", state: "NY", zip_code: 45_325)
          Person.create(name: "James", state: "CA", zip_code: 123_123)
          # Instruct Minions to adhere to any dynamic scopes for Person model
          ParallelMinion::Minion.scoped_classes << Person
          ParallelMinion::Minion.enabled = enabled
        end

        after do
          Person.destroy_all
          ParallelMinion::Minion.scoped_classes.clear
          SemanticLogger.flush
        end

        it "copy across model scope" do
          assert_equal 6, Person.count

          Person.unscoped.where(state: "FL").scoping { Person.count }

          Person.unscoped.where(state: "FL").scoping do
            assert_equal 3, Person.count
            minion = ParallelMinion::Minion.new(description: "Scope Test", log_exception: :full) do
              Person.count
            end
            assert_equal 3, minion.result
          end
        end
      end
    end
  end
end
