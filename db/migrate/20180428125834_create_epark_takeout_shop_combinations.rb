class CreateEparkTakeoutShopCombinations < ActiveRecord::Migration[5.1]
  def change
    create_table :epark_takeout_shop_combinations do |t|
      t.integer :shop_id, null: false
      t.integer :pattern, null: false
      t.integer :candidate, null: false
      t.integer :total_price, null: false
      t.integer :price, null: false
      t.text :name, null: false
      t.text :url, null: false

      t.timestamps
    end
  end
end
