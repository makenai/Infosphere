require 'rubygems'
require 'bundler/setup'
require 'amazon/ecs'
require 'htmlentities'
require 'yaml'
require 'pp'

RECOMMENDATIONS = 'https://spreadsheets.google.com/spreadsheet/pub?hl=en_US&hl=en_US&key=0AiGJ08IIrqw0dGZ2aUJNdDBqZVZYb210VFVndEdEM2c&output=csv'

# TODO: Prefer hardcover editions

CONFIG = YAML.load_file('config.yaml')
Amazon::Ecs.configure do |options|
  options[:aWS_access_key_id] = CONFIG['AWS_KEY']
  options[:aWS_secret_key]    = CONFIG['AWS_SECRET']
end

class Infosphere
  
  def initialize
  end
  
  def run
    puts 'Hi'
  end
  
  def parse_item( item )
    data = {
      :title      => item.get_unescaped('ItemAttributes/Title'),
      :author     => item.get_unescaped('ItemAttributes/Author'),
      :asin       => item.get('ASIN'),
      :isbn       => item.get('ItemAttributes/ISBN'),
      :ean        => item.get('ItemAttributes/EAN'),
      :sales_rank => item.get('SalesRank'),
      :binding    =>  item.get('ItemAttributes/Binding'),
      :image      => item.get('MediumImage/URL'),
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
        data[:nodes] << {
          :name    => node.get_unescaped('Name'),
          :node_id => node.get('BrowseNodeId')
        }
      end
    end
    return data    
  end
    
  # Get a book from the Amazon API
  def get_book( book_id )
    response = if book_id.to_s.length >= 10
      Amazon::Ecs.item_lookup( book_id, :id_type => 'ISBN', :search_index => 'Books', :response_group => 'Large,Reviews,Similarities' )
    else
      Amazon::Ecs.item_lookup( book_id, :response_group => 'Large,Reviews,Similarities' )
    end
    response.items.each do |item|
      binding = item.get('ItemAttributes/Binding')
      next if binding.match(/Kindle/i)
      return parse_item( item )
    end
  end
  
  # Get products from Amazon API given a node id
  def get_node( node_id, pages=1 )
    items = []
    1.upto( pages ).each do |item_page|
      response = Amazon::Ecs.item_search( nil, :browse_node => node_id, :search_index => 'Books', 
        :response_group => 'Large,Reviews,Similarities', :item_page => item_page, 
        :power => 'binding:paperback or hardcover', :sort => 'reviewrank' ) # salesrank also possible
      response.items.each do |item|
        items << parse_item( item )
      end
    end
    return items
  end
  
end

if __FILE__ == $0

  seeds = YAML.load_file('seed_books.yaml')
  
  sphere = Infosphere.new()
    
  seeds.each do |category,isbns|
    isbns.each do |isbn|
      
      book = sphere.get_book( isbn )
      pp book
      exit
      
    end
  end
  
end