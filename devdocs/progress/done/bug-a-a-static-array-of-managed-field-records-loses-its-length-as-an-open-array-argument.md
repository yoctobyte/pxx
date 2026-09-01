---
track: A
prio: 45
type: bug
blocked-by: []
summary: "FIXED (e7edc684e): both ir.inc open-array copy-in paths excluded records with managed FIELDS, so the argument fell through to a bare headerless address and the callee's High() answered -1 (FPC: 1) with the loop silently never running; above MAX_OPEN_ARRAY_STACK_TEMP it segfaulted. The exclusion itself was the whole defect — the existing WHOLESALE copy-in/copy-out is already correct for managed-field records, for the same reason it is correct for AnsiString elements, so none of the three fix directions proposed below was needed. Sibling arm of the managed-ELEMENT case fixed earlier. Six targets match the fpc oracle."
status: done
owner: frankA
---

# A static array of managed-field records loses its length as an open-array argument

- **Type:** bug — **Track A** (`compiler/ir.inc`, the open-array copy-in paths).
- **Found:** 2026-08-31 (frankS), probing for a behaviour delta while collapsing
  the durable param row. Not caused by that work — `pinned` does the same.

## Repro

```pascal
type TB = record S: AnsiString; end;
function only(const items: array of TB): Integer;
var k: Integer;
begin
  WriteLn('high=', High(items));
  for k := 0 to High(items) do WriteLn('  [', k, '] ', items[k].S);
  only := 0;
end;
var b: array[0..1] of TB;
begin b[0].S := 'xy'; b[1].S := 'zzz'; only(b); end.
```

| | `High(items)` | body |
| --- | --- | --- |
| pxx | **-1** | never runs |
| fpc 3.2.2 | 1 | prints `xy`, `zzz` |

**Silent.** No error, no crash — the loop simply does not execute, so a callee
that sums, searches or copies returns the empty answer. The first shape I hit it
in did crash (`Length(items[k].S)` over a garbage High walked off the end), which
is the lucky case.

## Controls, all run

| variant | result |
| --- | --- |
| element record has **no** managed field (`N: Integer`) | `high=1`, correct |
| `var items: array of TB` instead of `const` | same failure |
| `pinned` | same failure — pre-existing, not a regression |
| overload selection between `array of TA` and `array of TB` | **correct** — not the overload matcher |

So the discriminator is exactly "the element record has a managed field".

## Suspected site

`compiler/ir.inc`, both static-array → open-array-param copy-in paths, which
each gate on

```pascal
if oaEligible and
   not ((caElemTk = tyRecord) and RecordHasManagedFields(caElemRec)) then
```

The exclusion is deliberate and its reasoning is written down (a field-wise
release in the callee would need the copy-out to be field-aware). What is not
deliberate is the **fall-through**: an excluded argument does not get refused, it
takes the generic path, which passes a bare static-array address with no
`[len:8]` header — and `High` reads `[data-8]`.

## Fix direction, not yet chosen

1. **Refuse it**, so the exclusion is honest. Cheapest; turns a silent wrong
   answer into a diagnostic. FPC accepts the program, so this is a compat
   regression we would be choosing.
2. **Header without copy** for the `const` case: the callee only reads, so
   borrow the caller's elements and synthesize just the length header. Does not
   need the field-aware copy-out the exclusion was protecting.
3. Make the copy-out field-aware. Biggest, and only option 3 also fixes `var`.

Option 2 looks like the right first step and covers `const`, which is the
common shape; `var` then still needs 1 or 3. Decide with a measurement of which
shape real code uses, not here.

## Gate

`make compiler/pascal26` + the repro printing `high=1` and both elements +
the plain-record control still correct + `const` and `var` both covered in one
test file.

## What it actually was — the three fix directions above were all too big

Measured rather than reasoned from the comment: I removed **both** exclusions and
ran it. The wholesale copy-in / copy-out mechanism already handles managed-field
records correctly, so there was no fourth mechanism to build and no compat
regression to choose. **The exclusion was the entire defect.**

The comment's premise — "a field-wise release in the callee would need the
copy-out to be field-aware" — does not survive being run. It is the same shape as
the `AnsiString`-ELEMENT case sitting two paragraphs above it in the same
function, which this path has always allowed: ownership moves as a SET in both
directions, so nothing is ever released field-wise across the boundary. The
comment was describing a hazard that the surrounding design had already removed.

**This was the sibling arm of a half-fixed double case.** The managed-ELEMENT
form had its exclusion removed earlier (`bug-const-open-array-managed-elem-length`,
pinned by `test_const_open_array_managed`). The managed-FIELD form stayed broken
behind the same shape of predicate — the pattern `normalise-dont-special-case.md`
names: the second path is the one that stays broken.

### Arms measured against fpc 3.2.2, all byte-identical

const read · var write-back · two managed fields per record · a dynamic-array
field · a callee copying an element into a LOCAL (the field-wise release the
comment named) · a callee writing only element 0 · the
`>MAX_OPEN_ARRAY_STACK_TEMP` heap-temp path · a raise unwinding out of the callee
while the temp is live. Census `live` flat at 41 while allocations grew
10975 -> 45116: residue, not a leak, and no double free.

Six targets agree: x86-64, i386, aarch64, arm32, riscv32, xtensa. The xtensa arm
needs `--platform=posix --xtensa-soft-mulhigh`; without them it refuses on
`calloc`, which is a target property, not this defect.

### Controls

Built by re-inserting each exclusion and rebuilding — not by changing the input.
Each exclusion **alone** breaks every arm, so both removals were necessary and
neither was carried by the other. Against a compiler with both restored the new
test gives `const sum=0`, no write-back at all, and `rc=139` on the heap path.
The fixed binary reproduced byte-for-byte (`aa86a9a3a88c`) across the round trip.

### Landed

- `compiler/ir.inc` — both exclusions removed; the three comments asserting them
  rewritten, not deleted, since one of them was the reason nobody looked.
- `test/test_open_array_managed_field_record.pas` — new, wired native plus five
  cross-target differential rows.
- `tools/gate.sh quick`: GREEN with the FPC seed canary **PASS**, run before the
  commit while `compiler/` was still dirty so the canary was not skipped.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change: PENDING-COMMIT.
