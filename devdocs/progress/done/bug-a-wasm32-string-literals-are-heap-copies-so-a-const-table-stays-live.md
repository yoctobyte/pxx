---
track: A
prio: 50
type: bug
status: done
found: 2026-09-28
found-by: frankD
owner:
summary: "LEAK (constant), wasm32 only. Every string literal that reached a managed slot was heap-copied with PXXStrFromLit. The register backends hand out the literal's static block, which is laid down with a full header and MSTR_STATIC_RC. pylib's 256-entry `PyChar1Tab` const table became 249 heap blocks alive at exit in every program that links pylib, so json_calc_error_paths read live=265 against a bound of 64."
---

# wasm32: string literals are heap copies, so a const string table stays live

emit.inc gives every literal a managed header (meta, rc = MSTR_STATIC_RC,
length), so the handle `Strs[si].Offset + 8` is a valid managed string whose
retain and release are no-ops. The register backends use it
(EmitStaticLitHandle). wasm32's WasmEmitOwnedStr allocated a copy for every
literal instead.

## Resolution (2026-09-28)

A non-empty literal (or any literal under the nil-py rule) hands out its static
handle, with no allocation and no retain. The empty literal keeps the old path.

Copy-on-write was checked against FPC 3.2.2 with an 8-line probe: index store
into a literal-initialised variable and into a copy of a typed-const element,
`var` mutation, concat, SetLength, Insert and Delete. Output was identical.

Handing out the static handle exposed a wasm32 leak that the heap copy had been
hiding: bug-a-wasm32-a-const-by-ref-argument-clones-the-string-it-indexes.
Measured on wasm32: a pylib-only program 249 -> 0; json_calc_error_paths
265 -> 1.
