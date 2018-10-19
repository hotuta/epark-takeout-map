class AddEparkTakeoutShopsToCombinationPriceMin < ActiveRecord::Migration[5.1]
  def change
    add_column :epark_takeout_shops, :combination_price_min, :integer
  end
end
