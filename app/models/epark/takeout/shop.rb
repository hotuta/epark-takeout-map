class Epark::Takeout::Shop < ApplicationRecord
  has_many :products
  has_many :combinations

  @session = Capybara::Session.new(:chrome)

  class << self
    def get_res_to_obj(url, headers)
      Retryable.retryable(tries: 5) do
        res = RestClient.get(url, headers)
        json = res.body
        JSON.parse(json, object_class: OpenStruct).shops
      end
    end
  end

  def self.get_shop_and_product
    # FIXME: 情報を更新するために削除
    Epark::Takeout::Shop::Product.delete_all
    Epark::Takeout::Shop::Combination.delete_all

    get = RestClient.get "https://takeout.epark.jp"
    header = {x_requested_with: "XMLHttpRequest", cookies: get.cookies}

    page = 1
    loop do
      # なか卯スペシャル
      url = "https://takeout.epark.jp/rstList?page=#{page}&budget=0&category=none&keyword=%E3%81%AA%E3%81%8B%E5%8D%AF&latitude=&longitude=&receipt=2019%2F02%2F11&immediate=true&sort=1"
      # url = "https://takeout.epark.jp/rstList?page=#{page}&budget=0&category=none&keyword=&latitude=&longitude=&receipt=#{Date.today.strftime("%Y/%m/%d")}&sort=1"

      header = {Accept: '*/*', X_Requested_With: 'XMLHttpRequest'}
      shops = get_res_to_obj(url, header)

      @takeout_shops = []
      shops.each do |shop|
        takeout_shop = Epark::Takeout::Shop.new
        takeout_shop.name = shop["name"]
        takeout_shop.access = shop["access"]
        takeout_shop.shop_url = shop["url"]
        takeout_shop.menu_url = shop["url"] + "/menu?category_id=0&min=&max=&sort=1&page=1"
        takeout_shop.coordinates = "#{shop["latitude"]},#{shop["longitude"]}"
        takeout_shop.minimum_order = shop["minimumOrder"].gsub(/(\d{0,3}),(\d{3})/, '\1\2').to_i

        price_max = 1000
        next if takeout_shop.minimum_order > price_max

        menu_response = RestClient.get takeout_shop.menu_url
        menu_header = {x_requested_with: "XMLHttpRequest", cookies: menu_response.cookies}
        menu_doc = Nokogiri::HTML(menu_response.body)

        prices = []
        menu_page = 1
        catch(:break_loop) do
          loop do
            Retryable.retryable(tries: 5) do
              puts url
              puts shop["url"] + "/menu?page=#{menu_page}"
              old_menu_response = RestClient.get shop["url"] + "/menu?page=#{menu_page}"
              old_menu_doc = Nokogiri::HTML(old_menu_response.body)

              details = old_menu_doc.css(".box > .detail")
              details.each do |detail|
                targetid = detail.css(".favorite_product > a").first[:targetid].to_i
                product_response = RestClient.get "https://takeout.epark.jp/ajax/order/box?product_id=#{targetid}"
                product = JSON.parse(product_response, object_class: OpenStruct)

                price = detail.css(".price").text.delete("円").gsub(/(\d{0,3}),(\d{3})/, '\1\2').to_i

                # 50円未満の商品を組み合わせを取得しようとすると処理時間が異様に長くなるため、暫定処置
                if price <= price_max && price > 50
                  product_name = detail.css("div.title.fn-product-name > a").first.text
                  product_link = detail.css("div.title.fn-product-name > a").first[:href]

                  prices << {product_name: product_name, total_price: price, product_link: product_link}

                  if product.detail.options.present?
                    product.detail.options.each do |product_option|
                      product_option.lists.each do |list|
                        if list.price.present? && price + list.price <= price_max
                          prices << {product_name: product_name, option_name: list.name, total_price: price + list.price, product_link: product_link}
                        end
                      end
                    end
                  end
                end

                # shop_product = takeout_shop.products.build
                # shop_product.name = detail.css(".fn-product-name > a").text
                # shop_product.price = detail.css(".price").text.delete("円").gsub(/(\d{0,3}),(\d{3})/, '\1\2').to_i
                # if shop_product.price <= price_max
                #   prices << shop_product.price
                # end
                # shop_product.url = detail.css(".fn-product-name > a")[0][:href]
              end
              throw :break_loop if details.count < 9
              menu_page += 1
            end
          end
        end

        next if prices.blank?
        combination(takeout_shop, prices, 50, price_max)
      end

      columns = Epark::Takeout::Shop.column_names - ["id", "shop_url", "created_at", "updated_at"]
      Epark::Takeout::Shop.import @takeout_shops, recursive: true, on_duplicate_key_update: {conflict_target: [:shop_url], columns: columns}

      if shops.blank?
        puts "終了"
        break
      end

      page += 1
    end
  end

  def self.combination(takeout_shop, prices, price_min, price_max)
    combination_prices = []
    prices_array = prices.map {|h| h[:total_price]}.uniq.sort
    prices_min = prices_array.min

    # 最大数/最小数の個数まで1つずつ増やして組み合わせてみる
    1.upto((price_max / prices_min).ceil) do |count|
      # 重複組合せを順に取り出す
      prices_array.repeated_combination(count) do |price_array|
        price_sum = price_array.sum

        if price_sum >= price_min && price_sum <= price_max && price_sum >= takeout_shop.minimum_order
          combination_prices << price_array.map do |price|
            if prices.count {|price_hash| price_hash[:total_price] == price} > 1
              prices.map do |price_hash|
                if price_hash[:option_name].present?
                  {product_name: price_hash[:product_name], option_name: price_hash[:option_name], total_price: price}
                else
                  {total_price: price}
                end
              end.compact.uniq
            else
              prices.map do |price_hash|
                price_hash if price_hash[:total_price] == price
              end.compact
            end
          end.compact.flatten
        end
      end
    end

    if combination_prices.present?
      takeout_shop.combination = "\n"
      takeout_shop.combination_500 = "\n"

      combination_prices.uniq.sort_by {|combination_price| combination_price.sum {|hash| hash[:total_price]}}.each_with_index do |combination_price, i|
        combination_price_sum = combination_price.sum {|hash| hash[:total_price]}
        next if combination_price_sum > price_max
        takeout_shop.combination_price_min = combination_price_sum if i == 0

        if combination_price_sum >= 500
          takeout_shop.combination_price_500_min = combination_price_sum if takeout_shop.combination_price_500_min.blank?
          if combination_price.any? {|hash| hash[:product_name]}
            takeout_shop.combination_500 += "#{combination_price}\n"
          else
            takeout_shop.combination_500 += "#{combination_price.map {|hash| hash[:total_price]}}\n"
          end
          takeout_shop.combination_500 += "合計#{combination_price_sum}円\n"
        end

        takeout_shop.combination += "#{combination_price}\n"
        takeout_shop.combination += "合計#{combination_price_sum}円\n"
        takeout_shop.order_allowed = true if combination_price_sum <= 500
        takeout_shop.order_500_allowed = true if combination_price_sum == 500
      end
      @takeout_shops << takeout_shop
    end
  end
end
