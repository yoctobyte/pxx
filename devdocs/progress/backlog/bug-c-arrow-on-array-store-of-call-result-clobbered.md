# C: `arr->field = call()` store miscompiled when `arr` is an array

- **Type:** bug (codegen / C→IR lowering) — **Track A** (shared internals)
- **Status:** OPEN (filed by Track C)
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

## Likely cause

C→IR lowering (or backend reg-alloc) for an assignment whose lvalue base is an
array-decay-to-pointer and whose RHS is a call: the lowered destination address
(or the array base register) is materialised before the call and treated as
call-clobbered-safe, but a SysV call destroys it. `(*arr)` and `arr[i]`
re-materialise the address after the call, which is why they survive. Possibly
adjacent to the array-vs-pointer handling behind
[[bug-c-sizeof-array-yields-element-size]] /
[[bug-sizeof-array-and-typename-wrong]].

## Acceptance

- `arr->field = f()` (array + arrow + call RHS) stores `f()`'s full result, byte
  for byte, for pointer- and integer-typed fields.
- Repro added to `test/` with an exit-code oracle.
- `make test-cjson` round-trips all committed fixtures (parse→PrintUnformatted ==
  `*.expected`) once this lands.
- self-host byte-identical + cross unaffected.

## Log

- 2026-06-30 — Found by Track C standing up the cJSON round-trip suite
  (`test/cjson/`, `make test-cjson`). Parse works; print returns NULL for all
  values. Bisected from the cJSON print path down to the four-line repro above:
  the sole broken form is arrow-on-array lvalue with a call-valued RHS. Filed for
  Track A (codegen is shared-internals; not editable under Track C). The cJSON
  harness, fixtures, and a crtl `sscanf` (needed for cJSON's float-roundtrip
  check) are committed and will go green when this is fixed; integer/string/bool/
  null fixtures already exercise the blocked path.
