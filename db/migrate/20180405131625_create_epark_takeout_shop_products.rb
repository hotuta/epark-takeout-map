class CreateEparkTakeoutShopProducts < ActiveRecord::Migration[5.1]
  def change
    create_table :epark_takeout_shop_products do |t|
      t.integer :shop_id
      t.text :name
      t.text :catchphrase
      t.text :description
      t.text :image_path
      t.integer :price
      t.text :url

      t.timestamps
    end
  end
end
