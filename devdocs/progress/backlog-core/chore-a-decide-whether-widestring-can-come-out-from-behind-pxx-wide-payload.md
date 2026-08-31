---
slug: chore-a-decide-whether-widestring-can-come-out-from-behind-pxx-wide-payload
title: "WideString's element width is still behind {$define PXX_WIDE_PAYLOAD} — deliberate, and here is what would retire it"
track: A
prio: 25
type: chore
status: backlog
owner: ""
created: 2026-08-30
found-by: frankwasm
summary: "Declaring `w: WideString` gives UTF-8 bytes by default and UTF-16 units only under {$define PXX_WIDE_PAYLOAD} — a live behavioural difference (Length 5 / w[4]=195 vs 4 / 233 for 'café'). The gate is DELIBERATE, left in place when feature-unicodestring-model closed, and this ticket exists so the next reader can tell that from forgotten. Retiring it is a measurement, not a decision."
---

# The gate, and why it is still there

`pasparser_decl.inc` widens the type NAMES `widestring` / `unicodestring` only
when the program defines `PXX_WIDE_PAYLOAD`. Measured 2026-08-30 on `'café'`:

    no define:   Length(w)=5  w[4]=195     UTF-8 bytes, the historic alias
    with define: Length(w)=4  w[4]=233     UTF-16 units, é = U+00E9

Both are self-consistent. Neither is a bug. The default is the behaviour every
existing pxx program was written against.

**The gate does NOT hold back the thing the campaign was for.** `WideChar` is
not gated, so `WideChar(u1) + WideChar(u2)` is a genuine two-unit UTF-16 value
in a default build and `test_widestring_jsonscanner_wall` — the fcl-json escape
path, the campaign's whole reason to exist — passes ungated, byte-identical to
FPC. That was checked before the campaign closed and is why the gate could stay.

# Why this is a ticket and not a sentence in a closed write-up

Filed at the coordinator's insistence and the reasoning is worth keeping:
**a deliberate residue named only inside a `done/` file is invisible to the
ranker, invisible to `check`, and read by nobody.** In three weeks an agent
finds `PasDefineExists('PXX_WIDE_PAYLOAD')` and cannot tell deliberate from
forgotten — and the cheapest reading of an undocumented gate is always "someone
did not finish". This ticket is the thing that answers them.

# What would retire it — a measurement, not a judgment

The gate was correct when written because breaking the alias made the COMPILER
believe UTF-16 while the RUNTIME still stored UTF-8. That is no longer true; the
lowering exists. So the remaining question is only *blast radius*, and it is
answerable:

1. Force the define on globally and build the corpus + `lib/**` + `examples/**`.
2. The exposure to look for is code that declares `WideString` and then treats
   it as bytes — `Length` as a byte count, `s[i]` as a byte, a `SizeOf`-shaped
   assumption, anything passing it to a byte-oriented API.
3. **Do not use an ASCII test to decide this.** On ASCII a UTF-8 byte count and
   a UTF-16 unit count are the same number, so an ASCII sweep answers green for
   both settings and proves nothing. Three bugs in this campaign survived on
   exactly that.
4. Oracle: FPC with `uses cwstring`. Its default widestring manager converts
   byte-for-byte regardless of `{$codepage utf8}` or `-FcUTF8`, so stock FPC
   will report divergences that are not divergences.

If (2) finds nothing, the define comes off and `WideString` means UTF-16
everywhere. If it finds a handful, they are ordinary bug tickets and this stays
open behind them. If it finds a lot, the gate was load-bearing and should be
documented as permanent rather than removed.

Blocked by nothing. Low prio on purpose: nothing is broken today in either
setting, and the campaign's goal is met in the default one.

---

## Step 1 was BLOCKED by a bug, and the bug is now fixed (frank-rust, 2026-08-30)

This ticket's step 1 is *"force the define on globally and build the corpus +
`lib/**` + `examples/**`"*. **It could not start.** Under the define, this
four-line program was a hard compiler error:

```pascal
{$define PXX_WIDE_PAYLOAD}
program p; uses SysUtils; begin WriteLn(1); end.
```
```
compiler error: UTF-16 width conversion needs builtinwide (widestring with no RTL?)
```

`lib/rtl/sysutils.pas` has widestring functions, so under the define its own
body needs a transcoder — and `builtinwide` is pulled by a token scan in
`pasparser_prog.inc` that **sees the PROGRAM's tokens and not its used units'**.
Adding `var w: WideString` to the *program* made the identical build succeed,
which is what identified the scan's SCOPE as the cause rather than anything in
sysutils. `IRStrWidthConv`'s comment called this *"unreachable through a normal
compile"*, which was true before the define existed and false after it.

**The define gated its own blocker**, which is why this went unmet: without it
`widestring` IS `ansistring`, `dstWide = srcWide`, and no conversion is ever
synthesised. Nothing could find this except an attempt to do exactly step 1.

**That is worth separating from an ordinary coverage gap when this decision is
weighed** (frankA's framing, and it is the better one): this is not a missing
test, it is a region of the product **no test could reach from outside the
define**. Every suite we run is a default build, so the entire `PXX_WIDE_PAYLOAD`
side is unexercised by construction — and the one bug found there so far was
found by trying to use it, not by testing it. Whatever else step 1 reports, it
should be read as *first contact* with that side, not as a regression sweep over
it.

**Fixed:** under `PXX_WIDE_PAYLOAD` the driver pulls `builtinwide`
unconditionally. That is the same trade the scan's own note already makes — *"a
false positive costs 4 KB"* — at a setting where it is not close, since the
alternative is scanning every used unit's source before parsing it. Default
builds are byte-identical: measured, `uses SysUtils` without the define produces
the same 286488B of code as before. Test
`test/test_wide_payload_pulls_builtinwide_for_a_used_unit.pas`, whose body
deliberately does not name WideString, because naming it is what used to be
required.

## What step 1 now actually reports, on one corpus

`fcl-xml`'s DOM (`uses dom;`), which is rung 3 of [[feature-pascal-corpus-oop]]:

| build | first wall |
| --- | --- |
| default | `PWideChar(...)` refused at `xmlutils.pp:285` — the deliberate refusal, see below |
| `PXX_WIDE_PAYLOAD` | `xmlutils.pp:760`, `"List": no such member` — `TList.List`, an RTL gap, Track B |

So on this corpus the define is **not costing anything and is buying 475 lines**:
it goes further with the define than without it. That is one data point, not the
sweep step 1 asks for — and note it is an ASCII-clean measurement of *reach*, not
of correctness, so it does not touch this ticket's rule 3.

## A new consumer, which raises the value of retiring the gate

[[bug-p-a-property-in-an-interface-declaration-is-rejected]]'s corpus work added
`PWideChar(x)` as a cast, and it is **allowed only under the define** — measured,
not assumed. On `'hi'` in a default build `w[1]` is 104 in both pxx and FPC
(indexing steps one byte through the UTF-8 payload and widens, right for ASCII by
construction), but `PWideChar(w)[0]` steps TWO bytes and yields 26984 (`$6968`,
the pair packed) where FPC gives 104. The cast does not inherit the existing
divergence — it introduces a NEW one, on plain ASCII. So it refuses without the
define rather than producing a plausible wrong value.

That makes `PWideChar` the first construct that is **flatly unavailable** in a
default build rather than merely different in it, which is a change in kind for
this decision: previously both settings were self-consistent and neither was a
bug.
