# The repo's spec_helper.rb boots a Rails app that is not part of this gem (and
# still calls Spree 1.x APIs), so these specs load the plain objects directly.
# They need no database: both collaborate with a payment through get_metafield /
# set_metafield only.
require 'active_support/core_ext/object/blank'

require_relative '../app/services/payu_metafield'
require_relative '../app/services/payu_payment'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
end
