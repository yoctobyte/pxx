---
track: P
prio: 50
type: bug
status: done
found: 2026-11-10
found-by: claude (the reverse order of bug-p-a-var-may-redeclare-a-string-const-type-or-routine-of-the-same-name)
blocked-by: []
---

# A const or a type may redeclare a var declared before it

## Defect

The var check (5f11a77638) refuses a `var` that repeats a name of its own
scope. The other order went through: a const or a type declared AFTER a var,
string const or set const of the same name, in the same scope. fpc refuses
all of them ("Duplicate identifier"). pxx kept both and the later one won, so
the earlier name read as something else with no diagnostic.

    var tel: AnsiString;
    const TEL = 'telegram';   { accepted; fpc: duplicate identifier }

## Fix

- symtab.inc `VarNameTakenHere(name, anyCaseSyms, withTypes, withRoutines)`.
  The var site passes (False, True, True), which is unchanged.
- The const site in ParseConstSection, outside class/record bodies, passes
  (True, True, False). It matches symbols in any spelling, because a string
  const is not a symbol and CaseDupRefuse never sees that pair. After the
  report the name is renamed `$dup`, so a const that IS a symbol (ordinal,
  typed) is not reported a second time by CaseDupRefuse.
- The type site in ParseTypeSection, outside class/record bodies, passes
  (True, False, False). It is not checked against other types, because a
  forward class declaration states its name twice.
- Neither the const nor the type site is checked against routines: forward and
  interface declarations live in that table, and no cost has been measured
  there.
- System's predeclared consts (below SysConstSymTop: MaxInt, MaxSmallInt,
  StdErr ...) are outside both this check and CaseDupRefuse. A program may
  redeclare them in any spelling. fpc's tests/test/cg/tcase2.pp does
  (`const maxsmallint = high(smallint)`), and every pxx before this fix
  refused it through CaseDupRefuse.

## Census

5,082 files (test/, examples/, lib/, fpc-testsuite, rtl-generics, synapse)
plus the compiler self-host found one hit: tcase2.pp, which was the
SysConstSymTop false positive above and is fixed. There were no real
duplicates.

## Found on the way

The shadowing control turned up
bug-p-a-local-string-const-does-not-shadow-an-outer-var (fixed in the same
commit).

## Tests

- test/test_a_const_or_type_may_not_redeclare_a_var_declared_before_it.pas:
  must fail with exactly 7 messages. fpc also reports 7.
- test/test_a_const_or_type_may_shadow_a_name_of_an_outer_scope.pas (+
  .expected = fpc's output): inner const and type reuse, a forward class
  with a nested type named like a global var, and System's consts
  redeclared.
