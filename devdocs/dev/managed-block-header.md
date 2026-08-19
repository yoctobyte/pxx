# The managed-block header, and the kind word

Design record for multi-type string support (Pascal `ByteString` + NilPy
`TextString`), decided 2026-08-07. Written before implementation so the layout
is a decision rather than an accident.

## Why a runtime tag at all

The compiler knows a string's type statically almost everywhere — but not
everywhere, and the gaps are exactly where it matters: a value in a `Variant`, a
container element, an untyped/generic parameter. This is the same shape as the
RTTI gap: static knowledge evaporates at the boundary where a consumer most
needs it.

So the type must travel **with the value**, not only in the symbol table.

## What the header is today

The allocator hands back a block `B`; its own rounded-size word sits at `B-8`.
pxx lays its header at the front of `B`:

```
[alloc size:8]   B-8      the ALLOCATOR's, not ours
[refcount:8]     B+0
[length:8]       B+8      objects: a SPARE slot holding PXX_OBJ_MAGIC
[data...]        B+16     = p, the handle
```

so from the handle: `length` at `p-8`, `refcount` at `p-16`, block base at
`p-16`, allocator size word at `p-24`.

**16 bytes on every target.** There is no 32-bit variant — `PXXAlloc(len + 17)`
and `PXXAlloc(16 + n*elSize)` are unconditional, and ILP32 code simply reads the
low half of each 8-byte slot. This was checked rather than assumed; it is what
makes the change uniform across all six backends.

Strings, dynamic arrays **and objects share this protocol** — `ir_codegen.inc`:
*"a refcounted object block shares the string header protocol exactly (rc at
[p-16], free base = p-16), so the SAME release blob serves."*

## The new layout

One extra word, **below the refcount**:

```
[alloc size:8]   B-8
[kind:8]         B+0      NEW
[refcount:8]     B+8
[length:8]       B+16     objects: still the spare/magic slot
[data...]        B+24     = p
```

From the handle: **`length` stays at `p-8`, `refcount` stays at `p-16`.** Only
the block base moves, `p-16` → `p-24`.

That is the whole reason for this placement. The two hot fields keep their
offsets, so all ~73 length reads and every retain/release across six backends are
untouched. Two alternatives were rejected:

- **Steal the length's high bits.** Free in memory, but it is the hottest field
  in the compiler (every `Length`, every array bound), it is *already* overloaded
  (objects squat `PXX_OBJ_MAGIC` in its low 16 bits), and ILP32 reads only 32 of
  them — which would cap string and array size on 32-bit targets.
- **Narrow the refcount to 32 bits and use the freed 4 bytes** (FPC's own
  layout). Zero memory, but it changes atomic widths — `lock xadd` on x86-64,
  `ldaxr`/`stlxr` on aarch64 — on every target, for 8 bytes.

Cost: **+8 bytes per managed block**, exactly. The allocator rounds to a multiple
of 8 with bins at 8,16,…,512, so this is one bin up with no rounding cliff. Under
`PXX_ESP` the heap is a single 64 KiB static arena, where that is proportionally
expensive — which is what frozen strings (`string[N]`, shortstring) are for. They
carry no header at all and are unaffected.

## The word

Little-endian, byte 0 at `p-24`. Byte-aligned throughout, so every hot field
extracts in one instruction on all six backends.

**Naming.** The word is the **meta word** (`PXX_HDR_META`); its low byte is the
`BlockKind`. "Kind word" undersells it — it carries flags and per-kind payload
for strings, arrays *and* objects. Phase 1 shipped the offset constant as
`PXX_HDR_KIND`; rename it to `PXX_HDR_META` in phase 2's first commit, which
re-pins anyway. Nothing reads it yet, so the rename is free.

**All meaningful fields live in the LOW 32 BITS.** On ILP32 the three header
slots each use only their low half (`PWord` is a machine-word pointer), so 12 of
the 24 header bytes are padding there and a future packing pass would make the
meta word 32 bits wide — see
[[feature-a-shrink-managed-header-on-32-bit]]. Designing the payload to fit in
32 bits now costs nothing and keeps that option open; spending bits 32–63 would
close it.

| bits | field | purpose |
| --- | --- | --- |
| 0–7 | `BlockKind` | what this block IS |
| 8–15 | `Flags` | common to every kind |
| 16–23 | `KindData0` | per-kind |
| 24–31 | `KindData1` | per-kind |
| 32–63 | reserved | must be zero — **unavailable on a packed ILP32 header** |

An 8-bit `KindData0` cannot hold a raw Windows codepage (`CP_UTF8` = 65001), so
store a small **encoding enum** (0 = none/bytes, 1 = UTF-8, 2 = UCS-2,
3 = UCS-4) rather than FPC's number. That is the better field anyway: pxx needs
"how is this text represented", not a Win32 identifier, and it maps directly
onto PEP 393's kind.

**BlockKind:** `0 = Legacy/untagged`, `1 = ByteString`, `2 = TextString`,
`3 = DynArray`, `4 = Object`. 5+ reserved.

`ByteString` vs `TextString` is the real semantic axis — **do positions count
bytes or characters** — so it belongs in the kind, not in a codepage. This is a
deliberate divergence from FPC, which discriminates by codepage; encoding and
width are refinements *within* a kind here.

**Flags:** `bit0 Static` (in `.rodata`, refcount ignored, never freed — reserved,
speculative: it would enable FPC-style refcount-−1 literal aliasing), `bit1
Interned`, `bit2 ASCII` (verified no byte ≥ 0x80), `bit3 Extended` (a side-table
entry exists — the escape hatch), bits 4–7 reserved.

