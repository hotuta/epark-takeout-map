class Epark::Takeout::Shop < ApplicationRecord
  has_many :products
  has_many :combinations

  @session = Capybara::Session.new(:chrome)

  def self.get_shop_and_product
    # FIXME: 情報を更新するために削除
    Epark::Takeout::Shop::Product.delete_all
    Epark::Takeout::Shop::Combination.delete_all

    get = RestClient.get "https://takeout.epark.jp"
    header = {x_requested_with: "XMLHttpRequest", cookies: get.cookies}

    page = 1
    loop do
      stores_url = "https://takeout.epark.jp/rstList?page=#{page}&budget=0&category=none&keyword=&latitude=&longitude=&receipt=#{(DateTime.now + 1).strftime('%2F')}&sort=2"
      puts stores_url
      response = RestClient.get stores_url, header
      json = response.body
      hash = JSON.parse(json)
      shops_hash = hash["shops"]
      break unless shops_hash.present?
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

        price_max = 1110

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
              if shop_product.price <= price_max
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
              if shop_product.price <= price_max
                prices << shop_product.price
              end
              shop_product.url = detail.css(".fn-product-name > a")[0][:href]
            end
            break if details.count < 9
            menu_page += 1
          end
        end

        combination_and_order_allowed(takeout_shop, prices, price_max, minimum_order)
      end
      Epark::Takeout::Shop.import @takeout_shops, recursive: true, on_duplicate_key_update: {conflict_target: [:shop_url], columns: [:name, :access, :coordinates, :menu_url, :combination, :order_allowed]}
      page += 1
    end
  end

  def self.combination_and_order_allowed(takeout_shop, prices, price_max, minimum_order)
    p prices

    combinations = []
    price_min = 1080
    if prices.present? && minimum_order <= price_max
      1.upto((price_max / prices.min).ceil) do |count|
        hit_count = 0
        # 重複組合せを順に取り出す
        prices.uniq.repeated_combination(count) do |combination_price|
          if combination_price.sum >= price_min && combination_price.sum <= price_max
            combinations << combination_price
            hit_count += 1
          end
        end
        puts "#{hit_count}ヒット"
      end
    end

    if combinations.present?
      pattern = 0
      combinations.each do |combination|
        total_price = combination.sum
        combination.each do |combination_price|
          combination_products = takeout_shop.products.select do |n|
            n.price == combination_price
          end

          if combination_products.count >= 2
            # 同一金額商品が複数ある場合
            candidate = 1
          else
            # 同一金額商品が一つだけ
            candidate = 0
          end

          combination_products.each do |combination_product|
            shop_combination = takeout_shop.combinations.build
            shop_combination.pattern = pattern
            shop_combination.candidate = candidate
            shop_combination.total_price = total_price
            shop_combination.price = combination_product.price
            shop_combination.name = combination_product.name
            shop_combination.url = combination_product.url
            candidate += 1
          end
        end
        pattern += 1
      end

      takeout_shop.order_allowed = true
    else
      puts "#{minimum_order}円以上"
      takeout_shop.order_allowed = false
    end

    @takeout_shops << takeout_shop
  end
end
