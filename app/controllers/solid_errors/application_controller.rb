module SolidErrors
  class ApplicationController < SolidErrors.base_controller_class.constantize
    layout "solid_errors/application"
    protect_from_forgery with: :exception

    http_basic_authenticate_with name: SolidErrors.username, password: SolidErrors.password if SolidErrors.password

    helper_method :claiming?, :current_actor

    private

    def claiming?
      SolidErrors.claiming?
    end

    # The signed-in user as {id:, name:}, when the app configured current_actor
    def current_actor
      return @current_actor if defined?(@current_actor)

      @current_actor = (SolidErrors.actor_for(self) if claiming?)
    end

    public

    # adapted from: https://github.com/ddnexus/pagy/blob/master/gem/lib/pagy.rb
    OverflowError = Class.new(StandardError)
    class Page
      attr_reader :count, :items, :pages, :first, :last, :prev, :next, :offset, :from, :to

      def initialize(collection, params)
        @count = collection.count
        @items = (params[:items] || 20).to_i
        @pages = [(@count.to_f / @items).ceil, 1].max
        @page = ((page = (params[:page] || 1).to_i) > @pages) ? @pages : page
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
