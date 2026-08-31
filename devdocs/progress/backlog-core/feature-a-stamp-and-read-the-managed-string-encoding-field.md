---
track: A
prio: 55
type: feature
blocked-by: [decide-the-utf16-payload-fact-is-spelled-twice-kind-widestr-and-enc-ucs2]
summary: "BLOCKED ON A DECISION, do not implement gap 2 as written. The header reserves a text-encoding enum at meta bits 16-23 (PXX_ENC_BYTES/UTF8/UCS2/UCS4, builtinheap.pas:289) that nothing stamps or reads — but the UTF-16 fact is ALREADY spelled a second way, by PXX_KIND_WIDESTR = 5 in the BlockKind byte, shipped and stamped at three sites in builtinwide.pas and read by nothing. Stamping PXX_ENC_UCS2 for wide strings would add a second spelling of a live one, which is the normalise-dont-special-case failure this ticket's own body warns against. Fork filed as decide-the-utf16-payload-fact-is-spelled-twice-kind-widestr-and-enc-ucs2. The ASCII-heuristic interaction this ticket asked to CHECK is measured and UNREACHABLE — see below."
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
2. ~~**`compiler/emit.inc:670` stamps `MSTR_KIND_LEGACY` for every pooled
   literal**, so enc is always 0. A wide literal must stamp `PXX_ENC_UCS2`.~~
   **WRONG ON BOTH HALVES — measured 2026-08-31, see the section at the bottom.**
   There is no such thing as a pooled wide literal: `w := 'AB'` interns the
   NARROW bytes and transcodes at runtime through `PXXWideFromStr`, so
   `emit.inc` never sees a UTF-16 payload to stamp. And the fact this asks to
   stamp is already stamped elsewhere, as `PXX_KIND_WIDESTR`.
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


---

## 2026-08-31 — the CHECK this ticket asked for, run; and why gap 2 is withdrawn

Binary `1b252b0eb05e`, measured, not reasoned. Two results, and the second is
the one that changes what this ticket is.

### 1. The ASCII interaction is UNREACHABLE — the cheap answer

This ticket said, correctly, *"Whether any wide string reaches that path today
is UNVERIFIED — it may be unreachable. Verify before changing anything."* It is
unreachable, by both routes, and for two different reasons:

- **Static (`emit.inc:670`).** `InternStr` takes an `AnsiString` and a wide
  literal never reaches it as UTF-16. Under `-dPXX_WIDE_PAYLOAD`, `w := 'AB'`
  pools the two NARROW bytes and calls `PXXWideFromStr` at run time; the
  per-byte OR therefore only ever sees narrow bytes and is correct.
- **Runtime.** `PXXWideAlloc`/`PXXWideConcat` stamp `PXX_KIND_WIDESTR` and
  **never set `PXX_FLAG_ASCII_KNOWN`** — measured `known=FALSE` on every wide
  block. Nothing scans a wide payload, so nothing can mis-scan one.

So the feared `U+0100 -> bytes 00 01 -> OR = $01 -> flagged ASCII` cannot
happen today. Worth keeping in the record as a **trap for whoever makes the
wide path the default**: the moment anything scans a wide payload, that
heuristic is wrong, and the honest `known=FALSE` is what is protecting it.

### 2. The fact is already spelled once — gap 2 would spell it twice

`compiler/builtin/builtinheap.pas:226`, whose comment is explicit:

```pascal
{ Pascal WideString/UnicodeString -- fixed-width UTF-16. ... }
PXX_KIND_WIDESTR = 5;
```

**"fixed-width UTF-16" is `PXX_ENC_UCS2`'s definition.** It is stamped at
`builtinwide.pas` 99, 123 and 215, and `grep -rn PXX_KIND_WIDESTR compiler/
lib/` finds no reader anywhere — the only consumer of the kind byte is the
generic `hdrKind > PXX_KIND_MAX` poison check at `builtinheap.pas:642`.

Measured under `-dPXX_WIDE_PAYLOAD`: a wide block reads `meta = 5` — kind
WIDESTR, **enc 0 = BYTES** — which is the encoding field asserting BYTES about
a block that is UTF-16. Harmless only because nobody reads it, which is also
what makes now the cheap moment to fix it.

This ticket's own "design constraint that matters most" section is the argument
against its own gap 2:

> Two mechanisms serving one concept is
> `devdocs/dev/normalise-dont-special-case.md`'s exact failure mode, and it is
> the one the parent ticket just finished avoiding one level up.

It named the hazard and then missed that the system was already in it, because
the parent ruling audited `ASTStrElemTk` (the static side) and the reserved
`PXX_ENC_*`, and never grepped the kind byte.

### What is still live here, and what is not

- **Gap 1 (mirror the constants into `defs.inc`)** — still needed, but the
  decision picks WHICH constants. Do it after the ruling, not before.
- **Gap 2** — withdrawn as written, above.
- **Gaps 3 and 4 (nothing reads it; carry it through concat/COW/realloc)** —
  real, and unchanged in substance by the ruling: whichever spelling wins,
  something must carry it through `PXXStrAppend`/`PXXStrUnique`/the realloc
  path at `builtinheap.pas:4257`, which today preserve `LEGACY` and would drop
  a wide tag on any block that reached them.

Fork: `backlog-decide/decide-the-utf16-payload-fact-is-spelled-twice-kind-widestr-and-enc-ucs2.md`.
Filed rather than ruled here because retiring a value the runtime already
stamps is a design call with a `PXX_RTL_LAYOUT_VERSION` question attached, and
Track U is the lane for that.

### Unrelated staleness fixed in passing

`compiler/pasparser_decl.inc:480` justified the `PXX_WIDE_PAYLOAD` gate with
*"the four wide functions in builtin/builtinwide.pas are called from NOWHERE"*.
That was true when written and is now false — step 7c landed, and `ir.inc`'s
`IRStrWidthConv` / `IRWideWriteValue` / the concat arm call all of them. The
comment was corrected to record what it measured, when, and that the gate's
remaining reason is an open question rather than that one. The gate itself was
NOT touched.
