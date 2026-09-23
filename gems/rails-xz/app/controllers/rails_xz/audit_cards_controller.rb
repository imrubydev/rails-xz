# frozen_string_literal: true

module RailsXz
  class AuditCardsController < ApplicationController
    def index
      @cards = AuditCard.order(created_at: :desc)
    end

    def show
      @card = AuditCard.find(params[:id])
    end

    def approve
      card = AuditCard.find(params[:id])
      RailsXz::Approval.call(card, by: current_actor)
      render_decision(card)
    rescue RailsXz::Approval::Error => e
      redirect_to card, alert: e.message
    end

    def reject
      card = AuditCard.find(params[:id])
      card.reject!(by: current_actor)
      render_decision(card)
    end

    private

    # The card carries its own DOM id, so a Turbo form submission replaces just
    # that card with the decided one instead of reloading the page. A plain
    # request still falls back to the show page. See docs/03-audit-engine.md §2.
    def render_decision(card)
      respond_to do |format|
        format.html { redirect_to card }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            card,
            AuditCardComponent.new(card: card)
          )
        end
      end
    end

    # The host app owns authentication; the Engine only reads the acting user.
    def current_actor
      respond_to?(:current_user) ? current_user.to_s : "unknown"
    end
  end
end
