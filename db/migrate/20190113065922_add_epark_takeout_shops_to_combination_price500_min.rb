class AddEparkTakeoutShopsToCombinationPrice500Min < ActiveRecord::Migration[5.1]
  def change
    add_column :epark_takeout_shops, :combination_price_500_min, :integer
  end
end
