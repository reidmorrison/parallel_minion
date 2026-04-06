require_relative "test_helper"
require "active_record"

# Rails 5.2 + JRuby 10 (Ruby 3.4): ActiveModel::Type::Integer uses `def initialize(*); super`
# and does not forward `limit:` to Value#initialize. register_class_with_limit then calls
# Integer.new(limit: n) and schema/column load raises ArgumentError. Fixed in Rails 6+.
# DDL workarounds still hit this path as soon as AR loads column metadata.
if defined?(JRUBY_VERSION) && ActiveRecord::VERSION::MAJOR < 6
  class MinionScopeTest < Minitest::Test
    def test_skip_scope_tests_on_rails5_jruby
      skip "Rails 5.x on JRuby 10: ActiveRecord 5.2 is incompatible with Ruby 3.4 keyword args in ActiveModel::Type::Integer"
    end
  end
else
  require "erb"

  ActiveRecord::Base.logger         = SemanticLogger[ActiveRecord]
  ActiveRecord::Base.configurations = YAML.safe_load(ERB.new(File.read("test/config/database.yml")).result)
  ActiveRecord::Base.establish_connection(:test)

  ActiveRecord::Schema.define version: 0 do
    connection.create_table :people, force: true do |t|
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
end
