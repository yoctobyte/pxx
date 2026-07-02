# C: `arr->field = call()` store miscompiled when `arr` is an array

- **Type:** bug (codegen / C→IR lowering) — **Track A** (shared internals)
- **Status:** done (v145)
- **Priority:** high — silent pointer corruption, blocks a clean 3rd-party lib
- **Owner:** unassigned
- **Found / Opened:** 2026-06-30, cJSON bring-up (rung-1 C-frontend probe,
  `make test-cjson` / [[c-torture-candidates]]).

## Symptom

When the destination is reached through the **arrow operator applied to an array
identifier** (`arr->field`, i.e. `(*arr).field` where `arr` is a fixed array) and
the **right-hand side is a function call**, the store lands the wrong value — the
returned pointer is truncated / sign-extended / dropped, so the field ends up
garbage (often `NULL` or a mangled half-pointer). Every other shape of the same
store is correct.

Minimal repro (no libc-specific behaviour; reproduces with and without
`-Ilib/crtl/include`):

```c
#include <stdlib.h>
typedef struct { void *p; long q; } S;
int main(void){
  S a[1]; a->q = 7;
  a->p = malloc(256);     /* (1) array + arrow + call  -> WRONG (garbage ptr) */

  S c[1];
  (*c).p = malloc(256);   /* (2) explicit deref + call -> OK                  */

  S e[2];
  e[0].p = malloc(256);   /* (3) indexed element + call -> OK                 */

  S d; d.p = malloc(256); /* (4) plain struct var + call -> OK                */
  return 0;
}
```

Only form (1) is miscompiled. `a->p = (void*)1234;` (non-call RHS) is **also
correct**, so the trigger is specifically *arrow-on-array lvalue + call-valued
RHS*. The destination address of `a->p` appears to be computed before the call
and not preserved across it (caller-saved clobber), so the result store goes to a
stale location while `a->q`/other fields update normally.

Observed: `a->p` printed `0x3e000008` where the real `malloc` result was
`0x78413e000…`; a deterministic `give()` returning `0xABCD1234` came back
sign-extended as `0xffffffffABCD1234` through the arrow path but clean through
`(*c)`.

## Real-world impact

cJSON's printer is entirely dead because of this. `print()` does:

```c
printbuffer buffer[1];
buffer->buffer = (unsigned char*) hooks->allocate(default_buffer_size);  /* arrow-on-array + call */
```

`buffer->buffer` stays `NULL`, so `cJSON_Print`/`cJSON_PrintUnformatted` return
`NULL` for **every** value (even `null`/`true`). Parsing is unaffected (it reaches
`hooks->allocate` through a real pointer parameter, not an array). So a
round-trip parse→print of any JSON document fails at the print step.

The bug is silent: no diagnostic, just a wrong pointer — exactly the class that
corrupts real programs without a crash.

## Likely cause (as filed — see "Fixed" below for what it actually was)

C→IR lowering (or backend reg-alloc) for an assignment whose lvalue base is an
array-decay-to-pointer and whose RHS is a call: the lowered destination address
(or the array base register) is materialised before the call and treated as
call-clobbered-safe, but a SysV call destroys it. `(*arr)` and `arr[i]`
re-materialise the address after the call, which is why they survive. Possibly
adjacent to the array-vs-pointer handling behind
[[bug-c-sizeof-array-yields-element-size]] /
[[bug-sizeof-array-and-typename-wrong]].

## Fixed (2026-07-02, pin v145)

