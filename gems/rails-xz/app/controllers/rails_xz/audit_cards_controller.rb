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
      card.approve!(by: current_actor)
      redirect_to card
    end

    def reject
      card = AuditCard.find(params[:id])
      card.reject!(by: current_actor)
      redirect_to card
    end

    private

    # The host app owns authentication; the Engine only reads the acting user.
    def current_actor
      respond_to?(:current_user) ? current_user.to_s : "unknown"
    end
  end
end