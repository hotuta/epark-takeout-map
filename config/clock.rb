require 'clockwork'
require './config/boot'
require './config/environment'

module Clockwork
  handler do |job|
    puts "Running #{job}"
  end

  every(1.days, 'Epark::Takeout::Shop') do
    Epark::Takeout::Shop.get_shop_and_product
  end
end
