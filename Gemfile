source 'http://rubygems.org'

gem 'rake'
gem 'semantic_logger', '~> 2.1'

group :test do
  gem 'minitest', '~> 3.0'
  gem 'shoulda', '~> 2.0'
  gem 'activerecord'
  gem 'mocha'
  gem 'sqlite3', platform: :ruby

  platforms :jruby do
    gem 'jdbc-sqlite3'
    gem 'activerecord-jdbcsqlite3-adapter'
  end
end
