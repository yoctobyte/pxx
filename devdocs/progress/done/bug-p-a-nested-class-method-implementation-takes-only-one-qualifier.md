---
track: P
prio: 35
type: bug
blocked-by: []
summary: "`function touter.tinner.Tag: string;` — the implementation header of a method belonging to a NESTED class — is a parse error: the header parser takes one qualifier. Declaring and implementing such a method inline works, so this is the out-of-line spelling only."
status: done
owner: claude-A-P
---

# A nested class's method implementation takes only one qualifier

- **Type:** bug (refusal, FPC-compat) — **Track P**, in the shared
  `compiler/parser.inc`.
- **Found:** 2026-08-16, while fixing
  [[bug-a-duplicate-class-name-check-is-scope-blind]] — nested class TYPES are
  now scoped correctly, and this is the one spelling that still refuses.

## Measured

```pascal
type
  touter = class
  type tinner = class
    function Tag: string;
  end;
  end;
function touter.tinner.Tag: string; begin Result := 'outer'; end;
```

```
pascal26:16: error: unexpected token   (Expected: :, but got: .)
```

FPC 3.2.2 compiles it. `var a: touter.tinner`, `touter.tinner.Create` and the
fields all work as of the fix above — this is only the out-of-line
implementation header.

## Where

The implementation-header parser reads `Name.Method` and stops; a second dot
is not expected. It should walk the same nested-type registry the type and
constructor paths now use (`FindNestedType`, `compiler/parser.inc`), taking
qualifiers until the last one, which is the method name.

## Why it is filed rather than folded in

It is a different parser (declaration headers, not expressions or type names),
and the fix it belongs with was already three sites wide. Keeping it separate
keeps that one reviewable — and this refuses loudly, which is the safe failure.

## Gate

Extend `test/test_nested_class_type_scoping.pas` with an out-of-line method on
each of the two `tinner` classes, asserting each returns its OWN tag (that is
also what proves the qualifier picks the right class, not just that it parses);
diff against FPC; `tools/gate.sh quick`.

## Resolution — the header was one of THREE sites that stopped at one level

Fixed as filed, then the sibling check ("if you fix a bug on one arm of a double
case, grep for the sibling") turned up two more. The ticket says the type and
constructor paths "work as of the fix above" — true, but only to depth ONE, which
is as deep as that fix's tests went. So a doubly-nested class could be declared
and its methods implemented, and still not be named or constructed:

| depth-3 spelling | before |
| --- | --- |
| `function tthree.tmid.tleaf.Tag: string;` | parse error (this ticket) |
| `var c: tthree.tmid.tleaf;` | `error: unknown type:` |
| `tthree.tmid.tleaf.Create` | `error: class method not found: Create` |

All three are the same concept — *every qualifier but the last names a SCOPE* —
written three times, and each copy handled one level. Fixing only the header
would have left the feature half-working in a new place, which is exactly what
the `TOuter.TInner.Create` comment complains about.

### The three fixes

1. **Implementation header** (`ParseSubroutine`): after reading a qualifier, loop
   while the next token is a dot and the name just read resolves through
   `FindNestedType` — then it was a scope, so descend and keep reading. Mirrors
   the expression-path walk. Any depth, by construction.
2. **Type reference**: the same loop after the existing single hop. It only
   descends while the next qualifier IS a nested type, so an ordinary
   `TClass.TMember` is untouched.
3. **Constructor**: this was a FIXED three-token lookahead (`. ident . Create`),
   so it could not be turned into a plain loop without changing what gets
   consumed when the run does *not* end in `Create`. It now SCANS the whole
   `. nested . nested ...` run first, requires `Create` after it, and only then
   consumes — nothing is eaten on a non-constructor spelling, so the behaviour
   of every other form is unchanged.

## Verified

`test_nested_class_type_scoping.pas` extended per the Gate line, and then some:
out-of-line `Tag` methods on BOTH same-named `tinner` classes, each asserted to
return its OWN tag (that is what proves the qualifier picks the right class
rather than merely parsing), plus a doubly-nested `tthree.tmid.tleaf` exercising
all three fixed sites — typed var, construction, and an out-of-line method. 9/9,
identical to FPC 3.2.2 on the same source. Makefile assertion updated 5 -> 9.

Self-host fixedpoint converged; `tools/gate.sh quick` GREEN.

## Log
- 2026-08-16 — resolved.
- 2026-08-16 — resolved, commit PENDING-COMMIT.
