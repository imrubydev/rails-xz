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
- The generated header is an honest, complete description of the ABI, with one
  known gap: at the pinned compiler, `xz build --shared` does not lay out a
  by-value `@cstruct` larger than the register class per that header, so the
  bridge refuses such a crossing (§4.3). Everything else in this document
  assumes the header is authoritative.

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
                  lib/xz/bindings/order.rb
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

An `.xzint` opens with exactly one `@interface export|foreign` marker. The kind
decides the ownership rules (§4.6): an `@interface export` surface (the one
`xz build --shared` emits) borrows its parameters and retains its returns, so it
cannot declare `transfer` in either direction; an `@interface foreign` library
may take and hand back ownership. A file with no marker, or with more than one,
is rejected rather than guessed.

### 2.1 Generating from the compiler's header

When only the compiled artifact is available — a third-party shared library, or
an `@export` `.xz` built without an `.xzint` — the generator reads the C header
`xz build --shared` writes beside the library. The header is the compiler's own
description of the ABI (§1), so the generator maps its C types back to the same
type table (§6.1) instead of guessing a layout:

| C (header) | Xz |
|---|---|
| `bool` / `int64_t` / `uint64_t` / `double` / `char` | `Bool` / `Int` / `usize` / `Float` / `Char` |
| `XzStr` / `XzBytes` | `Str` / `Bytes` |
| `void*` | `Ptr` |
| `T*` (`void**` for `Ptr`) | `mut T` |
| `void` (return only) | no return |
| a `typedef struct` name | `@cstruct` |

The parser is chosen from the file name: a `.h` path is read as a generated
header, any other path as an `.xzint` interface. The `XzStr`/`XzBytes` carrier
typedefs, the include block, and the include guard are skipped. A C type outside
the table is a `HeaderError`, never a silent cast — the same no-degradation rule
as the `.xzint` path.

## 3. Loading the library

| Backend | Mechanism | Used for |
|---|---|---|
| `Fiddle` | Ruby stdlib `dlopen` + `Function` | Scalar- and pointer-only signatures; no native dependency. |
| `ffi` | `ffi` gem | Any signature that crosses a by-value aggregate or carries a `mut` parameter. |

Fiddle cannot pass or return a C struct by value, and the Xz ABI crosses `Str`,
`Bytes`, and `@cstruct` as structs (§1). A `mut` parameter also needs a typed
cell allocated in native memory. A signature is therefore bound through the
`ffi` gem the moment it contains one of those, so the `mut` cell can be allocated
and read back with ffi's typed memory; everything else stays on Fiddle. The
choice is per signature and is not a fallback: a by-value aggregate never
degrades to a pointer or a lossy cast.

`ffi` is a runtime dependency of `rails-xz-bridge`. Fiddle remains the backend
for the common scalar/pointer case so a binding that needs no aggregate carries
no native dependency beyond the gem itself.

The loader:

1. resolves the shared object path from the generated metadata,
2. verifies the Xz compiler version recorded in the metadata,
3. registers each symbol with its C signature (Fiddle) or ffi signature,
4. returns a typed facade.

A version mismatch raises `RailsXz::Bridge::VersionError`. A missing symbol
raises `RailsXz::Bridge::SymbolError`. Both are actionable, not silent.

## 4. Marshalling

### 4.1 Scalars

`Bool` → `true`/`false`, `Int`/`usize` → `Integer`, `Float` → `Float`,
`Char` → single-character `String`.

### 4.2 `Str` / `Bytes`

`Str` crosses as UTF-8 bytes into an `XzStr` struct; the binding encodes on call
and decodes on return. `Bytes` crosses as `String` with `Encoding::BINARY` and is
passed through without transcoding. A `Str`/`Bytes` return value is read from the
returned pointer/length pair and copied into a fresh Ruby String.

A return without `transfer` stays the library's buffer, so the binding copies it
and leaves it alone. A `transfer` return moves ownership to Ruby, so the binding
copies the value and then calls the named `release` symbol on the source buffer
(§4.6). A `mut Str`/`mut Bytes` cell that the callee repoints is the same problem
as a fresh transfer return; the copy-out value is read but the callee's new
buffer is not freed, which the release hook resolves only for a declared
`transfer` return.

### 4.3 `@cstruct`

Generated as a Ruby `Data` (immutable) or `Struct` with the same field order and
alignment. Nested `@cstruct` records nest as nested objects. The Ruby side never
reorders fields; the C layout is authoritative.

A `@cstruct` crosses by value: the binding builds the C struct from a `Data`
instance on call and reads a returned struct back into a `Data`. A `Str`,
`Bytes`, or `Ptr` field is marshalled by the same rules as a parameter, and a
nested `@cstruct` field nests by value.

#### By-value size limit on a compiler-built surface

The C ABI passes and returns a struct of at most two eightbytes (16 bytes) in
registers, and spills anything larger to memory. At the pinned compiler,
`xz build --shared` honors only the register path: for a larger by-value
`@cstruct` the emitted code does not match the header it writes, and a C caller
that includes the header reads garbage (verified with a C driver against the
header, not just through the bridge).

