# rails-xz-bridge

The Ruby FFI bridge: generate bindings from `.xzint` interfaces or the C header
`xz build --shared` writes, and load compiled Xz shared libraries. Scalar- and
pointer-only calls go through `Fiddle`; by-value aggregates (`Str`, `Bytes`,
`@cstruct`) and `mut` in/out cells go through `ffi`, because Fiddle cannot pass
or return a C struct by value.

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