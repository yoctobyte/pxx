---
track: P
prio: 60
type: bug
blocked-by: []
summary: "A class method named after a builtin does not shadow it inside the class's own methods: TFPObjectList.Remove's unqualified `Delete(Result)` binds to the BUILTIN Delete and fails to compile. lib/rtl/contnrs.pas has not compiled since it landed 2026-07-13; FPC compiles and runs the 15-line repro. Found by Track T once the crtl-map failure stopped masking the step behind it."
---

# A class method does not shadow a builtin of the same name

- **Type:** bug (Pascal frontend — name resolution) — **Track P**
- **Status:** backlog
- **Opened:** 2026-08-16
- **Filed by:** Track T. T owns the tool, never the bug.

## Repro — 15 lines, and FPC disagrees

```pascal
program del;
type
  TL = class
    procedure Delete(i: Integer);
    function Remove(i: Integer): Integer;
  end;
procedure TL.Delete(i: Integer); begin writeln('method Delete ', i); end;
function TL.Remove(i: Integer): Integer;
begin
  Result := i;
  Delete(Result);          { must bind to TL.Delete, not the builtin }
end;
var l: TL;
begin
  l := TL.Create; writeln(l.Remove(7)); l.Free;
end.
```

| | result |
| --- | --- |
| **FPC** | compiles, prints `method Delete 7` then `7` |
| **pxx** | `pascal26:11: error: Delete: string or plain dynamic-array variable expected (dyn-array fields/elements not yet supported)` |

An unqualified call inside a method must resolve against the enclosing class
before the builtin table. pxx reaches the builtin first, and the builtin's
argument check then rejects an `Integer` — so the diagnostic talks about dynamic
arrays, which is true of the builtin and nothing to do with the program.

## What it actually breaks

`lib/rtl/contnrs.pas` does not compile, and has not since it landed on
2026-07-13:

```
lib-units: FAIL contnrs
  pascal26:183: error: Delete: string or plain dynamic-array variable expected
```

Line 183 is `TFPObjectList.Remove` calling its own `Delete(Result)` — the same
shape as the repro, in the shape the FCL actually ships. `KNOWN_BROKEN` in
`tools/lib_units_compile.py` is empty, so this unit is expected to compile.

## Not the pin — verified both ways

The obvious reading of a `lib-test` red is a stale pin
([[task-t-enroll-libtest-demos-watcher]]'s pin-lag caveat: a red means EITHER a
Track B regression OR a stale pin, and those route to different tracks). Checked
explicitly, because a new pin (v341) had just landed:

```
PXX_STABLE=stable_linux_amd64/default/pinned  -> FAIL contnrs
PXX_STABLE=compiler/pascal26  (HEAD)          -> FAIL contnrs
```

Both fail identically, so this is not pin lag and a re-pin will not clear it.

## Why it stayed hidden for a month, which is the interesting part

Nothing about this bug is subtle; the *masking* is. Three layers had to come off
in order:

1. **`lib-test` ran in no tier.** Track B's whole gate executed only when a B
   agent typed it, until it was enrolled in the watcher on 2026-08-14.
2. **Then `crtl-map` failed first.** The `lib-test#00` job runs
   crtl-reachability -> crtl-map -> lib-units in sequence, and
   `compiler/crtl_names.inc` was a stale generated file
   ([[regression-lib-test-crtl-reachability]]). The step never reached
   lib-units.
3. **Only once Track C regenerated the map (`9860b8bf7`) did lib-units run**,
   and it failed on the first unit it could not build.

So the enrolment is peeling an onion, and each red it publishes is a real one
that was previously invisible. Worth expecting one or two more.

A related consequence for anyone reading the tier: `lib-test#00` failing takes
the other 166 jobs with it (they carry `deps:lib-test#00`), which is correct —
they build against artefacts step 00 produces — but it means a single red here
costs the whole target's coverage until it clears.

## Suggested shape, not prescribed

Resolution order inside a method body: enclosing class (own then ancestors) ->
unit scope -> builtins. The sibling arm to grep before closing, per
`normalise-dont-special-case.md`: the same precedence question exists for a
unit-level routine named after a builtin, and for a local variable — if those
take different paths, that is the second path that stays broken.

Related: [[bug-p-scope-hiding-covers-routines-but-not-types-and-classes]] (the
same "flat resolution ignores the enclosing scope" theme one layer up, for
`uses` order), [[bug-a-duplicate-class-name-check-is-scope-blind]] (ditto, for
declarations).
