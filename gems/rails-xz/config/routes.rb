# frozen_string_literal: true

RailsXz::Engine.routes.draw do
  resources :audit_cards, only: %i[index show], path: "modules" do
    member do
      post :approve
      post :reject
    end
  end

  root to: "audit_cards#index"
end