`ASCII` is the one that pays for itself: it makes NilPy `len`/index O(1) on the
overwhelmingly common string without a wider representation, and lets a Pascal
`ByteString` be adopted as text for free.

**Per-kind data:**

| kind | `KindData0` | `KindData1` |
| --- | --- | --- |
| ByteString | encoding enum, same values as TextString (`0` bytes / `1` UTF-8 / …) | elemsize (1) |
| TextString | encoding | bytes/char: 1, 2 or 4 (PEP 393's width) |
| DynArray | element `TTypeKind` | element size |
| Object | *(free — kind 4 replaces `PXX_OBJ_MAGIC`)* | |

`KindData0` is **8 bits, so it cannot hold a raw codepage** — that is the point
of the prose above, and the shipped constants agree:
`compiler/builtin/builtinheap.pas:210-216` defines `PXX_ENC_BYTES=0`,
`PXX_ENC_UTF8=1`, `PXX_ENC_UCS2=2`, `PXX_ENC_UCS4=3` at `PXX_ENC_SHIFT=16`,
under a comment reading *"A small enum, NOT a codepage — CP_UTF8 (65001) would
not fit"*. (Corrected 2026-08-19: this row used to claim the field held a
codepage "FPC-exact", contradicting both the paragraph above it and the code.)

## The three rules that keep this from being refactored

1. **Zero means legacy.** A block whose word is zero behaves exactly as today.
   This is what lets the layout land with nothing reading it.
2. **An unknown kind degrades to 0, never asserts.** Forward compatibility for a
   binary that predates a kind — which matters because a pinned stable binary
   has to keep working.
3. **`Extended` is the escape hatch.** If a future need does not fit, set it and
   key a side table on the block address. We can be wrong about the bit budget
   without being stuck.

## Static context wins; the kind answers only where it is lost

Kinds live on **shared, refcounted blocks**, so a kind cannot be flipped when a
string crosses between the Pascal and NilPy worlds without copying. Therefore:

> **Where a static type exists, it decides. The block kind answers only where the
> static type has been lost** — a variant, a container element, a generic or
> untyped parameter.

A `TextString` handed to Pascal code is read with byte semantics (FPC-correct, no
copy, no mutation). A `ByteString` pulled out of a variant by NilPy is treated as
UTF-8 text, with `ASCII` making the character count free when set.

## What it absorbs

- **`PXX_OBJ_MAGIC` retires.** `kind = Object` *is* the population tag; release
  dispatches on it instead of sniffing a magic word that lives inside the length
  field.
- **Dynamic arrays gain a runtime element type** — the same RTTI-shaped gap,
  closed for the other consumer of this header at no extra cost.

## Literals and frozen strings do NOT participate

A raw `.rodata` literal is never a valid managed handle — every path that turns
one into a string value goes through `AnsiStrFromLiteral` /
`EmitAnsiStrFromInlineString` and allocates a real block (*"Without this the
callee reads a raw rodata literal as a managed handle and the length is
garbage"*). Frozen `string[N]`/shortstring are inline buffers with no header.

Both are statically typed, so neither needs a runtime tag, and the
literal→managed conversion sites are the natural stamping points — the static
type is known exactly there. This was re-opened once during design; it is closed.

## Sequencing — READ THIS BEFORE TOUCHING CODE

**CORRECTED 2026-08-07 (this section was wrong the first time).** The original
claim here was that a header change "cannot land through a self-host generation"
and must be seeded from FPC. **That is false**, and it was measured wrongly: the
first experiment ran the old pinned binary from a scratch directory, where it had
no frozen RTL beside it and fell back to the LIVE tree — manufacturing exactly
the mismatch it then "proved".

Re-run properly, with the old pinned binary **and its own frozen
`builtin/`**, against the post-header source:

- it produced a **working** compiler (B), which compiled and ran programs;
- B → C → D reached a **fixedpoint** (C == D);
- and C was **byte-identical** to the FPC-seeded binary that shipped.

**The real rule is about the RTL, not about FPC:**

> Seed from a compiler that carries **its own versioned RTL**.

`pinned` does: `make pin` freezes `compiler/builtin/*.pas` into
`stable_linux_amd64/default/builtin/`, and the pinned binary resolves `uses
builtinheap` from its own ExeDir in preference to the live tree
(the pinned-stable builtin isolation). So a pinned seed is generation-consistent
by construction: its inline codegen and its RTL are the same vintage, while its
*emitter* is the new source — which is exactly what is needed.

`./compiler/pascal26` does **not**. It has no frozen RTL and resolves `uses
builtinheap` from the live tree, so it links tomorrow's RTL into today's
emitter. `make compiler/pascal26` seeds from it, which is the one path that
breaks — and it breaks silently: the compile succeeds and the *product* dies,
so it reads as a codegen bug. That gap is
[[bug-a-self-host-seed-has-no-versioned-rtl]].

`gate.sh` seeds its fixedpoint from `pinned` and would therefore have validated
this change all along. The earlier claim that it could not is withdrawn.

The split is deliberate and was the user's call:

- **Phase 1** — move the layout, allocate the word, write zero, *never read it*.
  Prove strings, dynamic arrays, objects and RTTI are unchanged. **Then pin.**
- **Phase 2** — only after the pin, start stamping and reading kinds. Because the
  pin made the new layout the ground truth, phase 2 never meets an old-offset
  binary.
