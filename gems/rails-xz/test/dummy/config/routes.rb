# frozen_string_literal: true

Rails.application.routes.draw do
  mount RailsXz::Engine => "/xz_audit"
end
