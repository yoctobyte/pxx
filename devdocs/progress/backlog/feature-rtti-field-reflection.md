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
