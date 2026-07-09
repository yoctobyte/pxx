---
prio: 55
---

# duktape: runtime segfault in first JS eval — pointer truncated to 32 bits

- **Type:** bug (runtime — C frontend **codegen**) — **Track A/C**.
- **Status:** backlog — found 2026-07-09; **root-caused to a 32-bit pointer truncation**
  2026-07-09 (deep gdb/objdump session). NOT setjmp, NOT crtl.
- **Blocks:** [[feature-c-corpus-duktape]] (compiles + links + heap-inits; can't run the
  JS test-suite until this is fixed).

## TL;DR (verified root cause)
A **64-bit pointer is truncated to 32 bits and sign-extended** somewhere in duktape's
JS-compiler value-stack / `duk_tval` handling. The wrong value (`0xffffffffe7e0d570`,
i.e. `(int)0x00007fffe7e0d570` sign-extended) is later dereferenced → SIGSEGV. gcc
compiles + runs the identical source correctly, so it is a **pxx codegen bug**, not the
engine or crtl. Every *isolated* reproduction attempt compiles correctly — the trigger
is context-dependent and NOT yet minimized.

## What was ruled OUT (don't re-investigate)
- **setjmp/longjmp**: `duk_safe_call(ctx, noop, ...)` returns rc=0 — the protected-call
  machinery works. The x86-64 setjmp/longjmp stubs (cparser.inc EmitCSetjmpStubs) are
  correct (save/restore rbx/rbp/r12-r15/rsp/retaddr).
- **crtl gaps**: heap creation + a no-op safe_call succeed; the crash is in
  `duk_pcompile_string` (JS compiler), even for the empty program `""`.
- **duk_tval layout**: pxx computes `sizeof(duk_tval)=16`, `offsetof(v)=8`, pointer
  members = 8 bytes, and `tv->v.heaphdr` load/store, `*dst=*src` 16-byte copy, function
  pointers in the union — ALL correct in isolation (tested against gcc).
- **Fixed-table overflow (the all-in-RAM caps)**: instrumented — duktape does NOT hit
  MAX_UCLASS (peak < 1900 of 2048), MAX_UFIELD, the CTag/CTypedef pools, nor the
  opaque-struct fallback (0 structs went opaque, 0 cap degradations). So it is NOT the
  [[feature-c-compiler-dynarrays]] class.
- **Isolated reproductions that ALL compile+run correctly under pxx** (do not retry):
  comma expression yielding a pointer `(assert, tv->v.hobject)`; the FULL
  `DUK_GET_HOBJECT_POSIDX` chain `(assert, ((duk_hthread*)thr)->valstack_bottom + idx)->v.hobject`
  assigned to a `duk_compiler_func` pointer field; `duk_tval_decref` + valstack loop;
  indexed `arr[i].v.member`; pointer-returning functions; incomplete/forward-declared
  pointee types. **The trigger requires duktape's full accumulated type context** — some
  earlier type definition in the 100k-line TU perturbs the resolution of this one access.

## Likely vicinity
`duk__init_func_valstack_slots` (duktape.c ~69716), run first thing in
`duk_pcompile_string`: it does `func->h_consts = DUK_GET_HOBJECT_POSIDX(thr, entry_top+1)`
(and h_funcs/h_decls/…) — a `duk_hobject *` from the value stack stored into a
`duk_compiler_func` pointer field. The corrupted value later drives a
`duk_heaphdr_decref`-shaped helper (reads `h->h_refcount` at offset 0) → the crash.

## Evidence (the smoking gun)
gdb on the `-g` build (`duk_split.c` minimal: heap → safe_call(rc=0) → pcompile "1" → crash):
- Crash PC derefs `%rax = 0xffffffffe7e0d570` (`mov (%rax),%eax`).
- The value came from a **`movslq` (32-bit sign-extending load)** at the caller
  (`0x599cc8`): `base->[0x18]` (the value stack `duk_tval *`) `+ index*0x10` `+ 0`, loaded
  4 bytes signed, passed as the pointer arg to a heaphdr helper (looks like
  `duk_heaphdr_decref`, inlined in gcc).
- The value-stack slot in memory holds `0x00000000e7e0d570` — high 32 bits **zero**, so
  the pointer was also **truncated on STORE** (4-byte write). So pxx is treating this
  pointer as a **4-byte field at offset 0** (should be an 8-byte load at offset 8 for
  `tv->v.heaphdr`, or the stored pointer's origin is truncated upstream).
- Net: both the store and the load of this pointer are 32-bit. Classic
  `int`-vs-`pointer` width mistake in codegen for one specific access.

## Where to dig next (fresh session)
The bug does NOT reproduce in isolation, so the two productive attacks are:

1. **IR-level codegen instrumentation (most direct).** The truncation is a 4-byte store +
   `movslq` (sign-extending 32-bit) load of a value whose type is a pointer. Instrument the
   C→IR lowering / ir_codegen_x64 field-access path to log, during the duktape compile,
   every field load/store where the resolved element type is 4 bytes but the field's source
   type is a pointer (or: every `movslq` emitted for a pointer-typed access). Grep the log
   for the value-stack/`h_consts` access → the exact mis-typed field, then fix the type
   resolution.

2. **Type-definition bisection.** Since isolated repros of the access all pass, an EARLIER
   type definition in the full TU corrupts this one's resolution. Build a reduced TU: the
   faithful `DUK_GET_HOBJECT_POSIDX`/`duk__init_func_valstack_slots` repro (already OK on
   its own) + progressively more of duktape's real type definitions prepended, until the
   pointer truncates. The type that flips it is the culprit (candidate: a struct/typedef
   that shares a name or aliases `duk_tval`/`duk_hobject`/`v`, mis-registering the field
   table; or a type whose registration mis-sizes a shared record entry).

Line-mapping caveat: the pxx binary has no symbol table, and its `-g` DWARF flattens the
unity into `duk_split.c` line numbers (offset ~8k vs duktape.c physical, non-linear because
#if-removed blocks collapse — calibration unreliable). Use the **gcc** oracle (full symbols)
to name functions; use pxx only for the codegen log.

## Symptom
The duktape amalgamation now compiles, links (libc-free crtl), and creates a heap:

```
heap ok            <- duk_create_heap_default() succeeds
Segmentation fault  <- during duk_peval_string(ctx, "1+2")
```

Minimal repro: crtl unity + `duktape.c` + a main that does
`duk_create_heap_default()` (prints "heap ok"), then `duk_peval_string(ctx,"1+2")`
→ SIGSEGV. So heap construction is fine; the crash is on the first protected
compile/execute of JS.

## Landmines
Same as the corpus arc (comment-brace self-host, no ErrOutput in byte-identical build,
stabilize→pin verify). Reproductions that FAILED to trigger (all compiled correctly under
pxx — don't repeat): standalone `duk_tval` layout/offsetof, `tv->v.heaphdr` read+write,
`arr[i].v.member`, `*dst=*src` 16-byte struct copy, function pointers in the union, a
faithful `duk_tval_decref` + valstack loop. The trigger needs duktape's full type context.

[[feature-c-corpus-duktape]] · [[project_c_stdio_pal_bridge_done]] · [[project_record_array_copy_codegen_bug]]
