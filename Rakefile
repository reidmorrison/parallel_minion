# Setup bundler to avoid having to run bundle exec all the time.
require "rubygems"
require "bundler/setup"

require "rake/testtask"
require "rubocop/rake_task"
require_relative "lib/parallel_minion/version"

desc "Build the gem"
task :gem do
  system "gem build parallel_minion.gemspec"
end

desc "Tag, push, and publish the gem"
task publish: :gem do
  system "git tag -a v#{ParallelMinion::VERSION} -m 'Tagging #{ParallelMinion::VERSION}'"
  system "git push --tags"
  system "gem push parallel_minion-#{ParallelMinion::VERSION}.gem"
  system "rm parallel_minion-#{ParallelMinion::VERSION}.gem"
end

Rake::TestTask.new(:test) do |t|
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
  t.warning = false
end

RuboCop::RakeTask.new(:rubocop)

# By default run tests against all appraisals, plus rubocop once at the top level
# rubocop:disable Rake/DuplicateTask -- only one branch is ever loaded, so this is not a real duplicate
if !ENV["APPRAISAL_INITIALIZED"] && !ENV["TRAVIS"]
  require "appraisal"
  task default: %i[appraisal rubocop]
else
  task default: :test
end
# rubocop:enable Rake/DuplicateTask
