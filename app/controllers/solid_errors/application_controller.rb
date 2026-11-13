module SolidErrors
  class ApplicationController < SolidErrors.base_controller_class.constantize
    layout "solid_errors/application"
    protect_from_forgery with: :exception

    http_basic_authenticate_with name: SolidErrors.username, password: SolidErrors.password if SolidErrors.password

    # Query params the pager carries from page to page. Add a filter's param here to keep it while paging.
    PAGER_PARAMS = %w[scope items].freeze

    # adapted from: https://github.com/ddnexus/pagy/blob/master/gem/lib/pagy.rb
    OverflowError = Class.new(StandardError)
    class Page
      attr_reader :count, :items, :pages, :first, :last, :prev, :next, :offset, :from, :to

      def initialize(collection, params, default_items: 20)
        @count = collection.count
        @items = [(params[:items] || default_items).to_i, 1].max
        @pages = [(@count.to_f / @items).ceil, 1].max
        @page = (params[:page] || 1).to_i.clamp(1, @pages)
        @first = (1 unless @page == 1)
        @last = (@pages unless @page == @pages)
        @prev = (@page - 1 unless @page == 1)
        @next = (@page == @pages) ? nil : @page + 1
        @offset = (@items * (@page - 1))
        @from = [@offset + 1, @count].min
        @to = [@offset + @items, @count].min
      end
    end
  end
end
