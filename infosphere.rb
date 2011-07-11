#!/usr/bin/env ruby -w
$:.unshift File.join(File.dirname(__FILE__), 'lib')
require 'rubygems'
require 'bundler/setup'
require 'amazon/ecs'
require 'amazon/ecs/ext'
require 'cgi'
require 'open-uri'
require 'infosphere/book'
require 'fastercsv'
require 'set'
require 'yaml'
require 'json'
require 'csv'
require 'pp'

# TODO: Prefer hardcover editions (AlternateVersions response group?)

CONFIG = YAML.load_file('config.yaml')
Amazon::Ecs.configure do |options|
  options[:aWS_access_key_id] = CONFIG['AWS_KEY']
  options[:aWS_secret_key]    = CONFIG['AWS_SECRET']
end

class Infosphere
  
  def initialize
  end
  
  def get_user_recommendations
    recommendations = []
    csv = open( CONFIG['SPREADSHEET_URL'] ).read
    CSV.parse( csv ).each_with_index do |line,i|
      next if i == 0 # Skip header
      date, title, category, url, note, person = *line
      next if category.match(/^Other/) # Looking at specific categories - Other is too broad
      if matches = url.match(%r{/(?:dp|product|ASIN)/([^/]*)})
        recommendations << {
          :id       => matches[1],
          :category => category
        }
      end
    end
    recommendations
  end
      
  # Get a book from the Amazon API
  def get_book( book_id )
    response = if book_id.to_s.length >= 10
      Amazon::Ecs.item_lookup( book_id, :id_type => 'ISBN', :search_index => 'Books', 
        :response_group => 'Large,Reviews,Similarities,AlternateVersions' )
    else
      Amazon::Ecs.item_lookup( book_id, :response_group => 'Large,Reviews,Similarities' )
    end
    response.items.each do |item|
      binding = item.get('ItemAttributes/Binding')
      next if binding.match(/Kindle/i)
      return Book.new( item )
    end
    return nil
  end
  
  # Get similar items using the amazon API
  def similar_items( item_id )
    items = []
    response = Amazon::Ecs.similarity_lookup( item_id.to_s, :response_group => 'Large,Reviews,Similarities' )
    response.items.each do |item|
      items << Book.new( item )
    end
    return items
  end  
  
  # Get products from Amazon API given a node id
  def get_node( node_id, pages=1 )
    items = []
    1.upto( pages ).each do |item_page|
      response = Amazon::Ecs.item_search( nil, :browse_node => node_id, :search_index => 'Books', 
        :response_group => 'Large,Reviews,Similarities,AlternateVersions', :item_page => item_page, 
        :power => 'binding:paperback or hardcover', :sort => 'salesrank' ) # salesrank also possible
      response.items.each do |item|
        items << Book.new( item )
      end
    end
    return items
  end
  
  # Get child nodes
  def child_nodes( node_id )
    children = []
    response = Amazon::Ecs.browse_node_lookup( node_id )
    response.browse_nodes.each do |browse_node|
      nodes = browse_node.get_elements('Children/BrowseNode') || []
      nodes.each do |node|
        children << {
          :name    => node.get_unescaped('Name'),
          :node_id => node.get('BrowseNodeId')
        }
      end
    end
    return children
  end
  
  # Gets rating into from GoodReads and apply it
  def rate_books( books )
    ratings_by_isbn = {}
    books.each_slice( 500 ) do |batch|
      begin
        isbns = batch.collect { |book| book.ean }
        url = "http://www.goodreads.com/book/review_counts.json?isbns=#{isbns.join(',')}&key=#{CONFIG['GOODREADS_KEY']}"
        data = JSON.parse( open( url ).read )
        data['books'].each do |rating|
          ratings_by_isbn[ rating['isbn13'] ] = rating
        end
      rescue Exception
        puts "Ooops! #{$!}"
      end
    end
    books.each do |book|
      if rating = ratings_by_isbn[ book.ean ]
        book.add_rating( rating )
      end
    end
  end
  
  # Writes a CSV output file
  def write_books( books, filename )
    FasterCSV.open( filename, 'w' ) do |csv|
      csv << %w{ Image Title Author Price ASIN ISBN13 Rank AvgRating Reviews Ratings }
      data = books.collect do |book|
        begin
          csv << [
            book.image ? "=Image(\"#{CGI::unescape(book.image)}\")" : nil,
            book.title,
            book.author,
            book.price,
            book.asin,
            book.ean,
            book.sales_rank,
            book.average_rating,
            book.reviews_count,
            book.ratings_count
          ]
        end
      end
    end
  end
  
end

if __FILE__ == $0
  
  
  sphere = Infosphere.new()
  books  = Set.new()
  
  # Strategy #1: User recommendations!
  sphere.get_user_recommendations.each do |reco|
    book = sphere.get_book( reco[:id] )
    next unless book
    puts book
    books.add( book )
  end
    
  # Let's keep track of what the original ones were before we get too carried away
  seed_books = books.clone
    
  # Strategy #2: Top items in categories of seed books
  seen_nodes = Hash.new(false)
  seed_books.each do |book|
    book.nodes.each do |node|
      next if seen_nodes[ node[:node_id] ]
      puts node[:name]
      similar = sphere.get_node( node[:node_id] )
      similar.each do |book|
        puts "\t#{book}"
        books << book
      end
      seen_nodes[ node[:node_id] ] = true
    end
  end
  
  # Strategy #3: Items in strategically selected categories

  # Hm.. I don't have any so far.
  
  # Strategy #4: Similar items
  seed_books.each do |book|
    count = books.length
    sphere.similar_items( book.asin ).each do |similar|
      puts "\t#{similar}"
      books.add( similar )
    end
  end
  
  # Separate the wheat from the chaff
  sphere.rate_books( books )
  good_books = []
  bad_books  = []
  books.each do |book|
    if book.has_rating? && book.average_rating.to_f > 3.5
      good_books.push( book )
    else
      bad_books.push( book )
    end
  end

  # Now write out our results
  sphere.write_books( good_books.sort { |a,b| a.average_rating <=> b.average_rating }, 'books.csv' )
  sphere.write_books( bad_books.sort { |a,b| a.average_rating <=> b.average_rating }, 'rejected_books.csv' )
  puts "#{good_books.length} books written"
  puts "#{bad_books.length} books rejected"  
end