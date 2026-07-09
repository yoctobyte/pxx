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
1. **Identify the exact function/access.** No symbols in the pxx binary and its `-g`
   line table flattens everything into `duk_split.c` line numbers (offset ~8k vs
   duktape.c physical, non-linear because #if-removed blocks collapse — calibration is
   unreliable). Better: build the **gcc** oracle with `-g` and break at the value-stack
   pop/decref during `duk_pcompile_string(ctx,"1")` to name the caller chain
   (`duk_heaphdr_decref` is `DUK_ALWAYS_INLINE` — break its callers: `duk_tval_decref` /
   the `duk_set_top` / valstack unwind path). Then read that exact C access and see which
   `tv->v.<member>` / pointer expression pxx lowers to a 4-byte offset-0 load.
2. **Instrument pxx codegen.** Add a temporary log in the C field-access / load-width path
   (the code that chose `movslq`/4-byte for this field) and compile duktape — print the
   field name/type whenever a union pointer-member resolves to a 4-byte or offset-0 load.
   That pinpoints the mis-resolution directly.
3. **Suspected class:** union member resolution where `duk_tval.v` has both a
   `duk_small_int_t i` (4-byte signed) member and pointer members — pxx may pick the wrong
   member type/offset only under duktape's full type context (all isolated repros with the
   same union picked the right member). Also check pointer-returning functions whose return
   type pxx might resolve to `int` (would truncate the stored pointer at its origin).

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
