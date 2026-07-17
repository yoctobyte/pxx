---
summary: "WideChar var → string still broken in CONCAT (segfault) and as a string ARG (overload error) — only assign was fixed"
type: bug
prio: 48
---

# WideChar variable → string: concat segfaults, arg mis-resolves (assign fixed)

- **Type:** bug (Track A/P — string concat + arg lowering / overload match). Sibling of
  [[bug-pascal-widechar-var-to-string-segfault]] (assign case, fixed `b1cbd204`).
- **Status:** backlog
- **Found:** 2026-07-17, context sweep right after fixing the assign case — a textbook
  demonstration of the shape/context whack-a-mole that
  [[refactor-centralize-managed-string-pchar-conversion]] exists to end.

## Repro

```pascal
procedure show(const s: AnsiString); begin writeln('arg=', s); end;
var s: AnsiString; w: WideChar;
begin
  w := WideChar($41);
  s := w;            { assign  — FIXED, b1cbd204 (prints A) }
  s := 'x' + w;      { concat  — FIXED, this session (single-sided string+ordinal) }
  show(w);           { arg     — STILL OPEN: compile error "Mismatch in MatchProcCall" }
end.
```

**Remaining:** only the ARG/overload case. `show(w)` (widechar var to a `const
AnsiString` param) fails overload resolution — `MatchProcCall` does not treat a tyUInt16
arg as string-compatible. Lower-severity than the crashes (a compile error, not a
segfault); needs the same widechar-string-compat rule at the call site, or the
centralization refactor.

## Root (same family, different sites)

WideChar collapses to `tyUInt16` with no subtype marker (see the assign bug). The
assign path was taught to wrap a `tyUInt16` RHS in `WrapWideCharToUTF8`, but the same
conversion is re-decided independently at:

- **string concat** lowering (`+` with a string and a non-string operand): the
  `tyUInt16` operand is not converted → treated as a pointer/wrong width → crash.
- **argument matching** (`MatchProcCall`): a `tyUInt16` value is not considered
  string-compatible, so `show(w)` fails overload resolution (FPC accepts widechar→string
  implicitly).

Each site re-implements "is this a char-like value that must become a string?" — exactly
the scatter the refactor targets.

## Fix

- **Narrow:** apply the same `tyUInt16 → WrapWideCharToUTF8` conversion at the concat
  site, and make `MatchProcCall` treat a `tyUInt16` arg as string-compatible (wrapping at
  the call site). Point-fixes; more moles will follow.
- **Systemic (preferred):** [[refactor-centralize-managed-string-pchar-conversion]],
  extended to cover the WideChar→string conversion alongside PChar→string. One
  `MaybeConvertToString(node)` keyed on the operand's char-likeness, called from assign /
  concat / arg / return. Kills PChar and WideChar scatter together. **Fourth instance
  this session** — the evidence for centralizing is now overwhelming.

## Acceptance

- All three lines above work (or arg errors cleanly, never the concat segfault); a
  `test/test_*.pas` regression per context.
- Gate: `make test` + self-host byte-identical.
