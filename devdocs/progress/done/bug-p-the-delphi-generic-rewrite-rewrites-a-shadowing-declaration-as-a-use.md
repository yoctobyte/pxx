---
prio: 55
track: P
type: bug
status: done
owner: frankA
blocked-by: []
found: 2026-08-30
found-by: frankA
summary: "In mode Delphi the generic-use rewrite matches `TName<...>` by name and arity anywhere, including at a type DECLARATION whose name is already registered as a template. It splices `specialize` in front of the declaration and the parse dies with `Expected: =, but got: TName`. A program that redeclares a generic it imports is valid Pascal — FPC compiles it — and we rejected it."
---

# The Delphi generic rewrite rewrites a shadowing DECLARATION as a use

## Repro — two units, eight lines each

`u_a.pas` declares `TBox<T>`; `u_b.pas` imports it and declares its own
`TBox<T>`:

```pascal
unit u_b;
{$MODE DELPHI}
interface
uses u_a;
type
  TBox<T> = record
    W: T;
  end;
implementation
end.
```

```
pascal26:6: error: unexpected token
  near: ... type specialize >>> TBox  T
```

`specialize` has been injected in front of a **declaration**. Rename `u_b`'s
type to `TBox2` and it compiles. **FPC compiles the original unchanged**, so
this is valid Pascal we rejected, not a diagnostic nicety.

## RENAMED — the first filing of this ticket was WRONG

It was filed as `...-before-a-declaration-in-an-include`, claiming the `{$I}`
include boundary was the trigger, "measured". It was not measured; it was
inferred from a repro whose `u_tmpl` happened to declare `TPair<K,V>` — left
over from an earlier experiment — so the include and the name reuse varied
together and I reported the wrong one. Four experiments separate them:

| # | shape | result |
| --- | --- | --- |
| A | include kept, name reuse REMOVED | **clean** |
| B | name reuse kept, include REMOVED | **fails** |
| C | same unit, same name, DIFFERENT arity | **clean** |
| D | same unit, same name, SAME arity | **fails** |

The include is irrelevant. C is clean only because the arity differs, so
"cross-unit" is wrong too: the condition is **same name AND same arity as an
already-registered template**, wherever it is written.

## Cause

`DelphiRewriteGenericUses` (`pasparser_generic.inc:654`) scans from `insertAt`
for `Tokens[i]=tname`, `Tokens[i+1]='<'`, collects args, and requires
`na = np`. Nothing asks whether the group is a *use* or the left-hand side of a
*declaration*, and a declaration matches every one of those tests.

## Fix

After the arity check, `j` is the closing `>`, so a following `=` means the
group is a declaration's LHS:

```pascal
if ok and ((j + 1) < TokCount) and (Tokens[j+1].Kind = tkEq) and
   ((i = 0) or (Tokens[i-1].Kind <> tkColon)) then ok := False;
```

The `:` test is load-bearing: a typed constant `x: TFoo<Integer> = (V: 1)` is
**also** followed by `=` and IS a genuine use. Verified — a program with a
typed const, a var and an alias of an imported generic compiles and runs
correctly (`5 + 7 = 12`).

## The regression asserts the TOKEN STREAM, because "it compiles" cannot

A rewrite's only observable is the stream it edits, so a passing compile cannot
distinguish a correct rewrite from one that injects in the wrong place. Added
the **`p.dgen`** PXXDBG channel, which prints every in-place injection.
`test-core` now asserts both directions on `test_generic_shadow_decl.pas`:

```
injections before the TBox DECLARATION = 0      (the bug)
injections before TPairU               >= 1     (a real paramform use in the
                                                 same file, so the zero cannot
                                                 pass by the rewrite dying)
```

The second line exists because the first is otherwise vacuous — measured, not
assumed: concrete specializations take the alias-minting path and print
nothing, so the file needed a paramform use added before the assertion meant
anything.

**Confirmed as a control by breaking it on purpose.** Guard removed and
rebuilt: **2** injections before the declaration and the parse fails. Guard
restored and rebuilt: 0 and clean. Output `shadow 12 10` matches FPC exactly.

## What this does NOT fix — two separate things, both still open

1. **Resolution.** The declaration now parses, but pxx resolves `b` to the
   **imported** `TBox` where FPC takes the local one. Filed as
   [[bug-p-a-generic-declaration-does-not-shadow-an-imported-one-of-the-same-name]].
   The regression sidesteps it deliberately: both records declare the same
   member, so its result cannot depend on which wins.
2. **The corpus wall.** `generics.collections` still stops at `unknown type:
   TKey`, unchanged by this fix — a different defect that the first filing of
   this ticket wrongly merged with it. See
   [[feature-pascal-corpus-expansion]].

## Verification

`make compiler/pascal26` — `converged after 1 round(s)`, fixedpoint verified.
All six earlier repro shapes now compile; A and C, which always passed, still
pass.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
