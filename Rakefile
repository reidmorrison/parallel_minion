# Setup bundler to avoid having to run bundle exec all the time.
require 'rubygems'
require 'bundler/setup'

require 'rake/testtask'
require_relative 'lib/parallel_minion/version'

task :gem do
  system 'gem build parallel_minion.gemspec'
end

task :publish => :gem do
  system "git tag -a v#{ParallelMinion::VERSION} -m 'Tagging #{ParallelMinion::VERSION}'"
  system 'git push --tags'
  system "gem push parallel_minion-#{ParallelMinion::VERSION}.gem"
  system "rm parallel_minion-#{ParallelMinion::VERSION}.gem"
end

Rake::TestTask.new(:test) do |t|
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
  t.warning = false
end

# By default run tests against all appraisals
if !ENV["APPRAISAL_INITIALIZED"] && !ENV["TRAVIS"]
  require 'appraisal'
  task default: :appraisal
else
  task default: :test
end
