module Amazon
  class Ecs

    def self.similarity_lookup( item_id, options={} )
      options[:operation] = 'SimilarityLookup'
      options[:item_id] = item_id
      self.send_request(options)
    end

    def self.browse_node_lookup( node_id )
      options[:operation] = 'BrowseNodeLookup'
      options[:browse_node_id] = node_id
      self.send_request(options)
    end
    
    class Response
      def browse_nodes
        @browse_nodes ||= (@doc/"BrowseNode").collect { |item| Element.new(item) }
      end    
    end
    
  end
end