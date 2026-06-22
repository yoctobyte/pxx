# `var`/`out` open-array param: fixed-array argument passes a wrong length

- **Type:** bug (codegen / open-array ABI)
- **Status:** DONE — 2026-06-22. Simple-var and static-array-FIELD arguments both
  fixed (copy-in / copy-out).
- **Owner:** — (Track A)
- **Opened:** 2026-06-22
- **Closed:** 2026-06-22
- **Found-by:** Synapse recon (`synacode.pas` `ArrByteToLong(var ArByte: array of
  byte; var ArLong: array of Integer)`). Independent of the capital-`array`
  keyword fix (b5c0252) that first unblocked that line.

## Symptom

Passing a **fixed** array to a **`var` (or `out`) open-array** parameter passes
the data pointer correctly but the implicit high/length is wrong (`High(a)` =
**-1**, i.e. length 0). The element data is reachable (`a[0]` reads correctly),
so only the length companion is broken.

- `value` open-array param (no `var`): **works** (correct High).
- `var` open-array param, **dynamic-array** argument: **works** (the dyn handle
  carries its own length).
- `var` open-array param, **fixed-array** argument: **BROKEN** — High = -1.
- Element type irrelevant (Byte and Integer both fail).

## Minimal repro

```pascal
program p;
procedure S(var a: array of Integer; var h: Integer);
begin h := High(a); end;
var f: array[0..2] of Integer; h: Integer;
begin S(f, h); WriteLn(h); end.   { prints -1; expected 2 }
```

`x := a[0]` in the same shape returns the right element, so the data pointer is
fine; only the length is lost.

## Likely cause

An open-array parameter is a fat argument (data pointer + high). For a `value`
open-array the caller materialises both correctly; for a **`var`** open-array
the by-reference path appears to pass the data address but drop / zero the
implicit high when the source is a fixed array (a dynamic source recovers it
from its handle, which is why dyn works). Look at the call-site open-array
marshalling for `pbyref[i] and parr[i]` (param loop ~parser.inc 9817/9842 sets
`parr`/`pbyref`) and how the High companion is computed for a fixed-array
lvalue argument vs a dynamic one. Compare the working value-param path.

## Why it matters

Blocks any FPC/Synapse routine taking `var X: array of T` and calling
`Length`/`High` on it — `synacode.ArrByteToLong` is the concrete case, so this
is on the Synapse compile path ([[feature-synapse-compile-check]]).

## Gate

`make test` (self-host byte-identical) + `make cross-bootstrap`. Add a test
(extend `test/test_keyword_array_case.pas` or a new one) covering fixed-array →
`var array of T` High/Length once fixed.

## Fix log

- 2026-06-22 — **simple-var case FIXED** (copy-in / copy-out). When a static
  array variable (`AN_IDENT`, `ArrLen >= 0`, not a param) is passed to a
  `var`/`out` open-array parameter, IRLowerCallArg now copies it into a header'd
  dyn temp (so `[data-8]` length + indexing work over the param), and the AN_CALL
  lowering emits a post-call copy-OUT (temp data -> static array) so the callee's
  writes propagate back. Nested-call-safe via a small pending stack
  (`PendOAWB*`, defs.inc) saved/restored around each call's arg lowering. A
  function result is spilled to a temp across the writeback (the COPY_REC would
  clobber rax/xmm0). All target-independent IR (IR_COPY_REC / IR_LEA / SetLength
  -102), so it works on every backend; the compiler's own source never hits the
  path, so self-host + cross-bootstrap stay byte-identical. Test
  `test/test_var_open_array.pas` (read via `High` + writeback), FPC objfpc
  oracle-matched (`6` / `0 10 20 30 `).
  **REMAINING:** static-array **FIELD** argument (`obj.field` whose field is a
  static array) — synacode's exact case (`MDContext.BufAnsiChar`,
  `MDContext.BufLong`). Needs a field-arrlen lookup (no `RecFieldArrLen` helper
  yet) + `IRLowerAddress(argAST)` for both the copy-in source and copy-out dest,
  generalising the `AN_IDENT` branch to `AN_FIELD`. Separately, `Length`/`High`
  on a static array used DIRECTLY (not via a param) is also wrong — filed as
  [[bug-static-array-length-direct]].

- 2026-06-22 — **FIELD case DONE.** Generalised the copy-in/out branch from
  `AN_IDENT` to `AN_FIELD`: a static-array record/class field passed to a
  `var`/`out` open-array param is copied into a header'd dyn temp and copied back
  after the call. The copy keys off the argument's ADDRESS (`IRLowerAddress`,
  works for var and field alike); the copy-out destination is the arg AST node,
  re-lowered at flush time. New helpers `RecFieldArrLen` / `RecFieldArrNDims`
  (symtab.inc) read the field's static length / dim count; dynamic-array fields
  (`RecFieldDynDepth > 0`) and multi-dim keep the native/runtime path. Test
  `test/test_var_open_array_field.pas` (synacode MD5 shape: read `BufByte` field,
  write `BufLong` field), FPC objfpc oracle-matched (256 / 1284). make test +
  cross-bootstrap byte-identical. This is synacode's exact construct — the
  Synapse compile path no longer trips on it (next there is `Move`/`FillChar`,
  Track B).
