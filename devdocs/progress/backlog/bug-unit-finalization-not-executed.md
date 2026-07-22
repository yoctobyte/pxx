---
track: A
prio: 40
type: bug
---

# A unit's `finalization` section is silently never executed

- **Type:** bug — Track A (unit finalization emission; sibling of the fixed
  bug-unit-init-begin-form-not-executed).
- **Found:** 2026-07-22, while fixing the begin-form init bug (its ticket asked
  for finalization to be "checked and either working or ticketed" — it is not
  working).

## Repro

```pascal
unit ufin;
interface
procedure Touch;
implementation
procedure Touch; begin end;
initialization
  writeln('init runs');
finalization
  writeln('finalization runs');
end.
```

Program using it prints `init runs` / `main done` — the finalization line never
appears. FPC prints `finalization runs` after the main body, in reverse
dependency order.

## Where

`compiler/parser.inc` implementation-scan loop: `ParseInitializationSection`
stops at the `finalization` identifier and the scan's fall-through skips its
tokens one by one. There is no exit-chain hook: fixing this needs (1) parsing
the section into a synthesized `__fini_<unit>` proc like `__init_<unit>`, and
(2) an exit path that runs registered finalizers in REVERSE init order —
including on `Halt`, which is where FPC runs them too.

## Why prio 40, not 60
Same silent-drop shape as the init bug, but finalization sections are far rarer
in real code (none in-tree today), and the missed work is cleanup at process
exit, which the OS mostly reclaims anyway. Escalate if a real consumer appears.

## Acceptance
- The repro prints the finalization line after the main body.
- Reverse-dependency-order test (mirror of test_unit_init_begin_form).
- Runs on `Halt(n)` too.
- Gate: `make test` + self-host byte-identical.
