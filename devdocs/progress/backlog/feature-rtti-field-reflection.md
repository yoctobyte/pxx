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
is_string_token, trace`. Method invoke-by-name (VMT-8) already ships and covers
the method half; this ticket's field get/set completes the bridge.