To refuse the same silent corruption, a binding generated from an
`xz build --shared` header (§2.1) is tagged `xz_abi :xz_shared`, and the ffi
marshaller raises `MarshallError` when such a binding would cross a by-value
`@cstruct` larger than 16 bytes, as a parameter or a return. A foreign `.xzint`
interface is left untagged and keeps the full range: a real C library lays its
structs out per the C ABI, so the guard does not apply to it. Until the compiler
is fixed, pass a large record through a `mut` pointer.

### 4.4 Handles

`Ptr` crosses as `RailsXz::Bridge::Handle`: a frozen, opaque wrapper around the
address, never a plain number. The binding rejects a bare Integer in a `Ptr`
position and a non-handle in a `@cstruct` field, so an address cannot be passed
by accident; `nil` is the one null form. `Handle` exposes `#to_i` and `#null?`
for interop.

`transfer` and handle lifetime land with the ownership slice (§4.6): a handle
from a `transfer` return owns its pointer and releases it with `#release!`, and
passing a handle to a `transfer` parameter consumes it, so it cannot be passed
or released again. A `Ptr` field inside a `@cstruct` is still copied with the
record; a handle transfer of a whole `@cstruct` is refused at generation.

### 4.5 `mut` cells

A `mut` parameter is the C in/out convention: it crosses as `T*`. The Ruby
caller passes the **initial value** positionally, and the binding:

1. allocates a typed cell for `T` in native memory,
2. writes the initial value into it,
3. passes the cell's address,
4. reads the callee's copy-out back into a Ruby value.

The updated values have to reach the caller without colliding with the function's
return. When a signature has at least one `mut` parameter, the generated method
returns a two-element array:

```ruby
status, out = parse_amount("1.50", 0.0)
status      # the Xz return value (e.g. a status code)
out         # => { out: 1.50 }  keyed by parameter name
```

When there is no `mut` parameter the method returns the Xz value directly. The
shape is decided by the signature alone, so the caller cannot forget to read an
out value. The mapping is per type: a scalar cell holds a scalar, `mut Str` /
`mut Bytes` / `mut @cstruct` / `mut Ptr` hold their by-value counterpart, and a
cell type outside the type table is a hard error.

### 4.6 Ownership (`transfer` / `release`)

A pointer that crosses the ABI has an owner. By default a parameter is
**borrowed** (the callee may read it only for the call) and a return is
**retained by the library** (Ruby must not free it). A `transfer` modifier moves
ownership in either direction, and it is legal only on an `@interface foreign`
(§2). The generated declaration carries the clauses straight from the `.xzint`:

```ruby
xz_func :strdup, { s: :str }, :str, release: :free
xz_func :write, { data: :bytes }, :int, transfer: [:data]
```

The runtime honors the two directions:

- **`transfer` parameter.** Ownership moves to the callee, which may retain the
  buffer past the call. For `Str`/`Bytes` the binding allocates the buffer from
  the C heap and copies the bytes into it, so it outlives Ruby's GC and the
  callee's own deallocator reclaims it; the binding never frees it. For `Ptr` the
  handle is consumed (`Handle#consume!`) and cannot be passed or released again.
- **`transfer` return.** The named `release <symbol>` is the library's
  deallocator (`func(ptr: Ptr) -> Unit`). For `Str`/`Bytes` the binding copies the
  buffer into a Ruby String and then calls the symbol on the source pointer, so
  the value is both safe and leak-free. For `Ptr` the binding returns a `Handle`
  that owns the pointer and exposes `#release!`, which calls the symbol exactly
  once; `nil`/zero and an already-consumed handle are no-ops, so a double free is
  impossible.

A signature the binding cannot honor is refused at generation time, never
degraded: `transfer` on an `@interface export`, a `transfer` of a scalar, a
`transfer` of a by-value `@cstruct`, a `transfer` return without a `release`
symbol, and a `release` whose symbol is not a `(Ptr) -> Unit` extern in the same
interface are all `GenerationError`s. A `mut Str`/`mut Bytes` cell that the
callee repoints still leaks the fresh buffer (there is no per-cell release
clause); declare such a function with a `transfer` return instead.

## 5. The `Result` problem

A C ABI export cannot carry a `Result`. Three sanctioned patterns, in order of
preference:

1. **Contracted wrapper (default).** Write a thin `@export` Xz function whose
   signature is C-representable and whose contract documents the mapping, e.g.
   an out-parameter `mut` status plus a value. The Ruby binding re-raises a typed
   error.

   ```xz
   /// @intent  Parses an amount; writes the value and returns a status code.
   /// @effects mut
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

The generator emits one Ruby module per interface, named after the source stem
(`libcurl.xzint` → `Xz::Bindings::Libcurl`). The module `extend`s
`RailsXz::Bridge::Facade` and declares the library, every `@cstruct`, and every
function. Declarations are emitted in dependency order: a record precedes any
record that nests it.

```ruby
# lib/xz/bindings/libcurl.rb (generated — do not edit)
require "rails-xz-bridge"

