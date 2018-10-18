class CreateEparkTakeoutShops < ActiveRecord::Migration[5.1]
  def change
    create_table :epark_takeout_shops do |t|
      t.text :name
      t.text :access
      t.text :shop_url
      t.text :menu_url
      t.boolean :order_allowed, default: false, null: false
      t.text :combination
      t.text :coordinates

      t.timestamps
    end
    add_index :epark_takeout_shops, [:shop_url], unique: true
  end
end
