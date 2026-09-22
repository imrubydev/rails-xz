# rails-xz-bridge

The Ruby FFI bridge: generate bindings from `.xzint` interfaces and load
compiled Xz shared libraries through `Fiddle` or `ffi`.

Part of [rails.xz](https://github.com/imrubydev/rails-xz). See
[docs/01-bridge.md](../../docs/01-bridge.md).

```ruby
loader = RailsXz::Bridge::Loader.new("vendor/xz/liborder.so")
loader.load!
fn = loader.function("payable_total",
                     [Fiddle::TYPE_DOUBLE, Fiddle::TYPE_DOUBLE],
                     Fiddle::TYPE_DOUBLE)
```

Owned by **ax1s-x1zz**.