# Not Stable

Implemented but unfinished. These work for tested cases but may change, have
sharp edges, or break outside covered paths.

## Naming

- `PXX` is provisional; the binary is still `compiler/pascal26`. CLI names,
  modes, and dialect extras are early interfaces and may be revised.

## Floating point

- `Single`/`Double`/`Real`/`Extended` arithmetic works. `Write`/`WriteLn`
  formatting differs slightly from FPC: scientific form uses
  `d.<15 digits>E±ddd` and last digits may differ.

## Managed strings

- `AnsiString` uses the heap-backed, refcounted representation by default
  (assignment cleanup, copy-on-write, concat, `SetLength`, globals, records,
  classes, and exception unwinding are covered by current regression tests).
  `-uPXX_MANAGED_STRING` selects the frozen fixed-capacity inline ABI for
  bootstrap compatibility. Refcounts are atomic only under `--threadsafe`.

## C structs / headers

- POD structs lay out as records (scalars, pointers, fixed arrays, nested
  structs, top-level unions). Bitfields, anonymous/nested struct-union defs, and
  tag-typed fields fall back to an opaque pointer (never silently wrong).
- Very large macro-soup headers (GTK) can exhaust record tables and fall back to
  opaque; header lookup is a linear scan, so huge headers parse slowly.
- Library-name resolution maps known names to sonames; unmapped names default to
  `lib<name>.so` with no loader-cache probe.

## Nil Python (`.npy`)

- v1 caps: ≤4 parameters, `//` for integer division (`/` errors), `for` step
  must be 1, param/result annotations required. No source-level pointer syntax;
  imported C handles can be held/passed and trailing `T**` out-params can be
  return-lifted.

## BASIC

- Early frontend only; experimental, not part of `make test`.
