---
track: A
prio: 55
type: feature
blocked-by: []
summary: "The managed-string header reserves a text-encoding enum at meta bits 16-23 (PXX_ENC_BYTES/UTF8/UCS2/UCS4, builtinheap.pas:289) and NOTHING stamps or reads it — every managed string in the system, of any width, is enc 0 = BYTES. Mirror the constants into compiler/defs.inc (which has no name for the field, so the compiler cannot stamp it), stamp them from the static element type at every allocation site, and read them where the width is not statically known. Adding a value to an already-reserved field is not a layout change, so PXX_RTL_LAYOUT_VERSION does not bump."
---

# Stamp and read the managed-string encoding field

Split from
`decided/decide-one-managed-string-kind-with-an-element-width-or-a-second-kind.md`,
where the owner raised it while ruling. **The field was reserved in the original
header design; this is finishing it, not adding it.**

## What exists

Header: `[meta:8][rc:8][len:8][data][nul]`, handle = base + 24. The meta slot is
8 bytes and the highest bit in use is 12. `compiler/builtin/builtinheap.pas:289`:

```pascal
{ KindData0, bits 16-23: text encoding. A small enum, NOT a codepage —
  CP_UTF8 (65001) would not fit, and this is the field pxx actually wants. }
PXX_ENC_BYTES = 0;  PXX_ENC_UTF8 = 1;  PXX_ENC_UCS2 = 2;  PXX_ENC_UCS4 = 3;
PXX_ENC_SHIFT = 16;
```

Accessors `PXXHdrMeta` / `PXXHdrSetMeta` exist and are already used for the
ASCII-cache flags. `test_managed_block_meta` already pins the meta word.

## The four gaps

1. **`compiler/defs.inc` has no `MSTR_ENC_*` mirror.** It stops at
   `MSTR_KIND_LEGACY`/`STATIC`/`ASCII`/`ASCII_KNOWN`. The constants are
   *deliberately* duplicated rather than shared (builtinheap is COMPILED by this
   compiler, not included into it), so the mirror is the required first step and
   must be added with the same "MUST equal" note the other constants carry.
2. **`compiler/emit.inc:670` stamps `MSTR_KIND_LEGACY` for every pooled
   literal**, so enc is always 0. A wide literal must stamp `PXX_ENC_UCS2`.
3. **Nothing reads it.**
4. **Every other allocation path** (`PXXStrFromLit`, the concat/SetLength/COW
   paths, the realloc path at builtinheap.pas:4257 which is documented as
   leaving the meta "EXACTLY as LEGACY plus…") must carry the source's encoding
   through rather than defaulting it.

## The design constraint that matters most

`ASTStrElemTk` (static, compile-time) and `PXX_ENC_*` (runtime) are two
spellings of one concept. **Derive one from the other at the allocation site;
never maintain them in parallel.** Two mechanisms serving one concept is
`devdocs/dev/normalise-dont-special-case.md`'s exact failure mode, and it is the
one the parent ticket just finished avoiding one level up. A checked build
should be able to *assert* they agree — that is a large part of the field's
value, since it converts the silent-wrong-value failure mode into a loud one.

Corollaries, both ruled in the parent:

- **`len` stays a BYTE count**, always. The encoding supplies the divisor. A
  char-count length would make every allocator size computation width-aware and
  give up the property that makes the runtime need no second block shape, no
  second refcount path and no second free path.
- **Keep the tag off `Length`'s hot path.** Where the width is statically known
  — nearly everywhere the compiler emits code — keep using it and keep the
  shift a compile-time constant. The tag earns its keep where the width is NOT
  known: a library routine holding a bare handle, `Write`, RTTI, variants, the
  debugger, assertions.

## One interaction to CHECK, not assumed

The ASCII flag is computed by OR-ing every byte and testing bit 7
(`emit.inc:671`). That heuristic is encoding-blind: UTF-16 `U+0100` is bytes
`00 01`, whose OR is `$01`, which would be flagged ASCII. **Whether any wide
string reaches that path today is UNVERIFIED** — it may be unreachable. Verify
before changing anything; if it is reachable it is a bug in its own right, and
either way the encoding field is what makes `ASCII` well-defined per encoding.

## Why this is cheap

Adding values to an already-reserved field is not a layout change, so
`PXX_RTL_LAYOUT_VERSION` (defs.inc twin, refused on mismatch at link) does not
bump and no seed compatibility breaks.

## Gate

`make compiler/pascal26` + a repro. Extend `test_managed_block_meta` to assert a
stamped encoding round-trips, and follow the parent's carried rule: **name the
`PXX_MANAGED_STRING` arm and run both.**
