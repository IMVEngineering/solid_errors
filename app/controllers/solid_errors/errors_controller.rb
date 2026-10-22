module SolidErrors
  class ErrorsController < ApplicationController
    around_action :use_english_when_available

    before_action :set_error, only: %i[show update destroy]

    helper_method :error_scope, :claim_filter

    # GET /errors
    def index
      errors_table = Error.arel_table
      occurrences_table = Occurrence.arel_table
      query_scope = error_scope.resolved? ? Error.resolved : Error.unresolved
      @errors = query_scope
        .joins(:occurrences)
        .select(errors_table[Arel.star],
          occurrences_table[:created_at].maximum.as("recent_occurrence"),
          occurrences_table[:id].count.as("occurrences_count"))
        .group(errors_table[:id])
        .order(recent_occurrence: :desc)
      @errors = filter_by_claim(@errors) if claiming?
    end

    # GET /errors/1
    # GET /errors/1.md?limit=5
    def show
      respond_to do |format|
        format.html do
          @page = Page.new(@error.occurrences, params)
          @occurrences = @error.occurrences.offset(@page.offset).limit(@page.items).order(created_at: :desc)
        end
        format.md do
          # Served as text/plain so browsers display it inline instead of downloading it
          render plain: @error.to_markdown(limit: params[:limit]), content_type: "text/plain"
        end
      end
    end

    # PATCH/PUT /errors/1
    def update
      @error.resolving_actor = solid_errors_actor
      @error.update!(error_params)
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

    def error_scope
      ActiveSupport::StringInquirer.new(params[:scope] || "unresolved")
    end

    # All, mine or unclaimed; mine only means something when the app says who is signed in
    def claim_filter
      filter = params[:claimed].to_s
      return "all" if filter == "mine" && solid_errors_actor.nil?

      %w[mine unclaimed].include?(filter) ? filter : "all"
    end

    def filter_by_claim(errors)
      case claim_filter
      when "mine" then errors.where(claimed_by_id: solid_errors_actor[:id])
      when "unclaimed" then errors.where(claimed_by_id: nil)
      else errors
      end
    end
  end
end
