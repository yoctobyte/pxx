---
slug: bug-a-pxxdbg-a-ir-star-silently-skips-a-program-main-body
title: "PXXDBG=a.ir:* silently skips a program's main body, and a comment says it is --dump-ir"
track: A
type: bug
prio: 30
status: backlog
found: 2026-08-28
found-by: frankwasm (cost two silent runs), verified by frank-coordinator
---

## The fact

`compiler/ir_codegen.inc:10106`:

```pascal
if DumpIR or ((CurProc >= 0) and PxxDbgWants('a.ir', Procs[CurProc].Name)) then
```

`DumpIR` (`--dump-ir`) is **ungated**. Every `PXXDBG=a.ir:…` form, `a.ir:*` included, sits
behind `CurProc >= 0`. **A program's main body has no `CurProc`, so `a.ir:*` never matches
it** — while `--dump-ir` does.

And the comment two lines above (`:10105`) states the equivalence the code does not have:

> `a.ir:*` is --dump-ir.

## Why it costs more than it looks

**It fails silently and the silence is ambiguous.** No match, a misspelled topic, and a wrong
flag all produce identical output: nothing. frankwasm lost **two runs** reading it as a bad
invocation before finding the gate. The workaround, once known, is trivial — put the code in a
named routine — which is exactly why the cost is all in the discovery.

This matters more than a p30 usually would because **`PXXDBG` is the repo's designated
alternative to reasoning.** `CLAUDE.md`'s debugging section exists to push people from
theorising to measuring; a measurement tool that returns nothing on the most obvious first
attempt pushes them back.

## Fix

Either make `a.ir:*` cover the main body (the equivalence the comment claims), or — if the gate
is load-bearing — **say so where it fails**: emit one line noting that a topic matched no
routine, so "no match" stops being indistinguishable from "bad flag". Correct the `:10105`
comment either way.

## Related

Same family as `feature-a-a-refusal-is-a-claim-with-a-date-on-it` — a state carrying no
information because several conditions read identically — and specifically its **face nine**
(an inert flag, with the false claim living in a comment). This is that shape in a diagnostic
tool: the comment asserts a property the code does not have, and the tool's silence hides it.
