---
track: A
prio: 30
type: bug
status: backlog
owner: ""
created: 2026-09-04
blocked-by: []
summary: "A `QWord` passed to `array of const` boxes as `vtInt64` (16); FPC boxes the same source as `vtQWord` (17). Measured side by side. `vtQWord` IS declared in builtinheap.pas and appears in EXACTLY ONE place in the whole tree -- its own declaration: zero producers, zero readers. So any consumer that dispatches on the tag the way FPC's does takes the signed branch and renders a value >= 2^63 negative. NOT fixable inside a quick gate: the emit change lands on four backend asm-text readers (x86-64/i386/arm32/riscv32) that test `<> vtInteger and <> vtInt64`, and three of those are invisible on this host. SUPERSEDED 2026-09-06 (frankA) AND THE PREMISE IS FALSE: d210325a6 landed the EMIT half, so there has been a producer and no readers since -- a WORSE state than filed, because an unlisted tag falls to a case `else` and rendered the EMPTY STRING rather than a signed value. That is test-core#test_libwriteln_parity, red from d210325a6 until f4b288b16, which adds the vtQWord arm to all four lib readers (libwriteln VarRecToText; sysutils FmtArgStr/FmtArgInt/FmtArgFloat -- %d stays SIGNED on purpose, matching fpc, measured). THE ASM-TEXT BLOCKER IS CENSUSED AND EMPTY: it is SIX readers not four (aarch64 and xtensa postdate this ticket) and NONE is reachable -- all 363 EmitAsm* call sites parsed by bracket matching, every hole argument an Integer literal, constant or field read. They fail LOUDLY if ever reached, never mis-render, so they are a latent trap and are deliberately NOT changed. Beware the obvious census: a line-oriented grep sees only 237 of the 363 sites because 126 calls span lines, and reports nothing for them exactly as it does for a clean site."
---

# A QWord boxes as vtInt64, so `array of const` loses unsignedness

Measured 2026-09-04 at `c94252bb92cd`, against `fpc 3.2.2 -Mdelphi -O1`, one
program printing `a[i].VType` for fourteen declared types:

| source type | pxx tag | fpc tag |
| --- | --- | --- |
| `QWord` | 16 `vtInt64` | **17 `vtQWord`** |
| `ShortString` | 11 `vtAnsiString` | 4 `vtString` |
| everything else measured | identical | identical |

The `ShortString` row is **not** a defect — `builtinheap.pas:99` says so at the
declaration (*"vtString = 4; { shortstring; unused with ansistrings }"*), it is
a chosen consequence of this RTL's string model, and it is recorded here only
so the next person measuring this table does not re-file it.

The `QWord` row has no such note anywhere.

## The tag exists and nothing on either side of it is wired

```
$ grep -rn vtQWord compiler/ lib/
compiler/builtin/builtinheap.pas:112:  vtQWord      = 17;
```

One hit, and it is the declaration. Nothing emits it and nothing reads it,
while FPC emits it for ordinary source. A consumer written against FPC's tag
set — `case v.VType of vtQWord: ...` — compiles here and silently takes a
different branch.

## Why it is quiet

Below 2^63 the signed and unsigned readings of the same 8 bytes are equal, so
the divergence is invisible on every small value and appears only at the top of
the range. `IntToStr(PInt64Rec(v.VInt64)^)` on `18446744073709551615` gives
`-1`.

**Do not reach for `Format('%d', [q])` as the repro — it prints `-1` under BOTH
compilers**, so it looks like agreement and proves nothing about the tag. FPC's
own `%d` reads its `vtQWord` signed; that is FPC's formatter choice, not the
tag. The tag is where we differ, and the probe has to print `VType` to see it.

## Why this is filed rather than fixed

Not size — **verifiability.** Emitting `vtQWord` is one line at the
`AN_VARREC_ARRAY` boxing site, but the readers are the constraint:

- `lib/rtl/sysutils.pas` — `FmtArgInt`, `FmtArgStr`, `FmtArgFloat` each `case`
  on the tag with an `else` returning `0`/`''`. A newly-emitted `vtQWord` falls
  into that `else`, so QWord arguments to `Format` would start rendering as
  empty rather than wrong. **The fix makes things worse until the readers land
  in the same commit.**
- `compiler/asmtext.inc`, `asmtext_386.inc`, `asmtext_arm32.inc`,
  `asmtext_rv32.inc` — all four test
  `(VType <> vtInteger) and (VType <> vtInt64)` and REFUSE anything else. This
  is the compiler's own asm-text emitter, i.e. self-host critical, once per
  backend.

Three of those four backends are cross targets. `gate.sh quick` and the
self-host fixedpoint both run on x86-64, so a break in the i386/arm32/riscv32
emitters is **structurally invisible to the gate that would have to approve
it** — the exact defect class this repo has been bitten by twice
(see `bug-a-method-pointer-record-is-hard-sized-16-bytes-on-32-bit-targets`).
Whoever takes it should land emit + all seven readers together and verify on a
cross target, not on this host.

## Ranking

30. The divergence is certain, but nothing in the tree reads `vtQWord` today,
so nothing is currently wrong *because* of it — the cost is that a
tag-dispatching consumer ported from FPC misbehaves silently. Raise it if
`feature-writeln-as-library` phase 3 lands, since a library `writeln` reading
the vector cannot render a large QWord the way the builtin does, and that is a
parity row it will fail.

