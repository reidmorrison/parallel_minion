appraise "rails_5.1" do
  gem "activerecord", "~> 5.1.5"
  gem "sqlite3", "~> 1.3.0", platform: :ruby
  gem "activerecord-jdbcsqlite3-adapter", "~> 51.0", platform: :jruby
  gem "mutex_m", platform: :jruby
  # JRuby 10 / Ruby 3.4+: bundled default gems
  gem "base64", platform: :jruby
  gem "bigdecimal", platform: :jruby
  gem "logger", platform: :jruby
  # Ruby 2.5 CI: minitest >= 5.18 needs Ruby >= 2.6
  gem "minitest", ">= 5.1", "< 5.18"
end

appraise "rails_5.2" do
  gem "activerecord", "~> 5.2.0"
  gem "sqlite3", "~> 1.3.0", platform: :ruby
  gem "activerecord-jdbcsqlite3-adapter", "~> 52.0", platform: :jruby
  gem "mutex_m", platform: :jruby
  gem "base64", platform: :jruby
  gem "bigdecimal", platform: :jruby
  gem "logger", platform: :jruby
  gem "minitest", ">= 5.1", "< 5.18"
end

appraise "rails_6.0" do
  gem "activerecord", "~> 6.0.0"
  gem "activerecord-jdbcsqlite3-adapter", "~> 60.0", platform: :jruby
  gem "sqlite3", "~> 1.4.0", platform: :ruby
  gem "mutex_m", platform: :jruby
  gem "base64", platform: :jruby
  gem "bigdecimal", platform: :jruby
  gem "logger", platform: :jruby
  # Ruby 2.6 CI: minitest >= 5.26 needs Ruby >= 2.7
  gem "minitest", ">= 5.1", "< 5.26"
end

appraise "rails_6.1" do
  gem "activerecord", "~> 6.1.0"
  gem "activerecord-jdbcsqlite3-adapter", "~> 61.0", platform: :jruby
  gem "sqlite3", "~> 1.4.0", platform: :ruby
  gem "mutex_m", platform: :jruby
  gem "base64", platform: :jruby
  gem "bigdecimal", platform: :jruby
  gem "logger", platform: :jruby
  # Ruby 3.0 CI: minitest >= 5.27 needs Ruby >= 3.1
  gem "minitest", ">= 5.1", "< 5.27"
end

appraise "rails_7.0" do
  gem "activerecord", "~> 7.0"
  gem "sqlite3", "~> 1.4.0", platform: :ruby
  gem "minitest", ">= 5.1", "< 6"
end

# Rails 7.2 stack: MRI needs explicit base64/bigdecimal on Ruby 3.4+ (stdlib default gems).
appraise "rails_7.2" do
  gem "activerecord", "~> 7.2"
  gem "sqlite3", ">= 1.4", platform: :ruby
  gem "base64"
  gem "bigdecimal"
  gem "minitest", ">= 5.1", "< 6"
end
