# Can't pass a function-result temporary to a const/by-ref record param

- **Type:** bug (compiler)
- **Status:** backlog
- **Owner:** — (track A)
- **Opened:** 2026-06-19 (track B, building lib/rtl/bignum)

## Symptom

Passing a function-result temporary (rather than a named variable) to a `const`
record parameter is rejected:

```pascal
p := BigAdd(BigFromInt(999999999), BigFromInt(2));
              ^ pascal26: error: by-reference argument must be a variable ()
```

Works when the arguments are variables:

```pascal
x := BigFromInt(999999999); y := BigFromInt(2);
p := BigAdd(x, y);              { ok }
```

`const` record params are passed by reference, and the compiler will only bind a
real lvalue, not a temporary. (FPC accepts a temporary for a `const` param.)

## Impact

Forces intermediate variables for every nested call over record-typed values —
ergonomic wart for any value-style API (bignum, JSON nodes, vectors, etc.).
Nesting `f(g(x), h(y))` is the natural style and currently illegal for records.

## Direction

For `const` (and by-value) record params, materialize a function-result
temporary into a hidden local and pass its address — i.e. allow temporaries to
bind to `const`-by-ref params, as FPC does. (Plain `var` params should still
require a true variable.)

## Log
- 2026-06-19 — opened by track B from the bignum lib; worked around with named
  locals in the test, but the lib's public API still forces that on callers.

## Re-verify on v10 (2026-06-19)

Last seen against pinned **v9 mid-WIP**. Track A pinned **v10** (`93ad58a`) —
freshly stabilized, binary+builtin coherent (the v9 era had the
bug-pinned-stable-reads-live-builtin mix). **Before bisecting, reproduce against
v10**: the crash may have been a WIP artifact and already be gone. If gone,
close; if it reproduces, bisect on the clean compiler.

## Resolution (2026-06-19) — FIXED

Reproduced on v10, then fixed. The codegen (`IRLowerCallArg`, ir.inc ~973-1008)
already materializes a non-lvalue record argument into a hidden local and passes
its address when the param is by-ref (the `needTemp` path) — the only thing
blocking the temp was a parse-time check that rejected any non-IDENT/INDEX/FIELD
arg to a by-ref param.

Fix: persist whether each param was declared `const` (new parallel array
`ProcParamIsConst[pi*16+i]`, mirroring `ProcParamRecId` — param sym slots are
reused across procs so it can't live on the sym), and relax the two AST-path
call-arg checks (parser.inc ~3328 and ~5862) to allow a **record temporary** for
a `const` param. `var`/`out` params still require a true lvalue (write-back), and
the legacy `--legacy-codegen` ParseCallArg path is unchanged.

Validated: direct/nested/mixed temp args (`AddR(MakeR(40), MakeR(2))`,
`AddR(AddR(...), AddR(...))`) all correct; `var` param still errors on a temp;
self-host + threadsafe fixedpoint byte-identical; `make cross-bootstrap` all 4
byte-identical. Tests: `test/test_const_record_temp.pas` (plain record, in
test-core + i386/aarch64/arm32 cross suites) and
`test/test_const_record_temp_managed.pas` (bignum-shape managed record, x86-64
test-core only).

NOTE: writing the managed-record cross test surfaced a **separate pre-existing**
crash — passing a `const` record *with a managed (dynarray) field* by-ref
segfaults on i386 + aarch64 (arm32 + x86-64 fine), independent of temporaries.
Filed as `bug-const-managed-record-param-byref-crash`.
