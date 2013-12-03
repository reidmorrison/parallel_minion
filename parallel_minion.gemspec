$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require 'parallel_minion/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name        = 'parallel_minion'
  spec.version     = ParallelMinion::VERSION
  spec.platform    = Gem::Platform::RUBY
  spec.authors     = ['Reid Morrison']
  spec.email       = ['reidmo@gmail.com']
  spec.homepage    = 'https://github.com/ClarityServices/semantic_logger'
  spec.summary     = "Concurrent processing made easy with Minions (Threads)"
  spec.description = "Parallel Minion supports easily handing work off to Minions (Threads) so that tasks that would normally be performed sequentially can easily be executed in parallel"
  spec.files       = Dir["lib/**/*", "LICENSE.txt", "Rakefile", "README.md"]
  spec.test_files  = Dir["test/**/*"]
  spec.license     = "Apache License V2.0"
  spec.has_rdoc    = true
  spec.add_dependency 'semantic_logger'
end
