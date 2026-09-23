# frozen_string_literal: true

module Orders
  # Calls the approved Xz module through its generated binding
  # (`Xz::Bindings::Order`). See docs/03-audit-engine.md section 8.
  class TotalService
    include RailsXz::XzModule
    xz_module "order", effects: :none

    def call(order)
      payable_total(order.subtotal, order.tax_rate)
    end
  end
end
