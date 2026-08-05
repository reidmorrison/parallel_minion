lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

# Maintain your gem's version:
require "parallel_minion/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name                  = "parallel_minion"
  spec.version               = ParallelMinion::VERSION
  spec.platform              = Gem::Platform::RUBY
  spec.authors               = ["Reid Morrison"]
  spec.homepage              = "https://minion.rocketjob.io"
  spec.summary               = "Run slow steps at the same time and cut request latency, for Ruby & Rails."
  spec.description           = "Parallel Minion cuts request latency by running slow steps at the " \
                               "same time. Wrap a block in a minion and collect its result later, " \
                               "with exceptions re-raised in the calling thread and timeouts that " \
                               "return a partial answer instead of hanging."
  spec.files                 = Dir["lib/**/*", "docs/*.md", "LICENSE.txt", "Rakefile", "README.md"]
  spec.license               = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2"
  spec.add_dependency "semantic_logger", "~> 5.0"
  spec.metadata = {
    "bug_tracker_uri"       => "https://github.com/reidmorrison/parallel_minion/issues",
    "changelog_uri"         => "https://github.com/reidmorrison/parallel_minion/blob/main/CHANGELOG.md",
    "documentation_uri"     => "https://minion.rocketjob.io",
    "source_code_uri"       => "https://github.com/reidmorrison/parallel_minion/tree/v#{ParallelMinion::VERSION}",
    "rubygems_mfa_required" => "true"
  }
end
