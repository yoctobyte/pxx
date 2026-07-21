---
track: A
prio: 45
type: feature
---

# RTTI: field get/set by name (extends the VMT-8 method-reflection blob)

- **Track:** A (compiler core: RTTI blob layout, symtab, codegen).
- **Opened:** 2026-07-19, needed by [[feature-lib-pyexec]] (uforth arc) —
  and by the LFM/streaming plan (project_rtti_streaming_plan), dual use.

Method reflection exists (VMT-8 blob: names + invoke-by-name, shipped in
the fpcunit arc). Missing: FIELD reflection — per-class table of (name,
type kind, byte offset, record id for aggregates), plus runtime helpers:

- `GetFieldPtr(obj, 'name') -> Pointer` (+ type kind out) — get/set built
  on it.
- Works for Pascal classes AND NilPy-lowered classes (same class machinery;
  the exec bridge resolves `vm.here` / `vm.memory[i] = x` through this).

Notes:
- Blob names as frozen strings (same as the method blob — see
  project_rtti_reflection_and_overload_landmines).
- Layout addition rides the existing RTTI blob emitter; bump its version
  tag, keep old readers working (streaming plan reads the same blob).
- Self-host: compiler binary carries RTTI blobs -> codegen change =
  reseed/codegen-differ expected on the landing commit.

Gate: `make test` + self-host byte-identical; regression exercising field
get/set by name on a class with mixed field types incl. a record field and
a variant.

## 2026-07-21 finding — the current field RTTI is INSUFFICIENT for this

Measured while scoping the uforth exec() bridge (pyeval). Two concrete gaps the
implementation MUST close, both verified in `rtti_emit.inc`:

- **Published-gated.** `EmitRTTI` gives unpublished classes "zero counts and no
  prop/meth arrays" (rtti_emit.inc ~329). NilPy classes publish nothing, so
  uforth's `VM` gets an EMPTY field table today — reflection finds nothing. The
  field/method tables must be emitted for ALL NilPy-lowered class members, not
  just published ones. (The per-class HEADER is already emitted for every class;
  only the member arrays are gated.)
- **No field TYPE.** `EmitFieldInfo` (rtti_emit.inc ~295) writes only name-ptr +
  byte offset. The exec bridge reads/writes `vm.memory` / `vm.here` / `vm.base`
  as VARIANTS, so it needs the field's type kind (and record id for aggregates)
  to box/unbox correctly — exactly the `(name, type kind, byte offset, record
  id)` tuple this ticket already specifies. Confirmed the gap is real, not
  hypothetical.

Consumer census (uforth PYTHON blocks): ~25 distinct `vm` members are touched —
FIELDS `memory, vars, here, rstack, stack, dict, base, _pic_buf,
current_def_tokens, input_line, fstack, input_pos, current_token_index,
current_def_name, xt_table` and METHODS `define_word, next_token_strict,
next_token, run_forth_word, exec_token_runtime, strip_string_token,
is_string_token, trace`.

## LANDED 2026-07-21 (commit e8ebbf0a) — field side complete

- Field table now emits EVERY field (not just published); FieldInfo grown to
  `(name, offset, typeKind, recId, flags)`, RTTI_FIELD_SIZE 16 -> 40, flags bit0
  = published so the streamer still filters. `EmitFieldInfo`/`EmitRTTI` in
  rtti_emit.inc, `TFieldInfo` in typinfo.pas kept in lockstep.
- Runtime helpers in typinfo.pas: `GetFieldInfoByName`, `GetInstanceRTTI` (VMT-8
  backlink), `GetFieldPtr(instance, cls, name, out kind) -> Pointer`.
- `test/test_rtti_field_get_by_name.pas`: int/int64(read+write)/object/record +
  absent-name. Quick+limited GREEN (only the pre-existing test-core#122 flake),
  self-host byte-identical after the expected RTTI reseed.

## FOLLOW-ON (not this ticket) — method table is ALSO published-gated

Discovered while landing fields: the METHOD table (`UMthPub=1` gate in
rtti_emit.inc) is published-only too, so `GetMethodAddr` finds NOTHING on a
NilPy class — method invoke-by-name does NOT yet cover uforth's `define_word` /
`run_forth_word` / etc. The exec bridge needs the same un-gating for methods,
plus arity/param-type in `MethInfo` (currently name+code only) so the generic
native-call trampoline can marshal args. Filed as part of the pyeval host-bridge
work in [[feature-lib-pyexec]] (build with the trampoline), not here — this
ticket was scoped to FIELD get/set and that is done.

## Log
- 2026-07-21 — resolved, commit e8ebbf0a.
