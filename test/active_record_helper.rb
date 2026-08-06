require_relative "test_helper"
require "active_record"
require "erb"

# Shared by the tests that need a database. Kept out of test_helper.rb so that minion_test.rb
# continues to run without ActiveRecord, proving the gem stands alone.
ActiveRecord::Base.logger         = SemanticLogger[ActiveRecord]
ActiveRecord::Base.configurations = YAML.safe_load(ERB.new(File.read("test/config/database.yml")).result)
ActiveRecord::Base.establish_connection(:test)
