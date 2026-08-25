---
slug: bug-p-a-class-const-cannot-take-the-address-of-a-sibling-class-const
title: "A typed class const initialised with `@SiblingClassConst` desyncs the declaration section"
track: P
prio: 45
type: bug
blocked-by: []
status: backlog_new
owner: claude-A
created: 2026-08-25
summary: "Inside a class body, `const P: Pointer = @Other;` could not see `Other` — class consts live under a mangled symtab key, so the bare name missed `FindSym`, the `@` arm fell through to the ordinal path (which cannot consume `@name`), and the parser reported `unexpected token` at the NEXT declaration, several lines away. FIXED this session."
---

# Symptom

```pascal
type
  TFoo = class
  private
    class var Slot: Integer;
    const Ptr: Pointer = @Slot;     { silently mis-parsed }
    class function Get: Integer; static;   { <-- error reported HERE }
  end;
```

The diagnostic pointed at the *following* member, which is what made this
expensive to find: the failing construct never appears in the error.

# Root cause

`TryParseInitValForm` (`compiler/pasparser_expr.inc`) handles `@name` by looking
the name up with `FindSym`. A class const or class var is registered under a
**mangled** key (class-qualified), so the bare identifier is invisible at that
point even though the class registry has it. The `@` arm then fell through to the
plain-ordinal path, which cannot consume an `@`, leaving `@` and the identifier
unconsumed — the const section resynced one declaration too late.

# Fix (landed 2026-08-25)

When `ParsingClassConstCi >= 0`, ask the class registry first —
`FindClassConstSym` then `FindClassVar` — before falling back to `FindSym`. On a
hit the arm consumes both tokens and yields the address form (`kind := 4`).

# Where it was found

[[feature-pascal-corpus-generics]] — this was the FIRST wall in
`generics.defaults.pas` (line 411); clearing it moved the frontier to 1569 and
then 1865, so it was blocking two further findings behind it.
