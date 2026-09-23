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
  # `xz_module` resolves the generated binding `Xz::Bindings::<Camelized name>`
  # (docs/01-bridge.md section 6), exposes its functions as instance methods,
  # and records the declared effect profile as service metadata
  # (docs/03-audit-engine.md section 8).
  module XzModule
    EFFECTS = %w[none mut io chan extern].freeze

    # Raised when the generated binding for a module name is not defined.
    MissingBinding = Class.new(NameError)
    # Raised when the declared effect label is not one the compiler emits.
    UnknownEffect = Class.new(ArgumentError)

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def xz_module(name, effects:)
        binding = resolve_xz_binding(name)

        declared = effects.to_s
        unless EFFECTS.include?(declared)
          raise UnknownEffect,
                "unknown effect #{effects.inspect}; expected one of " \
                "#{EFFECTS.map(&:inspect).join(', ')}"
        end

        include binding
        expose_xz_functions(binding)

        @xz_module_name = name.to_s
        @xz_effects = declared
        @xz_binding = binding
      end

      attr_reader :xz_module_name, :xz_effects, :xz_binding

      private

      def resolve_xz_binding(name)
        const_name = "Xz::Bindings::#{name.to_s.camelize}"
        unless Object.const_defined?(const_name)
          raise MissingBinding,
                "no generated binding #{const_name}; generate it with the " \
                "bridge (docs/01-bridge.md section 6)"
        end

        Object.const_get(const_name)
      end

      # A generated binding declares its functions as module-level methods
      # through RailsXz::Bridge::Facade, so `include` alone does not make them
      # instance methods. Forward each declared function to the binding; a
      # method the service defines itself is never overwritten.
      def expose_xz_functions(binding)
        return unless binding.respond_to?(:declared_functions)

        binding.declared_functions.each_key do |function|
          next if method_defined?(function) || private_method_defined?(function)

          define_method(function) do |*args, **kwargs, &block|
            binding.public_send(function, *args, **kwargs, &block)
          end
        end
      end
    end
  end
end
