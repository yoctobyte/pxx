# Types

Standard Object Pascal types behave as in FPC. This page covers the ones with
PXX-specific behaviour or limits.

## Ordinals & reals

`Integer`, `LongInt`, `LongWord`, `Int64`, `Boolean`, `Char`, enums, subranges,
and `Single`/`Double`/`Real`/`Extended` are supported. Integer arithmetic
**wraps unchecked** — there is no overflow or range checking. Cast intrinsics
(`Trunc`/`Round`/…) are not implemented; `WideChar` is not supported.

Float `Write`/`WriteLn` formatting differs slightly from FPC (scientific form is
`d.<15 digits>E±ddd`, last digits may vary).

## Strings

Two ABIs, selected at compile time by the `PXX_MANAGED_STRING` symbol, which is
**defined by default**:

- **Managed `AnsiString`** (default): heap-backed, reference-counted, copy-on-
  write. Assignment cleanup, concat, `SetLength`, globals, record/class fields,
  and exception-unwind release are covered by the regression suite. Refcounts are
  atomic only under `--threadsafe`.
- **Frozen string** (`-uPXX_MANAGED_STRING`): a fixed-capacity inline buffer, no
  heap, no refcount. Used for bootstrap/compatibility and on paths where a heap
  string is undesirable.

`Char` literals and `Char` values coerce to strings where expected.

## Typed pointers

`^T`, `@x`, `p^`, pointer arithmetic, and `nil` work. `PChar`-style access and
auto `string → const char*` marshalling exist for C interop (see
[`developer/c-interop.md`](../developer/c-interop.md)). Pointer-to-machine-word
must be `^NativeInt`, not `^Int64`, for code that must also run on 32-bit targets
(an `^Int64` write is 8 bytes and overruns a 4-byte slot).

## Dynamic arrays

`array of T` with `Length`/`SetLength`, copy-on-write, comma sugar `m[i, j]` for
nested arrays, and scope-exit cleanup — as locals and as record/class fields.
Multi-dimensional (`array of array of …`) is supported. Element types may
themselves be managed (strings, records with managed fields).

## Static arrays

`array[lo..hi] of T`, including multi-dimensional and named array types. A static
array passed to an `array of T` parameter is copied to a dyn-array header so
`Length()`/indexing work uniformly.

## Sets

`set of` over ordinals and subranges, with the usual operators and `in`. Backed
by a 32-byte bitset.

## Records

Fields, nested records, methods, managed fields (with correct zero-init and
whole-record ARC copy). **By-value record parameters larger than one machine word
are truncated** — pass big records as `const` (which passes by reference).

## Variants

`Variant` holds ordinals, floats, strings, and `array of const` elements
(`TVarRec`). Returning a 16-byte `Variant` *by value* truncates to 8 bytes;
that path is deferred.

## `array of const`

Open `array of const` lowers to a `TVarRec` array; element types Bool/Char/
Pointer/Int64/Double/AnsiString are handled. This drives variadic-style
`Format`-like routines.
