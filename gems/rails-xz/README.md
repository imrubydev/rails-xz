# rails-xz

The Rails Engine: service DSL and the `/xz_audit` board for AI-written,
human-reviewed Xz modules.

Part of [rails.xz](https://github.com/imrubydev/rails-xz). See
[docs/03-audit-engine.md](../../docs/03-audit-engine.md).

```ruby
# config/routes.rb
mount RailsXz::Engine => "/xz_audit"
```

Install it with the generator instead of editing routes by hand:

```bash
bin/rails g rails_xz:install
bin/rails rails_xz:install:migrations
bin/rails db:migrate
```

The generator mounts the Engine in development and test only.


```ruby
class Orders::TotalService
  include RailsXz::XzModule
  xz_module "order", effects: :none

  def call(order)
    payable_total(order.subtotal, order.tax_rate)
  end
end
```

Owned by **imrubydev**.