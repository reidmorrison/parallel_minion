require_relative "active_record_helper"

# Verifies the Ruby examples in docs/*.md, so that a documented example cannot quietly stop
# matching the code. Every example must parse, and every example that can stand on its own is
# executed against the doubles below.
#
# An example that cannot run standalone is marked in the markdown, on the line directly above
# its fence, with the reason it is exempt:
#
#   <!-- doc-test: skip needs a Rails application -->
#   ~~~ruby
#   Rails.application.configure { ... }
#   ~~~
#
# Keep that list short. A skip means the example is only syntax checked, which is how the
# examples drifted out of date in the first place.
class DocsTest < Minitest::Test
  DOCS = File.expand_path("../docs", __dir__).freeze

  Example = Struct.new(:file, :line, :code, :skip_reason)

  # The world the examples are evaluated in. Examples are evaluated with `module_eval`, so a
  # constant they name resolves here first and only then at the top level, which keeps these
  # doubles from colliding with the models in minion_scope_test.rb.
  #
  # The ActiveRecord models are real, against their own tables, so that an example using an API
  # that no longer exists fails rather than being absorbed by a stub.
  module DocExamples
    class Person < ActiveRecord::Base
      self.table_name = "doc_people"
    end

    class Request < ActiveRecord::Base
      self.table_name = "doc_requests"
    end

    class Account < ActiveRecord::Base
      self.table_name = "doc_accounts"
    end

    class Invoice < ActiveRecord::Base
      self.table_name = "doc_invoices"
    end

    module InventorySupplier
      def self.check(_product_id) = {available: true}
      def self.check_inventory(_product_id) = {available: true}
    end

    module UserSupplier
      def self.more_info(_name) = {details: "info"}
    end

    module RiskEngine
      def self.score(_order) = 5
    end

    module AddressCleanser
      def self.call(address) = address
    end

    # Values the examples refer to but do not define, supplied so they can run as written.
    class << self
      def product_id = 1
      def user_id = 1
      def user_name = "Jack"
      def state = "FL"
      def address = "1 Main Street"
      def order = Object.new
      def options = {count: 0}
      def regions = %w[east west]
      def user = Struct.new(:id, :name).new(1, "Jack")
      def customer = Account.first

      def minion
        @minion ||= ParallelMinion::Minion.new(description: "Doc example fixture") { 42 }
      end

      # Discards the memoized fixtures between examples.
      def reset
        @minion    = nil
        @customer  = Account.first
      end
    end
  end

  ActiveRecord::Schema.define(version: 0) do
    connection.create_table(:doc_people, force: true) do |t|
      t.string :state
      t.integer :user_id
    end
    connection.create_table(:doc_requests, force: true) { |t| t.integer :user_id }
    connection.create_table(:doc_accounts, force: true) { |t| t.boolean :active }
    connection.create_table(:doc_invoices, force: true) { |t| t.string :status }
  end

  DocExamples::Person.create!(state: "FL", user_id: 1)
  DocExamples::Account.create!(active: true)
  DocExamples::Invoice.create!(status: "open")

  SKIP_MARKER = /<!--\s*doc-test:\s*skip\s+(?<reason>.+?)\s*-->/

  class << self
    # Returns every fenced Ruby example in the documentation, with the skip reason from the
    # marker above its fence, if any.
    def examples
      @examples ||= Dir[File.join(DOCS, "*.md")].flat_map { |path| examples_in(path) }
    end

    def examples_in(path)
      file    = File.basename(path)
      lines   = File.readlines(path)
      found   = []
      index   = 0

      while index < lines.length
        opening = lines[index].match(/\A(?<fence>~~~|```)(?<language>\w*)\s*\z/)
        unless opening
          index += 1
          next
        end

        start  = index + 1
        index += 1
        index += 1 while index < lines.length && !lines[index].start_with?(opening[:fence])

        if opening[:language] == "ruby"
          marker = start >= 2 ? lines[start - 2] : nil
          found << Example.new(file, start, lines[start...index].join, marker&.match(SKIP_MARKER)&.[](:reason))
        end
        index += 1
      end

      found
    end

    # Reports a syntax error in `code` as a message, or nil when it parses.
    def syntax_error(code)
      if defined?(RubyVM::InstructionSequence)
        RubyVM::InstructionSequence.compile(code)
      else
        # JRuby and TruffleRuby have no RubyVM.
        require "ripper"
        raise(SyntaxError, "unparseable") if Ripper.sexp(code).nil?
      end
      nil
    rescue SyntaxError => e
      e.message.lines.first.strip
    end
  end

  def setup
    @enabled             = ParallelMinion::Minion.enabled?
    @scoped_classes      = ParallelMinion::Minion.scoped_classes.dup
    @context_handlers    = ParallelMinion::Minion.context_handlers.dup
    @executor            = ParallelMinion::Minion.executor
    @started_log_level   = ParallelMinion::Minion.started_log_level
    @completed_log_level = ParallelMinion::Minion.completed_log_level
    DocExamples.reset
  end

  # Several examples set the global switches on purpose. Put them back so that the example is
  # verified without leaking into the rest of the suite.
  def teardown
    ParallelMinion::Minion.enabled             = @enabled
    ParallelMinion::Minion.scoped_classes      = @scoped_classes
    ParallelMinion::Minion.context_handlers    = @context_handlers
    ParallelMinion::Minion.executor            = @executor
    ParallelMinion::Minion.started_log_level   = @started_log_level
    ParallelMinion::Minion.completed_log_level = @completed_log_level
  end

  # Guards the extractor itself. If a change to the fences or to this parser stopped matching,
  # every example below would silently pass by never being collected at all.
  def test_every_documentation_page_supplies_examples
    pages = Dir[File.join(DOCS, "*.md")].map { |path| File.basename(path) }

    refute_empty pages
    pages.each do |page|
      refute_empty self.class.examples.select { |example| example.file == page },
                   "#{page} has no Ruby examples, or the extractor stopped matching them"
    end
  end

  # A marker that drifted away from its fence exempts nothing and silently means the opposite
  # of what its author intended.
  def test_skip_markers_sit_directly_above_a_ruby_example
    marked = Dir[File.join(DOCS, "*.md")].flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        "#{File.basename(path)}:#{index + 1}" if line.match?(SKIP_MARKER)
      end
    end

    attached = self.class.examples.filter_map do |example|
      "#{example.file}:#{example.line - 1}" if example.skip_reason
    end

    assert_equal marked.sort, attached.sort,
                 "a doc-test skip marker is not directly above a ~~~ruby fence"
  end

  examples.each do |example|
    define_method("test_#{example.file.delete_suffix('.md')}_line_#{example.line}") do
      error = self.class.syntax_error(example.code)

      refute error, "docs/#{example.file}:#{example.line} does not parse: #{error}"
      skip(example.skip_reason) if example.skip_reason

      # A few examples print, which is part of what they are demonstrating. Keep it out of the
      # test runner's output.
      capture_io { DocExamples.module_eval(example.code, "docs/#{example.file}", example.line) }
    end
  end
end
