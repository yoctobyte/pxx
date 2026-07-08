---
prio: 65
---

# C: struct-tag redefinition misfiles a field into the prior record → self-referential record → compiler SIGSEGV

- **Type:** bug (cparser struct layout / tag redefinition). Track A (shared
  symtab.inc + record field pool).
- **Found:** 2026-07-08 game-library ladder, ENet unity probe
  (feature-game-library-candidate-suite).

## Symptom
The compiler SIGSEGVs (stack overflow) compiling the ENet unity build. Crash
site `RecordHasManagedFields` (symtab.inc) recursing forever on a
self-referential record: `struct in_addr` ends up with a field `ip_dst` whose
`UFldRec_` points back at `in_addr` itself.

## Mechanism (diagnosed)
ENet includes `<netinet/tcp.h>` / `<netdb.h>` / `<poll.h>`, which crtl does
NOT provide (see bug-c-crtl-missing-net-headers-enet), so the HOST headers are
pulled — and they REDEFINE `struct in_addr` (already defined by crtl's
netinet/in.h) and define `struct ip_opts { struct in_addr ip_dst; ... }`.
On the tag redefinition + adjacent struct layout, `ip_dst` (a `struct ip_opts`
member of type in_addr) is appended into `in_addr`'s own field range and
recorded with `UFldRec_ = in_addr`, i.e. a record containing itself by value —
impossible in C, and it makes RecordHasManagedFields (and any UFldRec_ walk)
recurse without bound.

## Two fixes
1. **Robustness (do regardless):** RecordHasManagedFields — and any recursive
   `UFldRec_` walk — must not infinite-loop on a cyclic/self record (depth cap
   or visited-set; a compiler must never crash on malformed input).
2. **Root cause:** struct-tag REDEFINITION must not append fields into the
   existing record's contiguous range (or must reject the redefinition), and a
   by-value field of the record's own type must be rejected, not recorded.

## Repro
`tools/install_lib_candidates.sh enet` then compile
`test/gamelib/enet_probe.c` (unity include of the ENet core .c) with
`-Ilibrary_candidates/enet/include -Ilibrary_candidates/enet`. SIGSEGV.

## Gate
ENet unity compiles (or errors cleanly); a minimal tag-redefinition repro; no
compiler crash; self-host byte-identical.

## Log
- 2026-07-08 — resolved, commit f9fe98f8.
