---
track: P
prio: 60
type: bug
status: done
found: 2026-10-20
found-by: claude (remote_thermostat, P1 meter tests)
blocked-by: []
---

# A var may silently redeclare a string const, a type or a routine of the same name

The duplicate-identifier check (case-insensitive, "already declared in this
scope") fires for an integer const followed by a var, and for var/var, but not
for several other pairs. pxx then accepts the program, and the later
declaration silently wins: no error, no warning. FPC rejects every case below
with `Error: Duplicate identifier`.

Found with the stable pinned compiler (`stable_linux_amd64/default/pinned`),
x86_64 and riscv32. Cost: a test's 600-byte telegram constant `TEL` read as an
empty string because a later `var ... tel: AnsiString` replaced it; every
check failed with no hint why, and it took a bisect to find.

## Repro

```pascal
program c;
const
  TEL = 'hello';
var
  tel: AnsiString;
begin
  writeln('[', TEL, ']');     { prints [] : TEL is now the empty var }
end.
```

## What pxx does now

| first declaration        | then                 | pxx                   | FPC   |
|--------------------------|----------------------|-----------------------|-------|
| `const X = 5;`           | `var x: Integer;`    | error (correct)       | error |
| `var a: Integer;`        | `var A: AnsiString;` | error (correct)       | error |
| `const X = 'hi';`        | `var x: AnsiString;` | **accepted**, var wins | error |
| `const X = 'hi';`        | `var x: Integer;`    | **accepted**, var wins | error |
| `const X = 'hi';` (local, in a procedure) | `var x: AnsiString;` | **accepted** | error |
| `const X = 5;`           | `var X: Integer;` (same case) | **accepted** (prints 0) | error |
| `type T = Integer;`      | `var t: Integer;`    | **accepted**          | error |
| `procedure P; ...`       | `var p: Integer;`    | **accepted**          | error |

So the check looks like it depends on the kind (and for consts, the type) of
the earlier symbol rather than on the name alone.

## Expected

Any second declaration of a name in the same scope, whatever the kinds, is
the existing error: `duplicate identifier "x": Pascal is case-insensitive, so
it is the same identifier as "X", already declared in this scope`.

## Side note seen while reducing

After a failed compile, the old output binary from a previous successful run
stays in place (pxx exits 1 but does not remove or truncate `-o`), so a
script that ignores the exit code runs a stale program. remote_thermostat's
build.sh already works around this by compiling to a fresh name.

## Resolution (2026-11-10)

`VarNameTakenHere` (compiler/symtab.inc), called for every name in
ParseVarSection, refuses a var whose name is already declared in the SAME
scope by any table: a symbol in the same spelling (a different spelling stays
CaseDupRefuse's, so a pair is reported once), a string const, a set const, a
type alias, or a routine. Scope per table: symbols by InnermostScopeBase,
consts and aliases by owner routine + unit, routines by lexical parent + unit.
It recovers, so one compile reports every duplicate.

    duplicate identifier "tel": already declared in this scope as a string constant

Census before landing: every program in test/, examples/ and lib/ (2,721
files), library_candidates/fpc-testsuite, rtl-generics and external/synapse
(2,361), the compiler itself, remote_thermostat (firmware and its tests) and
museum_landkaart (host, tests, firmware). Five hits, all in our own tests, and
fpc rejects all five with "Duplicate identifier"; renamed:
test_deref_shape_through_arith_and_nonident_base (`pb: PB`),
test_frozen_string_cross_b305 (`pf: PF`), test_ptr_deref_vararg (`pa: PA`),
test_set_of_char_const (`const C` + `var c`), test_subnormal_double_arithmetic
(`function Bits` + `var bits`). No false refusal found.

Tests: test_a_var_may_not_redeclare_any_name_of_its_own_scope (must not
compile; seven messages asserted by text, count = 7) and
test_a_var_may_shadow_a_name_of_an_outer_scope (legal inner-scope shadowing;
output equals fpc's).

Not covered, deliberately, until counted the same way: the REVERSE order (a
type, routine or const declared AFTER a var of the same name) and
same-spelling const/const and type/type pairs. Each needs the same check at
its own declaration site. The side note above (a failed compile leaves the
previous -o binary in place) is separate and still open.
