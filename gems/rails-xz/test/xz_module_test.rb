# frozen_string_literal: true

require "test_helper"

module Xz
  module Bindings
    module Order
      def payable_total(subtotal, tax_rate)
        subtotal * (1.0 + tax_rate)
      end
    end
  end
end

class XzModuleTest < Minitest::Test
  class TotalService
    include RailsXz::XzModule
    xz_module "order", effects: :none
  end

  def test_binding_methods_are_included
    service = TotalService.new

    assert_in_delta 110.0, service.payable_total(100.0, 0.1)
  end

  def test_effects_are_recorded
    assert_equal :none, TotalService.xz_effects
    assert_equal "order", TotalService.xz_module_name
  end
end