class Epark::Takeout::Shop < ApplicationRecord
  has_many :products

  @session = Capybara::Session.new(:chrome)

  def self.get_shop_and_product
    # FIXME: 商品情報を更新するために削除
    Epark::Takeout::Shop::Product.delete_all

    get = RestClient.get "https://takeout.epark.jp"
    header = {x_requested_with: "XMLHttpRequest", cookies: get.cookies}

    page = 1
    loop do
      stores_url = "https://takeout.epark.jp/rstList?page=#{page}&budget=0&category=none&keyword=&latitude=&longitude=&receipt=#{DateTime.now.strftime('%2F')}&sort=2"
      puts stores_url
      response = RestClient.get stores_url, header
      json = response.body
      hash = JSON.parse(json)
      shops_hash = hash["shops"]
      break unless shops_hash
      @takeout_shops = []
      shops_hash.each do |shop|
        takeout_shop = Epark::Takeout::Shop.new
        takeout_shop.name = shop["name"]
        takeout_shop.access = shop["access"]
        takeout_shop.shop_url = "https://takeout.epark.jp/#{shop["code"]}"
        takeout_shop.menu_url = "https://takeout.epark.jp/#{shop["code"]}/menu.php?sort=3&serach_word="
        takeout_shop.coordinates = "#{shop["latitude"]},#{shop["longitude"]}"
        minimum_order = shop["minimumOrder"].gsub(/(\d{0,3}),(\d{3})/, '\1\2').to_i

        menu_response = RestClient.get takeout_shop.menu_url
        menu_header = {x_requested_with: "XMLHttpRequest", cookies: menu_response.cookies}
        menu_doc = Nokogiri::HTML(menu_response.body)

        prices = []
        if menu_doc.css('a[bookmark_shop_id]').present?
          # APIのshop_idとメニューに必要なshop_idが違う:sob:
          shop_id = menu_doc.css('a[bookmark_shop_id]')[0][:bookmark_shop_id]

          loaded_product_count = 0
          while true
            begin
              products = RestClient.post("https://takeout.epark.jp/#{shop["code"]}/ajaxentry/shop_menu/read_more_products.php", {shop_id: shop_id, loaded_product_count: loaded_product_count, sort: 3}, menu_header) {|response| response}
            rescue RestClient::MovedPermanently => err
              binding.pry
            end
            products_json = products.body
            products_hash = JSON.parse(products_json)
            break unless products_hash["products_html"]
            products_hash["products_html"].each do |product_html|
              product_doc = Nokogiri::HTML(product_html)
              shop_product = takeout_shop.products.build
              shop_product.name = product_doc.css(".item_title").text
              shop_product.price = product_doc.css(".item_price").text.delete("円").gsub(/(\d{0,3}),(\d{3})/, '\1\2')
              if shop_product.price <= 1150
                prices << shop_product.price
              end
              shop_product.url = "https://takeout.epark.jp#{product_doc.css(".item_link > a")[0][:href]}"
            end
            left_count = products_hash["total_product_count_num"] - products_hash["item_count"] - loaded_product_count
            puts left_count
            break if left_count == 0
            loaded_product_count += products_hash["item_count"]
          end
        else
          menu_page = 1
          loop do
            old_menu_response = RestClient.get shop["url"] + "/menu?page=#{menu_page}"
            old_menu_doc = Nokogiri::HTML(old_menu_response.body)

            details = old_menu_doc.css(".box > .detail")
            details.each do |detail|
              shop_product = takeout_shop.products.build
              shop_product.name = detail.css(".fn-product-name > a").text
              shop_product.price = detail.css(".price").text.delete("円").gsub(/(\d{0,3}),(\d{3})/, '\1\2').to_i
              if shop_product.price <= 1150
                prices << shop_product.price
              end
              shop_product.url = detail.css(".fn-product-name > a")[0][:href]
            end
            break if details.count < 9
            menu_page += 1
          end
        end

        p prices
        combination_and_order_allowed(takeout_shop, prices, minimum_order)
      end
      Epark::Takeout::Shop.import @takeout_shops, recursive: true, on_duplicate_key_update: {conflict_target: [:shop_url], columns: [:name, :access, :coordinates, :menu_url, :combination]}
      page += 1
    end
  end

  def self.combination_and_order_allowed(takeout_shop, prices, minimum_order)
    combination_prices = []
    price_min = 1080
    price_max = 1150
    if prices.present? && minimum_order <= price_max
      1.upto((price_max / prices.min).ceil) do |count|
        hit_count = 0
        # 重複組合せを順に取り出す
        prices.uniq.repeated_combination(count) do |price|
          if price.sum >= price_min && price.sum <= price_max
            combination_prices << price
            combination_prices << "合計#{price.sum}"
            hit_count += 1
          end
        end
        puts "#{hit_count}ヒット"
      end
    end

    if combination_prices.present?
      takeout_shop.combination = combination_prices.join(",")
      takeout_shop.order_allowed = true
    else
      puts "#{minimum_order}円以上"
      takeout_shop.order_allowed = false
    end
    @takeout_shops << takeout_shop
  end
end
