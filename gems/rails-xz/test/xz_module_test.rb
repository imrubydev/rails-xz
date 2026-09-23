# frozen_string_literal: true

require "test_helper"

module Xz
  module Bindings
    # A generator-shaped binding: functions are module-level methods declared
    # through RailsXz::Bridge::Facade, not instance methods.
    module Order
      extend RailsXz::Bridge::Facade
      xz_func :payable_total, { subtotal: :float, tax_rate: :float }, :float
    end

    # A hand-written binding whose helper is a plain instance method.
    module Legacy
      def legacy_noop
        :ok
      end
    end
  end
end

class XzModuleTest < Minitest::Test
  class TotalService
    include RailsXz::XzModule
    xz_module "order", effects: :none

    def call(subtotal, tax_rate)
      payable_total(subtotal, tax_rate)
    end
  end

  def setup
    loader = Object.new
    loader.define_singleton_method(:function) do |_name, _args, _returns, need_gvl:|
      ->(subtotal, tax_rate) { subtotal * (1.0 + tax_rate) }
    end
    Xz::Bindings::Order.xz_loader = loader
  end

  def test_binding_functions_are_delegated_to_the_generated_binding
    assert_in_delta 110.0, TotalService.new.call(100.0, 0.1)
  end

  def test_effects_metadata_is_exposed
    assert_equal "order", TotalService.xz_module_name
    assert_equal "none", TotalService.xz_effects
    assert_same Xz::Bindings::Order, TotalService.xz_binding
  end

  def test_unknown_effect_is_rejected
    error = assert_raises(RailsXz::XzModule::UnknownEffect) do
      Class.new do
        include RailsXz::XzModule
        xz_module "order", effects: :bogus
      end
    end

    assert_match(/bogus/, error.message)
  end

  def test_missing_binding_is_rejected
    error = assert_raises(RailsXz::XzModule::MissingBinding) do
      Class.new do
        include RailsXz::XzModule
        xz_module "nonexistent", effects: :none
      end
    end

    assert_match(/Xz::Bindings::Nonexistent/, error.message)
  end

  def test_a_service_defined_method_is_not_overwritten
    service_class = Class.new do
      include RailsXz::XzModule

      def payable_total(*)
        :mine
      end

      xz_module "order", effects: :none
    end

    assert_equal :mine, service_class.new.payable_total(1.0, 2.0)
  end

  def test_include_exposes_plain_instance_methods
    service_class = Class.new do
      include RailsXz::XzModule
      xz_module "legacy", effects: :none
    end

    assert_equal :ok, service_class.new.legacy_noop
  end
end
