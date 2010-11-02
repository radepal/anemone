require 'anemone/http'

module Anemone
  class PageWorker

    #
    # Create a new Tentacle
    #
    def initialize(link_queue, page_queue,pages,varibles={}, opts = {})
      @link_queue = link_queue
      @page_queue = page_queue
      @pages = pages
      @on_every_page_blocks = varibles[:on_every_page_blocks]
      @on_pages_like_blocks = varibles[:on_pages_like_blocks]
      @focus_crawl_block = varibles[:focus_crawl_block]
      @skip_link_patterns = varibles[:skip_link_patterns]
      @opts = opts
    end

    #
    # Gets links from @link_queue, and returns the fetched
    # Page objects into @page_queue
    #
    def run
    #  sleep 0.1 until @page_queue.empty?
      loop do
        page = @page_queue.deq
        break if page == :END

        @pages.touch_key page.url
        puts "#{page.url} Queue link: #{@link_queue.size} Queue page: #{@page_queue.size}" if @opts[:verbose]
        do_page_blocks page
        page.discard_doc! if @opts[:discard_page_bodies]
        links = links_to_follow page
        links.each do |link|
          @link_queue << [link, page.url.dup, page.depth + 1]
        end
        @pages.touch_keys links

        @pages[page.url] = page

        delay
      end
    end

    private
 #
    # Execute the on_every_page blocks for *page*
    #
    def do_page_blocks(page)
      @on_every_page_blocks.each do |block|
        block.call(page)
      end

      @on_pages_like_blocks.each do |pattern, blocks|
        blocks.each { |block| block.call(page) } if page.url.to_s =~ pattern
      end
    end

    #
    # Return an Array of links to follow from the given page.
    # Based on whether or not the link has already been crawled,
    # and the block given to focus_crawl()
    #
    def links_to_follow(page)
      links = @focus_crawl_block ? @focus_crawl_block.call(page) : page.links
      links.select { |link| visit_link?(link, page) }.map { |link| link.dup }
    end

    #
    # Returns +true+ if *link* has not been visited already,
    # and is not excluded by a skip_link pattern...
    # and is not excluded by robots.txt...
    # and is not deeper than the depth limit
    # Returns +false+ otherwise.
    #
    def visit_link?(link, from_page = nil)
      !@pages.has_page?(link) &&
      !skip_link?(link) &&
      !skip_query_string?(link) &&
      allowed(link) &&
      !too_deep?(from_page)
    end

    #
    # Returns +true+ if we are obeying robots.txt and the link
    # is granted access in it. Always returns +true+ when we are
    # not obeying robots.txt.
    #
    def allowed(link)
      @opts[:obey_robots_txt] ? @robots.allowed?(link) : true
    end

    #
    # Returns +true+ if we are over the page depth limit.
    # This only works when coming from a page and with the +depth_limit+ option set.
    # When neither is the case, will always return +false+.
    def too_deep?(from_page)
      if from_page && @opts[:depth_limit]
        from_page.depth >= @opts[:depth_limit]
      else
        false
      end
    end

    #
    # Returns +true+ if *link* should not be visited because
    # it has a query string and +skip_query_strings+ is true.
    #
    def skip_query_string?(link)
      @opts[:skip_query_strings] && link.query
    end

    #
    # Returns +true+ if *link* should not be visited because
    # its URL matches a skip_link pattern.
    #
    def skip_link?(link)
      @skip_link_patterns.any? { |pattern| link.path =~ pattern }
    end
    
    def delay
      sleep @opts[:delay] if @opts[:delay] > 0
    end

  end
end
