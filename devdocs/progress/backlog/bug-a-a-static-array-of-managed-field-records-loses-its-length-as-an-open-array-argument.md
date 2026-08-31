---
track: A
prio: 45
type: bug
blocked-by: []
summary: "A static array whose element is a record WITH A MANAGED FIELD, passed to an open-array param, arrives with no length header: High(items) is -1 (FPC: 1) and the callee's loop silently never runs. Both ir.inc copy-in paths exclude managed-field records by an explicit `not (tyRecord and RecordHasManagedFields)` guard, and the fall-through passes a bare address rather than refusing. Plain-record elements work; `const` and `var` both fail; pre-existing on pinned."
status: new
owner: frankS
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
