---
summary: "`System.Delete(s,2,3)` binds a unit-level `Delete` instead of the builtin — the documented escape hatch for a shadowed intrinsic does not escape"
type: bug
prio: 45
track: P
---

# A `System.`-qualified call binds a same-named user routine

- **Type:** bug (name resolution — Track P, shared `parser.inc`/`symtab.inc`).
- **Status:** backlog. **Pre-existing** — identical on the pinned binary.
- **Found:** 2026-08-16, checking the sibling shapes before closing
  [[bug-p-a-class-method-does-not-shadow-a-builtin-of-the-same-name]].

## Repro

```pascal
program q;
procedure Delete(i: Integer); begin writeln('unit ', i); end;
var s: string;
begin
  s := 'abcdef';
  System.Delete(s, 2, 3);     { must be the BUILTIN }
  writeln(s);
end.
```

| | result |
| --- | --- |
| FPC | `aef` |
| pxx | `error: no overload of Delete matches these arguments` / `candidates: Delete(Integer)` |

The same happens for `System.Dispose(p)` with a unit-level `Dispose` in scope:
it calls the user routine and prints garbage rather than freeing.

## Why it matters more than the repro suggests

`System.X` is **the** documented way out of exactly this situation: shadow an
intrinsic deliberately, then reach the original where you still need it. FPC
code does this routinely. And the shadowing surface just grew — the class-method
fix above makes more names shadow builtins, so more programs will need the
escape hatch that does not work.

`MatchProcCall` already has the machinery: its `suppressBuiltin` parameter is
documented as "a `System.X` call (qUnit = -2) passes suppressBuiltin=False so
the intrinsic still wins". That is the intended behaviour, so the fault is
likelier in the SOFT-intrinsic path — the `CaseEqual(name, 'Delete') and
(FindProc('Delete') < 0)` guards in `parser.inc`, which run on the bare name
before any qualifier is consulted — than in `MatchProcCall` itself. Check
whether the qualifier is even visible at that point; if not, that is the fix.

## Gate

The repro plus the `Dispose` variant matching `fpc -O- -Mobjfpc`; the existing
`test_method_shadows_builtin.pas` extended with the qualified rows it currently
has to avoid; `gate.sh quick`; self-host fixedpoint.
