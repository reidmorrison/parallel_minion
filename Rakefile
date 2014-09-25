require 'rake/clean'
require 'rake/testtask'

$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require 'parallel_minion/version'

task :gem do
  system "gem build parallel_minion.gemspec"
end

task :publish => :gem do
  system "git tag -a v#{ParallelMinion::VERSION} -m 'Tagging #{ParallelMinion::VERSION}'"
  system "git push --tags"
  system "gem push parallel_minion-#{ParallelMinion::VERSION}.gem"
  system "rm parallel_minion-#{ParallelMinion::VERSION}.gem"
end

desc "Run Test Suite"
task :test do
  Rake::TestTask.new(:functional) do |t|
    t.test_files = FileList['test/*_test.rb']
    t.verbose    = true
  end

  Rake::Task['functional'].invoke
end

task :default => :test
