class AddEparkTakeoutShopsToCombination500 < ActiveRecord::Migration[5.1]
  def change
    add_column :epark_takeout_shops, :combination_500, :integer
  end
end
