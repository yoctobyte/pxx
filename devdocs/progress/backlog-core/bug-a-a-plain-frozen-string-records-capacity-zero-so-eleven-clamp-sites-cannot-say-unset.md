---
track: A
prio: 45
type: bug
status: open
created: 2026-09-03
found-by: frankA
owner: ""
blocked-by: []
summary: "AllocVar and AllocParam both spell `if TypeIsFrozenString(tk) and (tk
  <> tyString) then SymStrCap := LastTypeStrCap`, so a PLAIN frozen `string` is
  left at 0 on purpose and eleven downstream sites turn that 0 into
  DEFAULT_STR_CAP. The substitution is CORRECT for it -- measured, under
  -uPXX_MANAGED_STRING a `var s: string` with a 300-char store gives Length 255
  and an intact neighbour. The cost is that 0 now means two things, so a
  `string[N]` whose N was LOST is indistinguishable from a plain string, and
  every future missing carrier is a silent buffer OVERRUN rather than a
  diagnostic. Three have been found one at a time. THE SYMBOL HALF IS DONE
  (b84e73e53): AllocVar and AllocParam now record DEFAULT_STR_CAP for a plain
  frozen `string`. Behaviourally neutral in all three modes -- the readers find
  recorded what they were substituting -- and proven LIVE rather than assumed,
  by poisoning the value to 99 and watching `var s: string` report len=99
  high=99 under -uPXX_MANAGED_STRING. IT ENABLES NOTHING YET AND NO READER MAY
  BE MADE STRICT: the FIELD and ELEMENT carriers still write 0, and TWO SITES IN
  ir.inc DEPEND ON THAT 0 AS A MEANING -- 2638 selects the plain-string stride
  on it, 11216 the deliberate no-clamp, both saying so in their own comments --
  so recording 255 in RecFieldStrCap without converting them changes a stride
  and turns a no-clamp into a clamp. What is left, in order: (1) the
  array-element and record-field carriers, (2) convert those two ir.inc sites to
  ask the KIND rather than the zero, the shape SizeOfSlot already uses, and only
  then (3) let the eleven refuse instead of guessing."
---

# A plain frozen `string` records capacity 0, so eleven clamp sites cannot say "unset"

Split out of
[[bug-a-a-store-through-a-pointer-loses-the-shortstring-capacity-clamp]]
(closed), whose store fix landed and whose third and largest finding is this.

## The overload, and it is deliberate

`symtab.inc` `AllocVar` (4706) and `AllocParam` (5008), identical text:

```pascal
if TypeIsFrozenString(tk) and (tk <> tyString) then
  SymStrCap[SymCount] := LastTypeStrCap;
```

A plain frozen `string` is left at 0 **on purpose**, and eleven downstream sites
turn that into a capacity:

| where | sites |
| --- | --- |
| backend clamp helpers | 7 — `ir_codegen.inc`, i386, aarch64, arm32, riscv32, xtensa, wasm32 |
| `pasparser_decl.inc` | 3 |
| `symtab.inc` `FrozenStrSlotSize` | 1 |

each spelling `if cap <= 0 then cap := DEFAULT_STR_CAP`.

**And that substitution is correct.** Measured, not read off the guard: under
`-uPXX_MANAGED_STRING` (the frozen model, the self-host build), `var s: string`
with a 300-character store comes back **Length 255 with the neighbour intact**.
255 really is that type's capacity.

## Why it is still a defect

Because 0 now carries two meanings and only one of them is a real answer, so
the eleven readers cannot separate

- *plain frozen `string` — 255 is right*, from
- *`string[N]` whose N was never recorded — this store is about to run past the
  slot.*

The write direction makes the second one a **silent overrun rather than a
diagnostic**, which is why three of these have been found one at a time
(`a[0] :=`, `r.f :=`, `p^ :=`). This is
[[a-flag-whose-default-is-a-real-answer-cannot-say-not-applicable]] with a
memory-safety consequence.

**Do not "fix the eleven".** They cannot decline while the writer overloads the
encoding — making them refuse would break every plain frozen string.
`SizeOfSlot` is not a counterexample to that: it keys on the destination KIND
(`TypeIsFrozenString(tk) and (cap > 0)`, falling back to `TypeSlotSize(tk)`),
not on the zero, which is precisely the bit the eleven do not have.

## The fix, and its risk

Record `DEFAULT_STR_CAP` for `tk = tyString` at both allocators. Then 0 means
*unset* everywhere, the eleven substitutions become dead for every legitimate
case, and each can become a diagnostic.

**Two sites, not eleven** — [[a-count-that-grows-under-enumeration-means-the-fix-is-in-the-wrong-place]],
guard the few writes rather than the many reads. `pasparser_proc.inc:2177`
already guards on `> 0` and needs no change.

The risk is not the edit, it is the blast radius: every consumer of `SymStrCap`
for a plain frozen string sees 255 where it saw 0, and some guard on `> 0`
(`pasparser_expr.inc` 5522 and 5735 do). So it wants its own change, its own
sweep of those readers, and a control — not a ride-along.

**The two writer sites were found by an edit that ASSERTED its match was unique
and failed.** Identical text in `AllocVar` and `AllocParam`; a replace without
the assert fixes one arm and leaves the other, which is the double case
`normalise-dont-special-case.md` is about.

## Gate

`test_shortstring_cap_through_a_pointer.pas` (seven rows, native + i386 +
aarch64 + arm32 + riscv32) and `test_shortstring_trunc.pas` are the rows a
change here can regress; the frozen model (`-uPXX_MANAGED_STRING`) is where a
plain `string` is frozen at all and is where the 255 has to keep working.

## Half done, 2026-09-03 — the SYMBOL writers, and why that enables nothing yet

Both writer sites now record the real capacity:

```pascal
if TypeIsFrozenString(tk) then
begin
  if tk = tyString then SymStrCap[SymCount] := DEFAULT_STR_CAP
  else SymStrCap[SymCount] := LastTypeStrCap;