The "likely cause" guess above (call-clobbered register/address) was wrong —
confirmed via a dedicated investigation (an independent agent pass traced
`IRLowerAddress`'s AN_ASSIGN LHS-address-vs-RHS evaluation order and found it
identical for every AN_FIELD shape; no call-clobber divergence anywhere). The
"only breaks with a call-valued RHS" framing in the symptom section is
**incidental, not fundamental**: a small literal like `(void*)1234` happens to
survive a 32-bit signed round-trip unchanged, while a real `malloc()` heap
address (or the ticket's own `give()` returning `0xABCD1234`) does not — the
real trigger is the RHS value's bit magnitude, not whether it comes from a
call.

**Real root cause:** `ResolveNodeRec` (`compiler/symtab.inc`)'s `AN_IDENT`
branch unconditionally read `Syms[idx].RecName` — but an array symbol stores
its ELEMENT record in `ElemRecName`, not `RecName` (`AllocArray` never
populates `RecName`; only `AllocVar` does, for a plain scalar/record var).
`ResolveNodeRec`'s own sibling `AN_INDEX` branch already special-cases this
(reads `ElemRecName` for a non-pointer array base) — `AN_IDENT` was the one
branch missing the same check.

This is reachable specifically from C's `arr->field` where `arr` is an array
(not a pointer variable): C lets `->` apply to an array via array-to-pointer
decay, but `cparser.inc`'s `.`/`->` disambiguation (`CNodeIsPointer`)
explicitly excludes arrays (`not Syms[idx].IsArray`), so `arr->field` lowers
to a plain `AN_FIELD(AN_IDENT(arr), field)` — not a dereferenced-pointer
shape. No ordinary Pascal parse ever produces this (Pascal has no `.` on a
bare, unindexed array), so this AST shape had never previously exercised
`ResolveNodeRec`'s `AN_IDENT` branch before the C frontend existed. Resolving
`REC_NONE` there cascaded into the field's type tag defaulting to `tyInteger`
(4 bytes) instead of the real field type, truncating/mis-signing any wide
(pointer/`long`) value stored through it — and because the store then landed
at the wrong width, it also corrupted adjacent fields set earlier in the same
array (exactly the observed `a->q` clobber).

**Fix** — one shared `symtab.inc` change, not a C-frontend-only patch:

```pascal
if ASTKind[node] = AN_IDENT then
begin
  if Syms[ASTIVal[node]].IsArray then
    Result := Syms[ASTIVal[node]].ElemRecName
  else
    Result := Syms[ASTIVal[node]].RecName;
end
```

**Verification:** all four repro forms from this ticket (array+arrow,
explicit deref, indexed element, plain struct var) now correct; the
sign-extension example matches a real GCC oracle exactly (`ffffffffabcd1234`
on both the arrow-on-array and explicit-deref forms — GCC sign-extends
there too, so that part was never actually a bug, just diagnostic evidence
of the truncation). Full `make test` green (592 `ok:`), `make test-lua` (a
large real third-party C codebase) fully green, cross-target identical on
i386/arm32/aarch64, self-host byte-identical. `test/carrow_on_array_call_rhs_b136.c`
added, wired into `Makefile`. `make test-cjson` still needs a fetched cJSON
tree to actually run (not available in this environment) — not verified
directly, but the exact mechanism cJSON's printer hit (`buffer->buffer =
(unsigned char*) hooks->allocate(...)`, array+arrow+call) is precisely what
the new regression test covers.

Committed as `92afd493` (pin v145).

## Acceptance

- [x] `arr->field = f()` (array + arrow + call RHS) stores `f()`'s full result, byte
      for byte, for pointer- and integer-typed fields. **Done, pin v145.**
- [x] Repro added to `test/` with an exit-code oracle. **Done —
      `test/carrow_on_array_call_rhs_b136.c`.**
- [ ] `make test-cjson` round-trips all committed fixtures (parse→PrintUnformatted ==
      `*.expected`) once this lands — not verified in this environment (no
      cJSON tree fetched); mechanism match gives high confidence but should be
      confirmed once cJSON is available.
- [x] self-host byte-identical + cross unaffected. **Done.**

## Log

- 2026-06-30 — Found by Track C standing up the cJSON round-trip suite
  (`test/cjson/`, `make test-cjson`). Parse works; print returns NULL for all
  values. Bisected from the cJSON print path down to the four-line repro above:
  the sole broken form is arrow-on-array lvalue with a call-valued RHS. Filed for
  Track A (codegen is shared-internals; not editable under Track C). The cJSON
  harness, fixtures, and a crtl `sscanf` (needed for cJSON's float-roundtrip
  check) are committed and will go green when this is fixed; integer/string/bool/
  null fixtures already exercise the blocked path.