module Xz::Bindings::Libcurl
  extend RailsXz::Bridge::Facade

  xz_library "libcurl.so"

  # @cstruct curl_slist { data: Str, next: Ptr }
  xz_cstruct :curl_slist, { data: :str, next: :ptr }

  # extern func curl_easy_init() -> Ptr
  xz_func :curl_easy_init, {}, :ptr

  # extern func curl_easy_setopt(handle: Ptr, option: Int, param: Ptr) -> Int
  xz_func :curl_easy_setopt, { handle: :ptr, option: :int, param: :ptr }, :int
end
```

### 6.1 Type symbols

Every argument type is a symbol. A primitive keeps its lowercase name, a `mut`
parameter is prefixed `mut_`, and a `@cstruct` is its declared name.

| Xz | symbol | Ruby value |
|---|---|---|
| `Bool` | `:bool` | `true` / `false` |
| `Int` | `:int` | `Integer` |
| `usize` | `:usize` | `Integer` |
| `Float` | `:float` | `Float` |
| `Char` | `:char` | one-character `String` |
| `Str` | `:str` | `String` (UTF-8) |
| `Bytes` | `:bytes` | `String` (ASCII-8BIT) |
| `Ptr` | `:ptr` | opaque handle |
| `Unit` (return only) | `:unit` | `nil` |
| `@cstruct Color` | `:Color` | `Data` instance |
| `mut out: Float` | `:mut_float` | in/out cell (initial value in; updated value in the out hash, §4.5) |

### 6.2 `Facade` contract

- `xz_library(path)` records the shared object; the loader resolves it lazily on
  the first call.
- `xz_cstruct(name, fields)` defines a Ruby `Data` constant with matching field
  order. The C layout stays authoritative.
- `xz_func(name, params, returns, effects: nil, release_gvl: false, transfer: [], release: nil)`
  defines a positional Ruby method that marshals its arguments to the C ABI,
  calls the symbol, and returns the Xz value; with a `mut` parameter it returns
  `[value, out]` (§4.5). `effects` is the compiler-verified effect profile of an
  Xz `@export` function and drives the GVL policy (§7); `release_gvl: true`
  forces the GVL to be released for this call. `transfer` names the parameters
  whose ownership moves to the callee and `release` names the deallocator symbol
  of a `transfer` return (§4.6).
- A type the marshaller cannot represent is a `RailsXz::Bridge::MarshallError`,
  never a silent cast. Every type in the table above is marshalled; a type
  outside it (for example `mut Unit`) fails loudly.

## 7. GVL and threading

Native Xz code can block, and the effect profile from the compiler — not the
function name — is the source of truth for whether a call may hold the GVL. The
compiler proves the declared `@effects` equals the derived, transitive profile
(error `I0020`), so the bridge reads the `@effects` label from the `@export` `.xz`
source (`Interface::ExportSource`) and emits it on the generated declaration:

```ruby
xz_func :payable_total, { subtotal: :float, tax_rate: :float }, :float, effects: [:none]
xz_func :fetch, { url: :str }, :str, effects: [:io]
```

The policy at call time:

- **Keep the GVL** only when the profile is exactly `none` — the compiler proved
  the function pure and short.
- **Release the GVL** for every other profile (`mut`, `io`, `chan`, `extern`) and
  for an **unknown** profile: a third-party `.xzint` declares no effects, and an
  unproven call may block, so it must not stall the process.
- `release_gvl: true` forces release even for a pure function.

The mechanism is per backend: the Fiddle path passes `need_gvl: !release` to
`Fiddle::Function`, and the ffi path passes `blocking: release` to
`FFI::Function`. Both default to the safe release behavior for a call the bridge
does not know. See [ARCHITECTURE.md §4.1](../ARCHITECTURE.md).

## 8. Performance budget

FFI overhead target: **< 5%** over a direct C ABI call, excluding the body. This
rules out per-call `dlopen`, per-call marshalling of large buffers, and per-call
JSON. The benchmark suite in Phase 1 measures native Ruby vs. Xz FFI for a fixed
set of functions.

## 9. Open questions

- Should `--lang ruby` live in the Xz CLI or in `rails-xz-bridge`? (Current
  plan: the CLI, with the gem generator as a compatible fallback.)
- `transfer` ownership is supported, but the binding still copies a `Str`/`Bytes`
  transfer parameter into a callee-owned buffer rather than passing a Ruby buffer
  zero-copy; true zero-copy would need a `Bytes` owner that Ruby does not free. A
  `mut Str`/`mut Bytes` cell that the callee repoints has no release clause.
- `Fiddle` is the default for scalar/pointer signatures and `ffi` is required for
  by-value aggregates (§3); the open question is whether to move the whole
  runtime to `ffi` once it is available on every target Ruby version.
