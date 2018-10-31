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
      url = "https://takeout.epark.jp/rstList?page=#{page}&budget=0&category=none&keyword=&latitude=&longitude=&receipt=#{Date.today.strftime("%Y/%m/%d")}&sort=1"

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
                price = detail.css(".price").text.delete("円").gsub(/(\d{0,3}),(\d{3})/, '\1\2').to_i
                prices << price if price <= price_max
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
        combination(takeout_shop, prices, 500, price_max)
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

    # 50円未満の商品を組み合わせを取得しようとすると処理時間が異様に長くなるため、暫定処置
    prices.reject! {|p| p < 50}

    # 最大数/最小数の個数まで1つずつ増やして組み合わせてみる
    1.upto((price_max / prices.min).ceil) do |count|
      # 重複組合せを順に取り出す
      prices.uniq.repeated_combination(count) do |price|
        if price.sum >= price_min && price.sum <= price_max && price.sum >= takeout_shop.minimum_order
          combination_prices << price
        end
      end
    end

    if combination_prices.present?
      takeout_shop.combination = "\n"
      combination_prices.sort_by {|combination_price| combination_price.sum}.each_with_index do |combination_price, i|
        takeout_shop.combination_price_min = combination_price.sum if i == 0
        takeout_shop.combination += "#{combination_price}\n"
        takeout_shop.combination += "合計#{combination_price.sum}円\n"
        takeout_shop.order_allowed = true if combination_price.sum == 500
      end
      @takeout_shops << takeout_shop
    end
  end
end
