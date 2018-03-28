$LOAD_PATH.push File.expand_path('lib', __dir__)

# Maintain your gem's version:
require 'parallel_minion/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name                  = 'parallel_minion'
  spec.version               = ParallelMinion::VERSION
  spec.platform              = Gem::Platform::RUBY
  spec.authors               = ['Reid Morrison']
  spec.email                 = ['reidmo@gmail.com']
  spec.homepage              = 'https://github.com/reidmorrison/parallel_minion'
  spec.summary               = 'Wrap Ruby code with a minion so that it is run on a parallel thread'
  spec.files                 = Dir['lib/**/*', 'LICENSE.txt', 'Rakefile', 'README.md']
  spec.test_files            = Dir['test/**/*']
  spec.license               = 'Apache License V2.0'
  spec.required_ruby_version = '>= 2.3'
  spec.has_rdoc              = true
  spec.add_dependency 'semantic_logger', '>= 4.0'
end