end;
```

**Behaviourally neutral in all three modes** (default, `-uPXX_MANAGED_STRING`,
`-dPXX_SHORTSTRING`) — the readers substitute the same 255 they now find
recorded — and `gate.sh quick` GREEN with `test_shortstring_cap_through_a_pointer`,
`test_shortstring_trunc` and the frozen-model rows unchanged.

**PROVEN LIVE, because a change that measures as no change is otherwise
indistinguishable from an unreached edit.** Poisoned to `99` and rebuilt: under
`-uPXX_MANAGED_STRING` a `var s: string` reports `len=99 high=99` and a `string`
PARAMETER reports `high=99`. So both writers are reached and both are read, by
the clamp and by `High`. Restored, and the restored binary's sha matches the
pre-poison one.

### It enables NOTHING yet, and nobody may act as if it does

The eleven `if cap <= 0 then cap := DEFAULT_STR_CAP` sites do not read
`SymStrCap` alone — they take a capacity from whichever carrier the shape
provides, and **the FIELD and ELEMENT carriers still write 0 for a plain frozen
string.** So the overload is halved, not removed, and no reader can be made
strict.

Worse than "not yet": **two sites in `ir.inc` deliberately depend on the 0**,
which this ticket did not know when it was filed —

- `ir.inc:2638` — `if ... RecFieldStrCap(...) > 0 then elemSize :=
  FrozenStrSlotSize(...) else <the plain-string stride>`, with the comment
  *"RecFieldStrCap answers 0 for a genuine bare `string` field, so that keeps
  the existing stride."*
- `ir.inc:11216` — the record-field store clamp, *"RecFieldStrCap answers 0 for
  a plain `string` field, which is the existing no-clamp behaviour."*

Both branch on `0` as a MEANING. Recording 255 in `RecFieldStrCap` without
converting them changes a stride (`FrozenStrSlotSize(tyFixedString, 255)` is
not the same number as the plain-string arm's `STRING_CAP + 8` /
`LOCAL_STR_CAP + 8`) and turns a deliberate no-clamp into a clamp. That is a
real behaviour change and it is the work that remains.

### What remains, in order

1. `ArrTypeElemStrCap` (`pasparser_decl.inc` 6553/6631) and the record/class
   field capacity, both of which currently write 0 for a plain frozen string.
2. Convert `ir.inc:2638` and `ir.inc:11216` to ask the KIND rather than the
   zero — `SizeOfSlot` already shows the shape (`TypeIsFrozenString(tk) and
   (cap > 0)`, falling back on the kind).
3. Only then may any of the eleven refuse instead of substituting.

Doing 1 without 2 is a silent stride change. Doing 3 before both is a compiler
that rejects every plain frozen string. The symbol half is landed on its own
because it is the one piece that is true in isolation: 255 really is a plain
frozen `string`'s capacity, so recording it is a more truthful encoding than
recording its absence — measured, not assumed.
