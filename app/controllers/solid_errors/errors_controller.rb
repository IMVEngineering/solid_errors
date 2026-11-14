module SolidErrors
  class ErrorsController < ApplicationController
    around_action :use_english_when_available

    before_action :set_error, only: %i[show update destroy]

    helper_method :error_scope, :filter_params, :severity_options, :source_options

    # GET /errors
    def index
      errors_table = Error.arel_table
      occurrences_table = Occurrence.arel_table
      query_scope = (error_scope.resolved? ? Error.resolved : Error.unresolved)
        .search(filter_params["q"])
        .where(filter_params.slice("severity", "source"))
      @page = Page.new(query_scope.where(id: Occurrence.select(:error_id)), params, default_items: 25)
      @errors = query_scope
        .joins(:occurrences)
        .select(errors_table[Arel.star],
          occurrences_table[:created_at].maximum.as("recent_occurrence"),
          occurrences_table[:id].count.as("occurrences_count"))
        .group(errors_table[:id])
        .order(sort_order, errors_table[:id].desc)
        .offset(@page.offset)
        .limit(@page.items)
    end

    # GET /errors/1
    # GET /errors/1.md?limit=5
    # GET /errors/1.md?occurrence_id=7
    def show
      respond_to do |format|
        format.html do
          @page = Page.new(@error.occurrences, params)
          @occurrences = @error.occurrences.offset(@page.offset).limit(@page.items).order(created_at: :desc)
        end
        format.md do
          # Served as text/plain so browsers display it inline instead of downloading it
          render plain: @error.to_markdown(limit: params[:limit], occurrence_id: params[:occurrence_id]), content_type: "text/plain"
        end
      end
    end

    # PATCH/PUT /errors/1
    def update
      @error.update!(error_params)
      # Rows resolve in place via fetch (see the layout); everyone else gets the redirect
      return head :no_content if request.xhr?

      redirect_to errors_path, notice: "Error marked as resolved."
    end

    # DELETE /errors/1
    def destroy
      if @error.resolved?
        @error.destroy
        redirect_to errors_path(scope: :resolved), notice: "Error deleted."
      else
        redirect_to error_path(@error), alert: "You must resolve the error before deleting it."
      end
    end

    private

    # Only allow a list of trusted parameters through.
    def error_params
      params.require(:error).permit(:resolved_at)
    end

    def set_error
      @error = Error.find(params[:id])
    end

    # The dashboard's strings ship in English only; apps that don't allow :en keep their own locale
    def use_english_when_available(&action)
      return action.call unless I18n.locale_available?(:en)

      I18n.with_locale(:en, &action)
    end

    # The search, filter and sort params that are set. Non-string values are ignored.
    def filter_params
      @filter_params ||= params.to_unsafe_h.slice("q", "severity", "source", "sort").select { |_, value| value.is_a?(String) && value.present? }
    end

    def sort_order
      case filter_params["sort"]
      when "first_seen" then Error.arel_table[:created_at].desc
      when "occurrences" then Occurrence.arel_table[:id].count.desc
      else Occurrence.arel_table[:created_at].maximum.desc
      end
    end

    def severity_options
      Error.distinct.order(:severity).pluck(:severity)
    end

    def source_options
      Error.where.not(source: [nil, ""]).distinct.order(:source).pluck(:source)
    end

    def error_scope
      ActiveSupport::StringInquirer.new(params[:scope] || "unresolved")
    end
  end
end
