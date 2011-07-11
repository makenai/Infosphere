class Book
  
  # Takes an Amazon::Response as an argument
  def initialize( item )
    data = {
      :title      => item.get_unescaped('ItemAttributes/Title'),
      :author     => item.get_unescaped('ItemAttributes/Author'),
      :asin       => item.get('ASIN'),
      :isbn       => item.get('ItemAttributes/ISBN'),
      :ean        => item.get('ItemAttributes/EAN'),
      :sales_rank => item.get('SalesRank'),
      :binding    => item.get('ItemAttributes/Binding'),
      :image      => item.get_unescaped('SmallImage/URL'),
      :price      => item.get('ItemAttributes/ListPrice/FormattedPrice'),
      :similar    => [],
      :nodes      => []
    }
    if similarities = item.get_elements('SimilarProducts/SimilarProduct')
      similarities.each do |similarity|
        data[:similar] << {
          :asin  => similarity.get('ASIN'),
          :title => similarity.get_unescaped('Title')
        }
      end
    end
    if nodes = item.get_elements('BrowseNodes/BrowseNode')
      nodes.each do |node|
        node_id = node.get('BrowseNodeId')
        next if node_id == '1297808011' # Books
        next if node_id == '1294449011' # Books
        next if node_id == '1288264011' # All Product
        data[:nodes] << {
          :name    => node.get_unescaped('Name'),
          :node_id => node.get('BrowseNodeId')
        }
      end
    end
    @data = data
    @rating = nil
  end
  
  # All comparisons will be based on the ASIN
  def hash
    @data[:asin].to_s.hash
  end
  
  # Ditto. ASIN comparison
  def eql?( other )
    asin.to_s == other.asin.to_s
  end
  
  def []( key )
    @data[ key ]
  end
  
  def to_s
    "#{@data[:title]} - #{@data[:author]} [#{@data[:asin]}]"
  end
  
  # Not so pretty.. but meh.
  def method_missing( method, *args )
    @data[ method ] || ( @rating ? @rating[ method.to_s ] : nil )
  end
  
  # {
  #   work_text_reviews_count: 73
  #   text_reviews_count: 3
  #   average_rating: "3.70"
  #   work_ratings_count: 585
  #   isbn13: "9780471237129"
  #   isbn: "0471237124"
  #   id: 1005528
  #   work_reviews_count: 1107
  #   reviews_count: 87
  #   ratings_count: 28
  # }
  def add_rating( rating )
    @rating = rating
  end
  
  def has_rating?
    @rating ? true : false
  end
  
end