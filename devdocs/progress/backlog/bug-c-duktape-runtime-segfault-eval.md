---
prio: 55
---

# duktape: runtime segfault in first JS eval (heap init OK)

- **Type:** bug (runtime — C frontend codegen or crtl) — **Track A/C**.
- **Status:** backlog — found 2026-07-09 once pxx compiled duktape 2.7.0 end-to-end.
- **Blocks:** [[feature-c-corpus-duktape]] (compiles + links + heap-inits; can't run the
  JS test-suite until this is fixed).

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

## Prime suspect: setjmp/longjmp protected calls
duktape wraps every eval/call in a `setjmp` catchpoint (`DUK_SETJMP`/`DUK_LONGJMP`
→ crtl's `_setjmp`/`_longjmp`, the tcc-arc shim `__pxx_setjmp`/`__pxx_longjmp`,
`jmp_buf = struct { long __jb[16]; }`). `duk_peval_string` always sets a
setjmp catchpoint and drives the bytecode compiler under it. If the shim does not
save/restore the exact callee-saved register + stack state duktape relies on
(it longjmps out of deeply nested calls on the normal path, not just errors), the
first protected call corrupts control flow → segfault. This is the first thing to
verify: does the crtl setjmp/longjmp shim round-trip a non-trivial nested call on
x86-64? (It passed tcc's simpler usage.)

Secondary suspects if setjmp checks out: a pxx codegen bug on some construct only
duktape's VM exercises (computed dispatch is avoided — duktape's default is a plain
`switch` bytecode loop, no `&&label`), or a crtl gap (malloc alignment for
duktape's 8-byte-aligned tagged values, `memcpy`/`memmove` overlap, etc.).

## How to attack
- Build the same unity with **gcc** (oracle) — it should run the smoke green; confirms
  the bug is pxx/crtl, not the engine or the harness.
- Bisect duktape features: `duk_peval_string` with `""`/`"1"`/`"1+2"`; if even the
  empty program crashes, it's the protected-call frame (setjmp), not expression codegen.
- Instrument `__pxx_setjmp`/`__pxx_longjmp` (lib/rtl PAL) — dump saved SP/return addr;
  verify longjmp restores them. Compare a tiny hand-written setjmp/longjmp nest under
  pxx vs gcc.
- If setjmp is fine, `-O0` vs default and bisect the VM dispatch function.

## Landmines
Same as the corpus arc (comment-brace self-host, no ErrOutput in byte-identical build,
stabilize→pin verify). The setjmp shim is shared crtl/PAL — a fix there is Track A/B and
must keep tcc + sqlite (which also use setjmp) green.

[[feature-c-corpus-duktape]] · [[project_c_stdio_pal_bridge_done]]
