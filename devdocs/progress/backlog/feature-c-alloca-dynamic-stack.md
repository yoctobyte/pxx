---
prio: 55
---

# alloca(): dynamic stack allocation for the C frontend

- **Type:** feature (IR/codegen — dynamic frame) — **Track A** (needs an IR-level
  dynamic-stack op the backends lower; the cfront call-site recognition is the
  trivial part)
- **Status:** backlog
- **Opened:** 2026-07-12, the third wall of the QuickJS bring-up
  ([[feature-c-corpus-quickjs]]).

## Symptom

```
pascal26:15175: error: call to undeclared function: alloca ()
```

QuickJS uses `alloca` on its hottest paths — `JS_CallInternal` allocates the
argument buffer and local frame with it (quickjs.c:5288, 14707, 14818, 14970),
and libregexp sizes its capture stack with it (libregexp.c:2484). A
malloc-backed shim is NOT acceptable here: every JS call would leak its frame.

## Shape

- `alloca(n)` = allocate n bytes in the CALLER's stack frame, freed on function
  return. gcc lowers it to a `sub rsp, n` (aligned) + pointer to the hole.
- PXX frames are fixed-size today (locals laid out at compile time), so this
  needs: an IR op (`IR_ALLOCA size -> ptr`), codegen that adjusts rsp/sp
  dynamically, and epilogues that restore via frame pointer rather than
  pop-count (x86-64 uses rbp-based epilogue already? verify per backend).
  Restrict to x86-64 first (QuickJS runs hosted); other backends can error
  cleanly until ported.
- cfront: recognize `alloca`/`__builtin_alloca` calls and emit the op (mirror
  the `__builtin_clz` rename spot in cparser.inc, but as a real lowering).
- Interaction warnings: register allocator / -O passes must treat a function
  containing alloca conservatively (no frame-offset caching across it);
  longjmp/setjmp paths in the same function.

## Acceptance

- A C test: variable-size alloca in a loop-called function keeps a stable
  frame (no leak, no clobber), values survive, gcc-oracle parity.
- QuickJS compiles past its alloca sites (the bring-up's next wall becomes
  visible).
- Self-host byte-identical + cross gates green (op unused by Pascal paths).
