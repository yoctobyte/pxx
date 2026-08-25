---
slug: feature-p-legacy-value-object-types
title: "`TFoo = object ... end` — the legacy value-object type is not parsed at all"
track: P
prio: 35
type: feature
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "Turbo/Object Pascal's value `object` (a record with methods and single inheritance, `new`/`dispose`-able) has never been supported: `type TO = object X: Integer; ... end` fails with `Expected: begin, but got: X`. `object` is claimed by an unrelated meaning in ParseTypeKind (a rooted object REFERENCE, feature-object-reference-type), so the type-declaration position has no arm for it. Five fpc-testsuite generics tests fail on this alone."
---

# Measured, 2026-08-25 (HEAD, self-hosted fixedpoint)

```pascal
program plainobj;
{$mode delphi}
type
  TO2 = object
    X: Integer;
    function Test(a: Integer): Integer;
  end;
function TO2.Test(a: Integer): Integer;
begin Result := a + X; end;
var t: TO2;
begin t.X := 1; writeln(t.Test(42)); end.
```

```
pascal26: Expected: begin, but got: X (Kind: 1, Line: 5)
```

`fpc -Mdelphi -O1` compiles and runs it (prints 43).

The comment in `compiler/pasparser_decl.inc` (the `object` arm of the builtin
type-name chain) already states the position explicitly:

> NOT legacy Object Pascal's value-`object` (record-with-methods); that syntax
> was never supported here.

So this is a known absence, not a bug — filed as a feature so the size of what it
blocks is on the board.

# What it blocks

`tools/run_pascal_conformance.sh --only 'tgeneric*'` (fpc-testsuite), after the
nested-`type`-in-record fix landed, still fails these five *entirely* on
`object`:

| test | shape |
| --- | --- |
| `tgeneric62.pp` | nested `object` inside a generic class |
| `tgeneric65.pp` | generic record with a nested `object` |
| `tgeneric66.pp` | `generic TTest<T> = object` with a nested record |
| `tgeneric67.pp` | `generic TTest<T> = object` with a nested class |
| `tgeneric68.pp` | `generic TTest<T> = object` with a nested `object` |

`tobject*.pp` in the same suite is 6 skipped / 4 auto-gated — none of it runs.

# Shape of the work

Most of the machinery exists. A value `object` is, in pxx's model, a **record**:
`ParseRecordFields` already parses methods, class methods, `const` sections,
visibility sections, `class operator` signatures, and (as of this ticket's
sibling) nested `type` sections. The distances from a record are:

1. **the keyword** — the type-declaration parser needs an `object` arm that
   routes to the record path, kept apart from the `object` *reference* type in
   ParseTypeKind (which is a `tyPointer` over `tyClass`). The two meanings are
   distinguished by POSITION, not by lookahead: `= object` in a type declaration
   opens a body; `: object` on a var/field/param names the rooted reference.
   Anything else is guesswork and will get one of them wrong.
2. **single inheritance** — `TChild = object(TParent)`. Records do not inherit
   and `UClsParent` is already there for classes, so this is the one genuinely
   new piece for the record layout path.
3. **`constructor` / `destructor`** on a value object, and `new(p, Init)` /
   `dispose(p, Done)` — the two-argument forms. Worth deciding whether to
   support at all (see below) rather than assuming.
4. **virtual methods on a value object** — a VMT pointer field, only present if
   the object declares one. This is where the real cost is, and it is what
   `tobject*.pp` mostly tests.

# Escalation (Track U)

Rungs 1+2 are cheap and unlock the five generics tests plus ordinary
record-with-inheritance code. Rungs 3+4 are a different size, and `object` is
deprecated in FPC's own documentation. **Recommend: implement 1+2, refuse 3+4
with a clear diagnostic** ("a value `object` cannot be virtual / cannot have a
constructor — use a class or an advanced record") rather than accepting them and
being silently wrong, which is the failure mode
`devdocs/dev/root-cause-over-microfix.md` is about. If that split is wrong, it
is a Track U call; file `decide-how-much-of-legacy-object-we-implement`.
