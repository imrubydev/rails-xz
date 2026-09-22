# rails-xz-agent

The bounded LLM → `xz check-json` → repair loop, running on ActiveJob.

Part of [rails.xz](https://github.com/imrubydev/rails-xz). See
[docs/02-agent-loop.md](../../docs/02-agent-loop.md).

```ruby
result = RailsXz::Agent.run(
  intent: "Compute the payable total for an order.",
  target: "app/xz/order.xz",
  model: client,
  retries: 3
)
```

Owned jointly by **ax1s-x1zz** and **imrubydev**.