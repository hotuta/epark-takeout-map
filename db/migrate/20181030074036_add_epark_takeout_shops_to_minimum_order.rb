class AddEparkTakeoutShopsToMinimumOrder < ActiveRecord::Migration[5.1]
  def change
    add_column :epark_takeout_shops, :minimum_order, :integer
  end
end
