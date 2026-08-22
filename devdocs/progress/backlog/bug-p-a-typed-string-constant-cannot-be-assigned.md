---
track: P
prio: 35
type: bug
blocked-by: []
summary: "`const S: string = 'a'; ... S := 'b';` is `undefined variable (S)`, though the same assignment works for a typed Integer, Char or ARRAY constant. Typed consts are writable here (fpc's default in non-Delphi modes) for every type except string, which is registered as a read-only literal alias with no storage."
status: backlog
---

# A typed string constant cannot be assigned

Found 2026-08-22 by an FPC differential sweep over less-trodden language
features (`fpc -Mobjfpc -O1` 3.2.2 vs pxx `015bbbaf2`).

## The measurement

`{$WRITEABLECONST ON}` in every row (it is FPC's default outside `{$MODE
DELPHI}`, and pxx ignores the directive entirely — see below).

| declaration + assignment | fpc | pxx |
| --- | --- | --- |
| `const N: Integer = 0;` then `N := 1` | ok | ok |
| `const C: Char = 'x';` then `C := 'y'` | ok | ok |
| `const A: array[0..2] of Integer = (1,2,3);` then `A[1] := 9` | ok | ok |
| `const S: string = 'a';` then **read** `S` | ok | ok |
| `const S: string = 'a';` then `S := 'b'` | ok | **`undefined variable (S)`** |

So one type out of four, and the failure is a name-resolution error rather than
a "cannot assign to a constant" diagnostic — which is the tell that the constant
has no storage at all rather than a read-only one.

## Root cause

`ParseConstSection` (`compiler/pasparser_decl.inc`) registers a typed string
constant in the **StrConst** table, not as a variable, and its own comment says
why:

> Treated as a read-only string-literal alias — registered in the StrConst table
> exactly like the untyped `const Name = 'literal'` path, with NO storage var (a
> phantom var would shadow a same-named variable and ParseInitVal has no string
> case).

Both reasons are real. A use of the name expands to an `AN_STR_LIT` over the
source span, which coerces to a managed string wherever one is wanted — that is
why READING works and only the store fails.

## What a fix has to deal with

Allocating a real global for a typed string const means:

1. **Initialisation.** `ParseInitVal` has no string case; the literal has to
   become a managed-string assignment run before the main body, alongside the
   existing `LocalInitCount` typed-const initialiser mechanism for
   routine-locals.
2. **Shadowing.** The comment's hazard is
   `bug-set-of-char-const-corrupts-char-codegen`'s shape: a phantom var matching
   case-insensitively against a same-named variable. Registering the storage
   under a mangled key and resolving the NAME through the const table (as class
   consts already do via `ClassConstMangle`) sidesteps it.
3. **The untyped form must not move.** `const Name = 'literal'` (no type) is a
   literal alias in FPC too and must stay one — only the TYPED form gets
   storage. That distinction is already visible at the declaration site.

## A related, separate question for Track U

**`{$WRITEABLECONST}` is not implemented at all** — grepping the compiler finds
no reference. So typed consts are unconditionally writable here for the types
that have storage, and unconditionally unwritable for strings; the directive
that is supposed to decide it does nothing either way. Whether pxx should honour
`{$WRITEABLECONST OFF}` (and refuse the store with a proper diagnostic) or
document typed consts as always writable is a dialect call, not a bug fix —
file `decide-writeable-const-directive` if the taker wants it settled first.
Fixing the string case is worth doing regardless, since it only removes an
inconsistency between types.

## Gate

The five rows above matching `fpc -O1`, a read of the const still producing the
literal (no regression in the many places `const S: string = ...` is read), and
self-host byte-identical.
