---
slug: refactor-p-the-frozen-string-cap-travels-to-its-sizer-in-a-global-whose-window-nobody-enforces
title: "`SizeOfSlot`'s two arguments arrive from a call and a global, coupled only by a window"
track: P
prio: 45
type: refactor
status: backlog
owner: ""
blocked-by: []
summary: "ROUTE 4 OF THE (kind, companion) TAXONOMY, AND THE ONLY ROUTE WHOSE INVARIANT HAS NO OWNER. `SizeOfSlot(tk, cap)` and `TypeStorageSize(tk, recId)` take a kind and a companion that the CALLER assembles from two independent lookups. Eleven of the thirteen `SizeOfSlot` call sites take both halves from ONE indexed carrier (`Syms[sci].ElemType` with `SymStrCap[sci]`, `AliasTk[ai]` with `AliasStrCap[ai]`), so a mismatched pair is not expressible. TWO DO NOT: `pasparser_expr.inc:3663` reads `LastTypeStrCap` -- a global -- beside a kind returned by `ParseTypeKind`, and `pasparser_decl.inc:1033-1044` captures `LastTypeStrCap`/`LastTypeRecId` into locals immediately after its own `ParseTypeKind()` and sizes from those. BOTH ARE CORRECT TODAY. What couples the pair at both is a TEMPORAL WINDOW -- the global is valid only until the next declaration parse -- and nothing enforces it, nothing names it, and neither `SizeOfSlot` nor `ParseTypeKind` can detect a violation, because a stale cap is a VALID Integer and produces a plausible width. THE WINDOW HAS ALREADY BEEN VIOLATED ONCE, WITH A SILENT WRONG VALUE: `ArrTypeElemStrCap`'s declaration comment (defs.inc:6388) exists because `array[..] of string[N]` read the cap at a USE of the alias, far from where `string[N]` was parsed, where `LastTypeStrCap` is 'whatever the last unrelated declaration left behind' -- [[bug-a-nd-array-function-result-indexes-the-wrong-slot]], prio 50, fixed by giving that element its own carrier rather than by tightening the window. So the pattern's failure mode is measured, not hypothetical, and the fix that worked was A DEDICATED CARRIER. NOT A GATE ROW: the defect is not mechanically checkable at the call site, which is exactly what distinguishes routes 4-5 from 1-3 -- the discriminator is whether the companion is reachable from the same expression that produced the kind, and here it is not. APERTURE: 'both correct today' is a claim about the thirteen call sites enumerated by grep on 2026-09-06 at 9c217657e, not about any target or any runtime path; a caller added between a `ParseTypeKind` and its read would not fail any existing test."
---

# The cap and the kind arrive by different roads, and only a window joins them

- **Type:** refactor (a latent-defect shape with a measured precedent) — **Track P**
- **Found:** 2026-09-06, sweeping the record-sizing arms for a peer's
  (kind, companion) question. Route 4 of 5.

## The two sites

```pascal
{ pasparser_expr.inc:3663 -- reads the global AT USE }
szDeclTk := ParseTypeKind;
if (szDeclTk = tyRecord) and (LastTypeRecId <> REC_NONE) then
  prevTok := RecSize(LastTypeRecId)
else
  prevTok := SizeOfSlot(szDeclTk, LastTypeStrCap);

{ pasparser_decl.inc:1033 -- CAPTURES into locals first, which is the safe form }
fileElemTk  := ParseTypeKind();
fileElemRec := LastTypeRecId;
fileElemCap := LastTypeStrCap;
```

The second is what discipline looks like and nothing makes it the rule. Both
read three globals that `ParseTypeKind` set as a side effect; the first reads
them at the point of use, the second within three lines of the call.

## Why this is not the other four routes

| route | pair comes from | checkable at the call site? |
| --- | --- | --- |
| 1 same record | one `Syms[i]` / `Alias*[ai]` | yes — a mismatch is not expressible |
| 2 same lookup pair | two arrays, one index | yes |
| 3 paired resolver | one function returning both | yes |
| **4 parameter + global** | **a call, and a global channel** | **no** |
| 5 state machine | the parse's own history | no, but it has ONE owner |

Route 5 at least has a single owner for its history. **Route 4's invariant has
none**: the setter is `ParseTypeKind`, the reader is any caller, and the
contract between them is a comment in `defs.inc`.

## The fix that already worked once

Not a gate row and not a tighter window — **a dedicated carrier**, which is what
`ArrTypeElemStrCap` is and why it exists. The same move applies here: have
`ParseTypeKind` return the cap (or fill a small record) rather than leave it in
a global for the caller to pick up in time.

## Done when

`SizeOfSlot`'s companion is reachable from the same expression that produced its
kind at all thirteen call sites, so route 4 is empty and the taxonomy's
unmechanisable half is routes 5 only.
