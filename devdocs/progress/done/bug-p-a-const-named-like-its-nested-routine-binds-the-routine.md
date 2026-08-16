---
summary: "a local const whose name matches its own NESTED routine resolves to the routine's mangled name — `procedure Inner; const inner: integer = 0;` fails with `undefined variable (Inner$13)`"
type: bug
prio: 30
track: P
owner: claude-A-P
---

# A const named like its own nested routine binds the routine

- **Type:** bug (name resolution — Track P, shared `parser.inc`/`symtab.inc`).
- **Status:** done
  binary, so it is not fallout from the static-local-const work that found it.
- **Found:** 2026-08-16, writing the regression test for
  [[bug-p-a-routine-local-typed-const-is-reinitialised-on-every-call]]; the test
  named its inner const after the routine holding it and hit this instead.

## Repro

```pascal
program nst3;
procedure Outer;
const outer: integer = 100;
  procedure Inner;
  const inner: integer = 0;                { same name as the routine }
  begin Inc(inner); write('i', inner, ' '); end;
begin Inc(outer); write('o', outer, ' '); Inner; Inner; end;
begin Outer; Outer; writeln; end.
```

```
pascal26:6: error: undefined variable (Inner$13)
```

FPC compiles and runs it: `o101 i1 i2 o102 i3 i4`.

## Boundary (measured)

| shape | result |
| --- | --- |
| const `inner` inside nested `Inner` | **fails** — binds `Inner$13` |
| const `icount` inside nested `Inner` | ok, matches FPC |
| const `foo` inside NON-nested `Foo` | ok |
| local `var` of the same name inside a nested routine | untested — **check this first** |

So it is specific to a **nested** routine: the mangled name (`Inner$13`) is what
the const's name resolves to, meaning the nested routine's own registration wins
over a const declared inside it. The non-nested case is fine, which says the
mangling — not the shadowing rule in general — is where the two names meet.

## Before closing

Grep the sibling shapes, because a resolution rule fixed on one arm here is
famously still broken on the others
([[project_pascal_name_resolution_has_six_tables]] is the tally): a local `var`
of the same name, a `type`, and a parameter. If they take different paths, that
is the second path that stays broken.

## Gate

The repro above matching `fpc -O- -Mobjfpc` byte for byte, plus whichever
sibling shapes the grep turns up; `gate.sh quick`; self-host fixedpoint.

## Resolution — the ticket's "check this first" row was broken too, and so was a THIRD site

The ticket's boundary table listed a local `var` of the same name as untested
and told the next reader to check it. Measured, with the parameter and type
shapes alongside:

| shape | before | FPC |
| --- | --- | --- |
| `const inner` in nested `Inner` | `undefined variable (Inner$13)` | `o101 i1 i2 o102 i3 i4` |
| `var inner` in nested `Inner` | `undefined variable (Inner$6)` | `i7` |
| param `inner` of nested `Inner` | `undefined variable (Inner$6)` | `i5` |
| `type inner` in nested `Inner` | ok | ok |

Three of four, one mechanism. In `ParseNestedRoutine`'s free-variable scan the
own-name test — *this identifier is the routine's own name, so it is the
function-result variable or a self-recursive call; rewrite it to the mangled
name* — ran **before** the test for the routine's own params and locals. So a
declaration inside the routine that shared its name was rewritten too. Only
`type` escaped, because a type name never reaches the scan as an expression
reference. Non-nested routines were always fine: the mangle is the one thing
their path does not do, which is what the ticket's non-nested row was telling us.

The fix is the reorder: own params/locals/consts are tested first. A function's
RESULT variable is the routine name itself and is never a declared local, so it
cannot be swallowed by the earlier test — asserted by the two controls below.

### The third site, found by the sibling grep the ticket asked for

Writing the sibling-shape case turned up a separate defect at a different site.
The call-site rename pass that rewrites `nestedName` across the parent's whole
range — the one that exists so a SIBLING routine calling this one follows the
mangle (bug-nested-proc-sibling-call-unresolved) — renamed by name blindly. A
sibling declaring a local of that name got its own declaration rewritten:

```pascal
procedure Helper; begin ... end;
procedure User;
var helper: Integer;        { -> `var Helper$357: Integer;` }
begin helper := 5; ... end;
```

`pascal26: error: unexpected token near: procedure User$362 var Helper$357` — a
parse error naming a routine the program never wrote. Fixed with the same rule
at that site: before renaming, collect the spans of sibling routines that
declare the name themselves (walking token by token, so routines nested inside a
sibling are covered), and skip them. New helper `NestRoutineDeclares`.

## Verified

`test_nested_routine_local_shadows_own_name.pas`: all four shapes, the same
shapes while the routine also CAPTURES an enclosing variable (so the shadowed
name and the capture machinery meet in one body), the sibling shape, and two
controls that the reorder could have broken — a function whose body assigns its
RESULT variable, and a capturing self-recursive function whose self-call must
still carry the hidden captured-frame argument. 11/11, identical to
`fpc -O- -Mobjfpc`. Wired into `make test`.

`test_nested_routine_depth2_capture` and `test_nested_proc_sibling_call` both
still produce their recorded output — they are the two tests that exercise the
rename passes this touched.

Self-host fixedpoint converged; `tools/gate.sh quick` GREEN.

## Log
- 2026-08-16 — resolved.
- 2026-08-16 — resolved, commit PENDING-COMMIT.
