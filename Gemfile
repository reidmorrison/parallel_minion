source 'http://rubygems.org'

group :test do
  gem 'rake'
  gem 'activerecord'
  gem 'shoulda'
  gem 'mocha'
  gem 'sqlite3', :platform => :ruby

  platforms :jruby do
    gem 'jdbc-sqlite3'
    gem 'activerecord-jdbcsqlite3-adapter'
  end
end

gem 'semantic_logger'