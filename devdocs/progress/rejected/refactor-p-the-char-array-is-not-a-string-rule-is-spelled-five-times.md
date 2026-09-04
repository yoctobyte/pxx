---
slug: refactor-p-the-char-array-is-not-a-string-rule-is-spelled-five-times
track: P
prio: 40
type: refactor
blocked-by: []
status: rejected
owner: ""
created: 2026-08-29
resolved: PENDING-COMMIT
summary: "REJECTED -- false premise, and the consolidation this asks for had already happened NINE DAYS before the ticket was written. There is ONE oracle, `ASTCharArrayCap` in pasparser_lval.inc (landed 2026-08-20, a22177c73/3c2d75dd5), whose own header says it is `the ONE oracle the char-array-is-a-string conversion asks -- both directions, every site`, plus two direction wrappers. The `five separate sites in ir.inc` are occurrences of the TICKET SLUG in comments, not implementations of the rule: at the ticket's own filing date ir.inc held FOUR of them, and today there are four in ir.inc and four more in three other files -- eight citations of one bug, applied at the contexts where a value enters a string context (call argument, binop, assignment, write). Nothing to consolidate; counting a slug counted the bug's fame, not its spellings."
---


# The "a char array is not a string" rule is spelled five times

- **Type:** refactor — **Track P** (the sites are Pascal lowering).
- **Found:** 2026-08-29 by frankC during the `cir.inc` carve-out inventory;
  routed here by the coordinator because it is not Track C's ground.

## The measurement

The rule from `bug-p-a-char-array-is-not-a-string-in-any-direction` appears at
**five** separate sites in `compiler/ir.inc`, each with a comment pointing at the
others. They are Class-B sites in the carve-out inventory — `not CProgramMode`
guards around **Pascal** code, so they are Pascal's to consolidate.

`devdocs/dev/root-cause-over-microfix.md` sets the line explicitly: *"count how
many mechanisms serve the one concept (two is a smell, three is a design
flaw)."* This is five, and the cross-referencing comments are evidence that each
author knew about the others and added a sixth spelling anyway rather than
consolidating — which is the failure mode that document exists to name.

## Why it is filed rather than fixed

frankC found it while inventorying `ir.inc` for the C carve-out and correctly did
not touch it: these sites are Pascal lowering behind a C guard, not C lowering.
Moving them would have relocated part of the Pascal frontend into `cir.inc`.

## What to do

Consolidate to one predicate. Per `normalise-dont-special-case`, the win is
deleting cases rather than adding a sixth; and per
`root-cause-over-microfix`, **measure by tickets-closed-per-change** — check
whether the open char-array tickets collapse onto the single implementation
before deciding scope.

**Grep for the sibling before closing:** five copies means a fix on one arm is
the default outcome, not the risk.

## Related

Coordination context and the full Class-A/B/C inventory:
`refactor-a-c-exclusive-lowering-has-no-carved-out-file-so-track-c-cannot-be-staffed`.

## Rejected 2026-09-04 (frankB) — the census, re-derived

The brief that sent me here said to re-derive the "five" first, because two
counts the same night had been wrong in the same direction. It is wrong here
too, and in a way worth writing down because the instrument is one anybody
would reach for.

```
$ grep -rn 'char-array-is-not-a-string' compiler/*.inc | wc -l
8                       # not 5 — and across FOUR files, not ir.inc alone
$ grep -rn 'ASTCharArrayCap' compiler/ | grep -v 'function ASTCharArrayCap' | wc -l
12                      # calls of the ONE predicate
```

**What those eight actually are:**

| where | what it is |
| --- | --- |
| `pasparser_lval.inc:6000`, `:6032` | the section header and the header of `ASTCharArrayCap` itself — the DEFINITION, counted twice |
| `ir.inc:3842`, `:10078`, `:11201`, `:15191` | four CONTEXTS: a call argument, a `+`/relational binop, an assignment, a `write` item |
| `pasparser_expr.inc:5932` | `Length()` — a guard AGAINST the rule misfiring, not an application of it |
| `pasparser_prog.inc:1568` | the RTL-linkage prescan: does this program need `builtin.pas` at all. Token-keyed, a different concern entirely |

The four `ir.inc` contexts each call the same `ASTCharArrayCap` and the same
`WrapCharArrayToStringExpr`; what differs between them is three to eight lines
of context-specific condition (a parameter that is not `var` and not an array;
a binop with one of seven operators; an assignment in either direction; a write
item with or without a width). Those conditions are not copies of each other —
there is nothing there to fold.

**The dates settle it.** All the char-array work landed on 2026-08-20 in
`a22177c73` and `3c2d75dd5`, with `ASTCharArrayCap` consolidated from the start.
This ticket was filed 2026-08-29, nine days later, and at that moment `ir.inc`
held **four** slug citations:

```
$ git show 47eaf847c:compiler/ir.inc | grep -c 'char-array-is-not-a-string'
4
```

So the premise was false when written, not overtaken since.

## The instrument, since it will be reached for again

A ticket slug in a comment is a citation of a BUG. Grepping it counts how often
one bug was worth naming — which rises when a fix is applied carefully at
several contexts, exactly the opposite of what the count was read to mean. The
sites here even cross-reference each other ("the same way it does in an
assignment or a comparison"), and that reads like evidence of copied rules while
being the opposite: it is what one rule applied at four contexts looks like when
each author documented the others.

`root-cause-over-microfix`'s "two is a smell, three is a design flaw" is about
MECHANISMS. The mechanism count here is one predicate and two direction
wrappers, and its own header already says so. To count mechanisms, grep the
predicate, not the ticket.
