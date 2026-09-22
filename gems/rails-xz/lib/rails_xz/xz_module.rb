# frozen_string_literal: true

require "active_support/core_ext/string/inflections"

module RailsXz
  # The service-object DSL that wires an approved Xz module into a Ruby class.
  #
  #   class Orders::TotalService
  #     include RailsXz::XzModule
  #     xz_module "order", effects: :none
  #
  #     def call(order)
  #       payable_total(order.subtotal, order.tax_rate)
  #     end
  #   end
  #
  # Including the generated binding module is the Phase 2 slice
  # (docs/05-roadmap.md).
  module XzModule
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def xz_module(name, effects:, lib: nil)
        binding_const = "Xz::Bindings::#{name.to_s.camelize}"
        include Object.const_get(binding_const) if Object.const_defined?(binding_const)

        @xz_module_name = name.to_s
        @xz_effects = effects
        @xz_lib = lib
      end

      attr_reader :xz_module_name, :xz_effects, :xz_lib
    end
  end
end