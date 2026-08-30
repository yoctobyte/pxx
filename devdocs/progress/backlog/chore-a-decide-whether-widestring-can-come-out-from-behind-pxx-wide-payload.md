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
