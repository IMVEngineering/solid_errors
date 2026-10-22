module SolidErrors
  class ClaimsController < ApplicationController
    before_action :require_claiming
    before_action :set_error

    # POST /errors/1/claim
    def create
      return redirect_to(error_path(@error), alert: "Resolved errors can't be claimed.") if @error.resolved?

      assignee = find_assignee(params[:assignee_id])
      return redirect_to(error_path(@error), alert: "That person can't claim errors.") unless assignee

      @error.claim!(assignee: assignee, actor: solid_errors_actor)
      redirect_to error_path(@error), notice: "Error claimed for #{assignee[:name]}."
    end

    # DELETE /errors/1/claim
    def destroy
      return redirect_to(error_path(@error), alert: "That error isn't claimed.") unless @error.claimed?

      @error.unclaim!(actor: solid_errors_actor)
      redirect_to error_path(@error), notice: "Error unclaimed."
    end

    private

    def require_claiming
      head :not_found unless SolidErrors.claiming?
    end

    def set_error
      @error = Error.find(params[:error_id])
    end

    # The signed-in user may always claim for themselves, even when they aren't an assignee
    def find_assignee(id)
      [solid_errors_actor, *SolidErrors.assignee_list].compact.find { |assignee| assignee[:id] == id.to_s }
    end
  end
end
