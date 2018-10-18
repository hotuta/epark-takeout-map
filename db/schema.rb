# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20180429080748) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "epark_takeout_shop_combinations", force: :cascade do |t|
    t.integer "shop_id", null: false
    t.integer "pattern", null: false
    t.integer "candidate", null: false
    t.integer "total_price", null: false
    t.integer "price", null: false
    t.text "name", null: false
    t.text "url", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "registered_at"
  end

  create_table "epark_takeout_shop_products", force: :cascade do |t|
    t.integer "shop_id"
    t.text "name"
    t.text "catchphrase"
    t.text "description"
    t.text "image_path"
    t.integer "price"
    t.text "url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "registered_at"
  end

  create_table "epark_takeout_shops", force: :cascade do |t|
    t.text "name"
    t.text "access"
    t.text "shop_url"
    t.text "menu_url"
    t.boolean "order_allowed", default: false, null: false
    t.text "combination"
    t.text "coordinates"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_url"], name: "index_epark_takeout_shops_on_shop_url", unique: true
  end

end
