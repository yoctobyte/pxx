---
track: U
prio: 55
type: decide
blocked-by: []
summary: "The runtime already spells 'this block holds UTF-16' TWICE: PXX_KIND_WIDESTR = 5 in the BlockKind byte, stamped at three sites in builtinwide.pas and shipped, and the reserved PXX_ENC_UCS2 in KindData0 that feature-a-stamp-and-read-the-managed-string-encoding-field was filed to start stamping. Neither is READ by anything, so nothing is broken yet and this is the cheap moment. Recommend the ENC field wins and WIDESTR retires, because kind is one byte with one value and so TEXTSTR (NilPy, character positions) + UTF-16 payload has no representable value today. Do NOT implement that ticket's gap 2 until this is ruled."
---

# Two spellings of "this payload is UTF-16", and the open ticket builds the second

## The fork

`compiler/builtin/builtinheap.pas` reserves two independent bit ranges in the
meta word, and both now claim the same fact:

```pascal
{ BlockKind, bits 0-7 }
PXX_KIND_LEGACY = 0; PXX_KIND_BYTESTR = 1; PXX_KIND_TEXTSTR = 2;
PXX_KIND_DYNARRAY = 3; PXX_KIND_OBJECT = 4;
{ Pascal WideString/UnicodeString -- fixed-width UTF-16. ... }
PXX_KIND_WIDESTR = 5;      { line 226 -- SHIPPED and STAMPED }

{ KindData0, bits 16-23: text encoding. }
PXX_ENC_BYTES = 0; PXX_ENC_UTF8 = 1; PXX_ENC_UCS2 = 2; PXX_ENC_UCS4 = 3;
PXX_ENC_SHIFT = 16;        { line 289 -- RESERVED, never stamped }
```

`PXX_KIND_WIDESTR`'s own comment says **"fixed-width UTF-16"**. That is
`PXX_ENC_UCS2`'s definition.

## How they came to coexist — nobody made this decision

Landing order, from `git log -S`:

| | commit | what |
| --- | --- | --- |
| first | `3d077e71a` | `feat(N): the META word and a free ASCII flag — phase 2 foundation (pin v248)` — **reserves `PXX_ENC_*`** |
| later | `bfe82dd79` / `c59bcb7f0` | `feat(a): UTF-16 runtime half` / `builtinwide becomes an on-demand unit` — **adds and stamps `PXX_KIND_WIDESTR`** |

The encoding field was reserved first. When the UTF-16 runtime was actually
built, its author reached for the BlockKind byte instead — reasonably, since
nothing pointed at the reserved field. Then
`decided/decide-one-managed-string-kind-with-an-element-width-or-a-second-kind`
(2026-08-31) re-discovered the reserved field while ruling and filed
`feature-a-stamp-and-read-the-managed-string-encoding-field` to finish it,
**without noticing the shipped stamp**. Neither step was wrong on its own
evidence; the duplication is what fell out.

That ruling's own carried text argues the encoding field is the better shape,
and it argues it against a WIDTH field, never having seen the KIND value:

> **An ENCODING field is a better shape than a width field** [...] `BYTES` and
> `UTF8` are both one byte per character and differ in *meaning*; width (1/1/2/4)
> falls out of the encoding rather than being the primary fact.

## Measured, at `1b252b0eb05e`

Nothing reads either spelling. `grep -rn PXX_KIND_WIDESTR compiler/ lib/`
returns **four lines: three stamps in `builtinwide.pas` (99, 123, 215) and the
declaration.** The only consumer of the kind byte anywhere is the generic
use-after-free poison check at `builtinheap.pas:642` (`hdrKind > PXX_KIND_MAX`
=> `Halt(204)`), which cares about the MAX and not about which value it is.
`compiler/defs.inc` mirrors neither: it stops at `MSTR_KIND_LEGACY`, so the
compiler has no name for WIDESTR *or* for the encodings.

With `-dPXX_WIDE_PAYLOAD` the wide path is live and correct — `w := 'AB'`
stores `65 0 66 0`, `WideChar(256) + WideChar(65)` stores `0 1 65 0` with
`w[1] = 256`, `Write(w)` emits UTF-8 — and every one of those blocks carries
`meta = 5`: kind WIDESTR, **enc 0 = BYTES**, which is the field saying the
payload is bytes about a block that is UTF-16. Harmless only because nobody
asks.

## The argument that decides it, and it is checkable rather than aesthetic

**Kind is ONE byte holding ONE value, so kind and encoding cannot both live
there.** The two existing kinds that matter are distinguished by *public
position semantics*, not by payload:

- `PXX_KIND_BYTESTR` — Pascal AnsiString, `Length` counts BYTES (FPC-exact)
- `PXX_KIND_TEXTSTR` — NilPy str, public positions count CHARACTERS

`PXX_KIND_WIDESTR` fuses a position semantics (Pascal's) with a payload
encoding (UTF-16) into a single value. The concrete consequence: **a NilPy
`str` with a UTF-16 payload has no representable value.** TEXTSTR and WIDESTR
are two values of one field; you cannot say both. With the second axis it is
just `kind = TEXTSTR, enc = UCS2`. That is the product-of-axes case, and it is
the reason the second range was reserved in the first place.

It also predicts the next collision rather than merely explaining this one: any
future `UCS4` payload needs a *seventh* kind under the fused scheme, and zero
new kinds under the split one.

## Recommendation

**The ENC field wins; `PXX_KIND_WIDESTR` retires**, and a wide block becomes
`kind = BYTESTR` (Pascal position semantics — `Length` is already a byte count
for it, per the constant's own comment) with `enc = UCS2`.

Cheap today and only today: three stamp sites, no readers, and
`PXX_KIND_MAX` drops 5 -> 4 with the poison check unaffected ($DD = 221 is
still `> MAX`). Every retain/release/free/memcpy path is untouched by
construction — the ruling's whole point is that `len` stays a byte count.

**What I am NOT deciding, because it is genuinely someone's call:**

1. Whether to retire `PXX_KIND_WIDESTR` outright or leave it declared-but-
   unstamped as a reserved-dead value. Reusing 5 for something else later is
   the hazard either way.
2. `PXX_RTL_LAYOUT_VERSION`. The parent ruling says adding a value to a
   reserved field does not bump it. **Changing a value the runtime already
   stamps is not the same act**, even with no readers — a seed binary built
   before the change stamps 5 and one built after does not. I believe it still
   does not bump (nothing compares the field), but I did not verify the seed
   path and will not assert it.

## Consequence for the open ticket — this is the part that needs no ruling

`feature-a-stamp-and-read-the-managed-string-encoding-field` (Track A, prio 55,
`backlog-core/`) is READY and its gap 2 says *"A wide literal must stamp
`PXX_ENC_UCS2`"*. Implementing that as written adds the second spelling rather
than resolving the first, and its own body cites
`normalise-dont-special-case.md` against exactly that. Its summary and gap list
have been corrected to point here; **that correction stands whichever way this
is ruled**, because building both spellings is not an option either way.
