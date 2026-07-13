---
prio: 0
---

# REJECTED — "a method's local is not registered" — my evidence was wrong

- **Type:** bug report — **WITHDRAWN 2026-07-13, same session it was filed.**
- **Track:** P
- **Status:** rejected. The claim was false. Kept, not deleted, because HOW it was false is
  the useful part.

## What I claimed
That inside `TTestString.TestFormat` (fcl-json's suite) the local `S : TJSONString` was never
registered, and `S` bound instead to an unrelated `skParam` of type AnsiString at symbol index
172 — i.e. name resolution silently binding to the WRONG SYMBOL. I filed it urgent (prio 70)
because that mechanism, if real, would silently read and write the wrong variable in any program.

## Why it was wrong
The instrumentation was gated on `CurTok.Line` being in the 1700–1740 range. **Line numbers are
per-FILE and collide across units.** Those `S`-is-an-skParam hits were from a DIFFERENT unit
(fpjson / fpcunit / the RTL), not from testjsondata at all. I read them as if one file were being
parsed.

Re-instrumented, gated on `CurProc` instead (a routine index is globally unique, a line number is
not):

```
DBG S idx=257 tk=6 rec=86 kind=0        { tyClass, TJSONString, skLocal — CORRECT }
```

The local IS registered and DOES resolve. `FindSym` walks the hash chain newest-first and finds
it, block-visible. The `CurProc = -1` var section I also pointed at was a BUILTIN unit's
pre-scan, again matched only by line-number coincidence.

## The lesson, which is the reason this file still exists
**A line number is not an identity.** Every diagnostic in this compiler that keys on
`CurTok.Line` to decide "am I in the interesting place" is unreliable the moment more than one
file is in play — which is always. Gate instrumentation on something globally unique: `CurProc`,
a symbol index, a token SOffset (see [[project_decl_order_soffset_not_token_index]], which is the
same lesson about token INDICES).

This is the second time tonight that reading a line number as a location cost real time — the
first was the drifting `pascal26:NNNN` in error messages, which is why `WriteTokenContext` exists.
I knew that, and still keyed a debug print on a line range.

## What is actually true, and where it went
`S` resolves fine; the real failure in `AssertEquals('...', S.AsJSON, S.FormatJSOn)` is in the
member access on it, and it is DECL-ORDER dependent (moving the method to the end of the
implementation section makes it compile). That live finding is recorded in
[[feature-pascal-corpus-fpjson]], which is where it belongs — it is a corpus wall, not a
general scoping bug.
