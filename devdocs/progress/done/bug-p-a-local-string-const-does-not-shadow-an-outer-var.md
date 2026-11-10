---
track: P
prio: 70
type: bug
status: done
found: 2026-11-10
found-by: claude (the shadowing control for bug-p-a-const-or-type-may-redeclare-a-var-declared-before-it)
blocked-by: []
---

# A local string const does not shadow an outer var

## Defect

    var outer: Integer;            { program level, = 1 }
    procedure C;
    const outer = 'inner const';
    begin writeln(outer); end;     { pxx: 1   fpc: inner const }

The program got the wrong value silently. The guard in ParseFactorCore,
"a variable in scope beats an untyped string constant", let a variable at
ANY depth win. It was written while the string-const table was flat and
unscoped. Since bug-pascal-string-const-not-scoped, FindStrConstIn is
innermost-wins, but the guard still threw away an inner const for an outer
var. A one-character const never showed the bug, because it is a char
symbol that FindSym finds.

The set-const path had the same rule (`if idx < 0 then FindSetConstIn`). There
it crashed: `'5' in digs` ran on the global integer `digs` and segfaulted.

## Fix

- symtab.inc `SymScopeHops(idx)` is the symbol twin of ScopeHopsToProc. It
  walks the lexical chain from CurProc, and the first routine whose ScopeBase
  is at or below idx owns the symbol. A global gives MaxInt.
- pasparser_expr.inc has two guards, string and set. The const loses to the
  symbol only when the symbol is at least as inner as the const:
  `SymScopeHops(sym) <= ScopeHopsToProc(const owner)`.

## Test

test/test_a_local_string_or_set_const_shadows_an_outer_var.pas (+ .expected
= fpc 3.2.2's output). It covers a nested routine reading its enclosing
routine's const over a global var, a local var over the enclosing const and
over a global const, an inner const over an enclosing var, and a local set
const over a global integer var.
