class AddEparkTakeoutShopsToOrder500Allowed < ActiveRecord::Migration[5.1]
  def change
    add_column :epark_takeout_shops, :order_500_allowed, :boolean, default: false
  end
end
