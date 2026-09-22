# 01 — Ruby FFI bridge

`rails-xz-bridge` turns an Xz shared library into a typed Ruby module that a
Rails service object can call directly.

## 1. What the Xz side guarantees

From the Xz FFI spec:

- `xz build --shared <file.xz>` emits a shared object plus a C header for the
  functions marked `@export`. Everything else keeps internal linkage.
- An exported signature must be C-representable end to end: `Bool`, `Int`,
  `usize`, `Float`, `Char`, `Str`, `Bytes`, `Ptr`, or a `@cstruct record`, with
  `Unit` allowed only as the return. A `Result`, `Option`, `List`, `Map`, `Set`,
  `Chan`, `enum`, or plain `record` has no C declaration and is rejected.
- `Str`/`Bytes` cross as two-field structs (pointer + length, no NUL
  guarantee). `mut` parameters map to `T*` (C in/out).
- The generated header is an honest, complete description of the ABI.

The bridge consumes exactly this surface. It never reads Xz source to guess a
layout; it reads the generated header or the `.xzint` interface.

## 2. Interface-first workflow

Preferred: declare the boundary in a `.xzint` file and generate both sides from
it.

```
liborder.xzint ──► xz pkg gen --lang python   (existing)
              └──► xz pkg gen --lang ruby      (planned, in the Xz CLI)
                        │
                        ▼
                  app/xz/bindings/order.rb
```

`xz pkg gen --lang ruby` mirrors the existing `--lang python` target:

- emits a module named after the interface stem,
- declares each `@cstruct` as a Ruby `Struct`/`Data` with matching field order,
- types every `extern`/`@export` function,
- loads the shared object named by `--lib` (default: stem + platform suffix).

Until `--lang ruby` ships, `rails-xz-bridge` provides a generator that parses
the same `.xzint` grammar and emits the same shape, so the CLI and the gem stay
interchangeable. This is the same fallback strategy `next.xz` uses for
TypeScript.

## 3. Loading the library

| Backend | Mechanism | Notes |
|---|---|---|
| `Fiddle` (default) | Ruby stdlib `dlopen` + `Function` | No native dependency; ships with Ruby. |
| `ffi` | `ffi` gem | Faster for high-frequency calls; optional. |

The loader:

1. resolves the shared object path from the generated metadata,
2. verifies the Xz compiler version recorded in the metadata,
3. registers each symbol with its C signature,
4. returns a typed facade.

A version mismatch raises `RailsXz::Bridge::VersionError`. A missing symbol
raises `RailsXz::Bridge::SymbolError`. Both are actionable, not silent.

`Fiddle` is the default so that installing `rails.xz` adds no native build
dependency. The `ffi` gem is an opt-in acceleration for hot call paths.

## 4. Marshalling

### 4.1 Scalars

`Bool` → `true`/`false`, `Int`/`usize` → `Integer`, `Float` → `Float`,
`Char` → single-character `String`.

### 4.2 `Str` / `Bytes`

`Str` crosses as UTF-8 bytes into an `XzStr` struct; the binding encodes on call
and decodes on return. `Bytes` crosses as `String` with `Encoding::BINARY` and is
passed through without transcoding. A `Str`/`Bytes` return value is read from the
returned pointer/length pair; ownership of any newly allocated return buffer is
defined by the wrapper contract (see §5).

### 4.3 `@cstruct`

Generated as a Ruby `Data` (immutable) or `Struct` with the same field order and
alignment. Nested `@cstruct` records nest as nested objects. The Ruby side never
reorders fields; the C layout is authoritative.

### 4.4 Handles

A `@cstruct` containing a `Ptr` is a handle type: never copied, handed off only
with `transfer`. The Ruby binding exposes it as an opaque object whose methods
route back into the library; it is not a plain value object. A handle owns its
lifetime; the binding raises if a transferred handle is used again.

## 5. The `Result` problem

A C ABI export cannot carry a `Result`. Three sanctioned patterns, in order of
preference:

1. **Contracted wrapper (default).** Write a thin `@export` Xz function whose
   signature is C-representable and whose contract documents the mapping, e.g.
   an out-parameter `mut` status plus a value. The Ruby binding re-raises a typed
   error.

   ```xz
   /// @intent  Parses an amount; writes the value and returns a status code.
   /// @effects none
   @export func parse_amount(text: Str, mut out: Float) -> Int
       post result >= 0
   {
       ...   // 0 = ok, >0 = error code
   }
   ```

2. **Status + last-error accessor.** A library-scoped error slot read by a
   companion `@export` function.

3. **CPython-style shim (future).** A generated shim that maps `Result` to a
   Ruby exception. This is the long-term clean path, mirroring the Python
   binding story.

The bridge always surfaces the mapping in the generated Ruby signature, so a
caller cannot forget to check it.

## 6. Generated module shape

```ruby
# app/xz/bindings/order.rb (generated — do not edit)
module Xz::Bindings::Order
  extend RailsXz::Bridge::Facade

  # @cstruct Color { r: usize, g: usize, b: usize, a: usize }
  Color = Data.define(:r, :g, :b, :a)

  # @export payable_total(subtotal: Float, tax_rate: Float) -> Float
  payable_total(:double, :double) # => Float

  # @export parse_amount(text: Str, mut out: Float) -> Int
  # returns [status, out]; raises Xz::Bindings::Order::ParseError unless status.zero?
  parse_amount(:string, :out_float) # => Integer
end
```

## 7. GVL and threading

Native Xz code can block. The loader releases the GVL around a call whose
derived effect profile includes `io` (and for any call the developer marks
`release_gvl: true`), and keeps the GVL for `@effects none` calls. The effect
profile comes from the compiler, not from the function name. See
[ARCHITECTURE.md §4.1](../ARCHITECTURE.md).

## 8. Performance budget

FFI overhead target: **< 5%** over a direct C ABI call, excluding the body. This
rules out per-call `dlopen`, per-call marshalling of large buffers, and per-call
JSON. The benchmark suite in Phase 1 measures native Ruby vs. Xz FFI for a fixed
set of functions.

## 9. Open questions

- Should `--lang ruby` live in the Xz CLI or in `rails-xz-bridge`? (Current
  plan: the CLI, with the gem generator as a compatible fallback.)
- Zero-copy ownership rules for retained pointers need a contract syntax that
  `.xzint` cannot currently express.
- Should `Fiddle` or `ffi` be the default once `ffi` is widely available on the
  target Ruby versions?