## Repro

```pascal
procedure Dump(const a: array of const);
var i: Integer;
begin
  for i := 0 to High(a) do write(a[i].VType, ' ');
  writeln;
end;
var q: QWord;
begin
  q := 3; Dump([q]);     { pxx: 16    fpc: 17 }
end.
```

## RESOLVED IN TWO HALVES, AND THE READER CENSUS THIS TICKET ASKED FOR IS DONE

**2026-09-06 (frankA), on binary `5375cb2828e8`.**

### The emit half landed first, and broke the reader half

`d210325a6` made the compiler emit `vtQWord` (17) — `ir.inc`, the `tyUInt64` /
`tyNativeUInt`-on-64-bit arm. So this ticket's central claim, *"zero producers,
zero readers"*, has been false since that commit. There was a producer and no
reader, which is a worse state than the one filed here: every `array of const`
reader dispatches with a `case` over the tag, and an unlisted tag falls to the
`else`. `LibWriteLn(['x=', q])` printed **nothing at all** for a QWord, where
the filed defect was merely rendering signed. That is
`test-core#test_libwriteln_parity`, red from `d210325a6` until `f4b288b16`.

**The divergence moved from "renders signed" to "renders nothing" between the
two fixes, and this ticket's summary described neither.**

### The reader half: FOUR readers, and the ticket had found one class of them

`f4b288b16` adds the `vtQWord` arm to all four:

| reader | was | now |
| --- | --- | --- |
| `libwriteln.pas` `VarRecToText` | `''` | `UIntToStr` |
| `sysutils.pas` `FmtArgStr` (`%s`) | `''` | `UIntToStr` |
| `sysutils.pas` `FmtArgInt` (`%d`) | `0` | `Int64()` — see below |
| `sysutils.pas` `FmtArgFloat` (`%f`) | `0` | `Double` |

`%d` stays SIGNED deliberately and the comment carries the measurement, because
it looks like a bug: at `q = 18000000000000000000`, fpc 3.2.2 and pxx both give
`Format('%d')` = `-446744073709551616` and `Format('%u')` = the full value. `%d`
is the signed conversion. Making that arm unsigned would diverge from the oracle.

### The asm-text readers: CENSUSED, and they are unreachable today

This ticket's stated blocker was that the emit change *"lands on four backend
asm-text readers … and three of those are invisible on this host."* Measured:

**It is SIX readers, not four** — `asmtext.inc:1209`, `asmtext_386.inc:681`,
`asmtext_arm32.inc:544`, `asmtext_rv32.inc:506`, `asmtext_a64.inc:905`,
`asmtext_xtensa.inc:419`. All still test `(VType <> vtInteger) and (VType <>
vtInt64)`. The ticket's count predates aarch64 and xtensa.

**And none of them can be reached today.** Census over every `EmitAsm*` call
site in `compiler/**`: **363 sites**, each parsed by matching its bracket rather
than by line, and every hole argument is an `Integer` literal, an `Integer`
constant (`BSS_*`, `HEAP_*`, `VT_PROMO_*`) or an `Integer` field read
(`Syms[i].Offset`, `Strs[i].Offset`, `Strs[i].Len`, `LabelPositions[l]`). No
`QWord`, `NativeUInt`, `PtrUInt` or `Int64` argument exists at any of them.

**The first cut of that census was wrong and the correction is the useful part.**
A single-line `grep` for `EmitAsm*([...]` sees only 237 of the 363 sites —
**126 calls span lines**, and a line-oriented instrument reports nothing for
them, exactly as it reports nothing for a site with no wide argument. Both look
like "clean". The count that matters is not the hits, it is the 363.

The bracket-matching splitter is imperfect in one direction only: it mis-splits a
few string literals containing `{ }` comments, so they appear in the candidate
list as if they were arguments. That **over**-reports candidates and cannot
**under**-report them, so the conclusion survives the flaw.

**So these six are a LATENT TRAP, not a live defect, and they fail LOUDLY.**
Reached, they call `Error('… missing integer hole value')` — for a value that is
an integer. They never mis-render. `tyNativeUInt` only becomes `vtQWord` where
`TARGET_PTR_SIZE = 8` (frankS's narrowing), so the 32-bit backends cannot
inherit it through that door at all; a literal `QWord` in an asm-text hole is
the only way in, and nothing writes one.

**Not fixed here, deliberately.** Adding a `vtQWord` arm to six readers no
caller can reach is a change with no measured need, and
[[a-guard-you-add-must-say-whether-its-necessity-was-shown]] applies. What is
worth having is this paragraph, so the next person to widen the tag set knows
the readers exist, that there are six, and that the census was of call sites
rather than of grep hits.

### What is inert under the pin, stated precisely

Two true statements about different things, and a pin manifest wants the second
(frankS's distinction, and it corrects the looser line in `f4b288b16`):

- The lib/rtl **source** is live for anything built from the tree.
- The new **arm never fires** under `$(PXX_STABLE)`, because the pinned compiler
  does not emit tag 17. Under the pin these readers see `vtInt64` exactly as
  before.
