# Setup bundler to avoid having to run bundle exec all the time.
require "bundler/setup"

require "rake/testtask"
require "rubocop/rake_task"
require_relative "lib/parallel_minion/version"

GEM_FILE = "parallel_minion-#{ParallelMinion::VERSION}.gem".freeze

# Page order for docs/llms-full.txt, matching the site nav in docs/_layouts/default.html.
LLMS_PAGES = %w[index guide tuning rails api upgrading].freeze

desc "Build the gem"
task :gem do
  sh "gem build parallel_minion.gemspec"
end

desc "Tag, push, and publish the gem"
task publish: :gem do
  sh "git tag -a v#{ParallelMinion::VERSION} -m 'Tagging #{ParallelMinion::VERSION}'"
  sh "git push --tags"
  sh "gem push #{GEM_FILE}"
  rm GEM_FILE
end

desc "Regenerate docs/llms-full.txt from the docs markdown pages"
task :llms_full do
  unlisted = Dir["docs/*.md"].map { |path| File.basename(path, ".md") } - LLMS_PAGES
  raise "Add #{unlisted.join(', ')} to LLMS_PAGES in the Rakefile" unless unlisted.empty?

  header = <<~HEADER
    # Parallel Minion - Complete Documentation

    > Parallel Minion runs a block of Ruby code on another thread and hands back its result when the
    > caller asks for it, so independent slow steps overlap instead of running one after another.

    This file concatenates every page of https://minion.rocketjob.io for consumption by AI assistants.
    It is generated from the markdown sources in docs/ by `bundle exec rake llms_full`; do not edit it directly.
    A per-page index is available at https://minion.rocketjob.io/llms.txt
  HEADER

  sections = LLMS_PAGES.map do |page|
    text = File.read("docs/#{page}.md").
           sub(/\A---\n.*?\n---\n/m, "").  # Jekyll front matter
           gsub(/^\{:.*\}\n/, "").         # kramdown attribute lines ({:toc}, {:.no_toc}, ...)
           gsub(/^\* TOC\n/, "").
           gsub(/^\*\*Contents\*\*\n/, "").
           gsub(/\n{3,}/, "\n\n").         # blank runs left behind by the strips above
           # Site-relative page links resolve against nothing once the pages are concatenated.
           gsub(/\]\((\w+\.html(?:#[\w-]+)?)\)/, '](https://minion.rocketjob.io/\1)')
    "<!-- source: docs/#{page}.md -->\n\n#{text.strip}\n"
  end

  File.write("docs/llms-full.txt", ([header] + sections).join("\n\n---\n\n"))
  puts "Wrote docs/llms-full.txt (#{File.size('docs/llms-full.txt')} bytes)"
end

Rake::TestTask.new(:test) do |t|
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
  t.warning = false
end

RuboCop::RakeTask.new(:rubocop)

# By default run tests against all appraisals, plus rubocop once at the top level.
# Under `appraisal ... rake` the appraisal is already chosen, so only the tests run.
# rubocop:disable Rake/DuplicateTask -- only one branch is ever loaded, so this is not a real duplicate
if ENV["APPRAISAL_INITIALIZED"]
  task default: :test
else
  require "appraisal"
  task default: %i[appraisal rubocop]
end
# rubocop:enable Rake/DuplicateTask
