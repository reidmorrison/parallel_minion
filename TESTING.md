## Installation

Install all needed gems to run the tests:

    appraisal install

The gems are installed into the global gem list.
The Gemfiles in the `gemfiles` folder are also re-generated.

## Run Tests

For all supported Rails/ActiveRecord versions:

    rake

Or for specific version one:

    appraisal rails_6.0 rake

Or for one particular test file

    appraisal rails_6.0 ruby test/minion_test.rb

Or down to one test case

    appraisal rails_6.0 ruby test/minion_test.rb -n "/raise exception/"
