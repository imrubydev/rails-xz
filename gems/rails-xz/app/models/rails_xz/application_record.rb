# frozen_string_literal: true

module RailsXz
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end