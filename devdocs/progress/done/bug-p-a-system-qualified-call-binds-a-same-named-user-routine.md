---
summary: "`System.Delete(s,2,3)` binds a unit-level `Delete` instead of the builtin — the documented escape hatch for a shadowed intrinsic does not escape"
type: bug
prio: 45
track: P
owner: claude-A-P
---

# A `System.`-qualified call binds a same-named user routine

- **Type:** bug (name resolution — Track P, shared `parser.inc`/`symtab.inc`).
- **Status:** done
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

## Resolution — the ticket's guess was right, and the family was 10 shapes, not 2

The ticket predicted the fault was "likelier in the SOFT-intrinsic path — the
`CaseEqual(name, 'Delete') and (FindProc('Delete') < 0)` guards, which run on the
bare name before any qualifier is consulted — than in `MatchProcCall`". Correct,
with one correction: the qualifier IS visible at that point (`qUnit` is set by
`ConsumeUnitQualifier` at the top of the same `tkIdent` block, and the `Finalize`
guard three lines below already consults it). The soft-intrinsic guards simply
never looked at it.

Measured the whole family against `fpc -O- -Mobjfpc` before touching anything.
Ten shapes were wrong, across **two independent dispatch sites**:

| | before | FPC |
| --- | --- | --- |
| `System.Delete(s,2,3)` | error: no overload | `aef` |
| `System.Insert('XY',s,2)` | error: no overload | `aXYbcdef` |
| `System.SetLength(s,3)` | error: no overload | `abc` |
| `System.Str(42,t)` | error: no overload | `42` |
| `System.Move(a,b,4)` | error: no overload | `7` |
| `System.Inc(n)` | **prints `user`, n unchanged** | `6` |
| `System.Dispose(p)` | **prints `user`, never frees** | `freed` |
| `System.Length(s)` | error: no overload | `6` |
| `System.Copy(s,2,3)` | error: no overload | `bcd` |
| `System.Ord('A')` | **prints `user`, returns 97** | `65` |

Three of them fail SILENTLY — `Inc`, `Dispose` and `Ord` call the user routine
and the intrinsic's effect never happens. That is worse than the reported
symptom, and none of the three is in the ticket.

The second site is the reason the ticket's two examples were not the whole
story: `Length`/`Copy`/`Ord` are dispatched on the EXPRESSION path, guarded by
`procIdx < 0` rather than `FindProc(...) < 0`, so they needed the same rule
written a second time. `Length`'s guard already carried a partial
`(qUnit = -2) or (FindSym(name) < 0)` escape — the convention existed, it had
just never been applied to the proc half or to the siblings.

### The fix

One helper pair in `symtab.inc` carries the rule instead of thirteen open-coded
copies of it:

```pascal
function SoftIntrinsicOpen(const nm: AnsiString; qUnit: Integer): Boolean;
begin
  SoftIntrinsicOpen := (qUnit = -2) or
    ((FindProc(nm) < 0) and not IntrinsicShadowedByMember(nm));
end;
```

plus `SoftIntrinsicOpenSym` for the older guards that test an in-scope SYMBOL
rather than a method. Applied at every soft-intrinsic guard on the statement
path (Delete, Insert, SetLength, New, Dispose, ReallocMem, Str,
SetSignalHandler, GetMem, FreeMem, Inc/Dec, Include/Exclude, Move/FillChar/
FillByte/FillDWord) and open-coded at the three expression-path guards, which
key on `procIdx` and cannot share the helper.

Only the `System.` marker (-2) opens a shadowed intrinsic. A call qualified by a
NAMED unit (qUnit >= 0) is unchanged — it asks for that unit's routine by
construction — and so is every unqualified call.

## Verified

All ten rows match `fpc -O- -Mobjfpc` byte for byte, and so do the controls that
matter more: unqualified `Delete`/`Inc`/`Length`/... still bind the user routine,
and an unqualified call inside a method still binds the METHOD while
`System.Delete` gets past it. `test_system_qualified_intrinsic.pas` +
`.expected` covers all of it.

**Also wired `test_method_shadows_builtin.pas` into `make test`.** It was added
by [[bug-p-a-class-method-does-not-shadow-a-builtin-of-the-same-name]] with an
`.expected` file and named in that ticket's Gate line, but no Makefile rule was
ever added and the harness auto-discovers nothing in the test directory — so the
sibling fix has been ungated since it landed. It passes.

Self-host fixedpoint converged; `tools/gate.sh quick` GREEN.

## Log
- 2026-08-16 — resolved.
- 2026-08-16 — resolved, commit 1a35d9095.
