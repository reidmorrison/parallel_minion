$LOAD_PATH.push File.expand_path("lib", __dir__)

# Maintain your gem's version:
require "parallel_minion/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name                  = "parallel_minion"
  spec.version               = ParallelMinion::VERSION
  spec.platform              = Gem::Platform::RUBY
  spec.authors               = ["Reid Morrison"]
  spec.homepage              = "https://github.com/reidmorrison/parallel_minion"
  spec.summary               = "Run slow steps at the same time and cut request latency, for Ruby and Rails"
  spec.files                 = Dir["lib/**/*", "LICENSE.txt", "Rakefile", "README.md"]
  spec.license               = "Apache License V2.0"
  spec.required_ruby_version = ">= 3.2"
  spec.add_dependency "semantic_logger", ">= 5.0"
  spec.metadata["rubygems_mfa_required"] = "true"
end
