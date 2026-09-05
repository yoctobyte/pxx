---
track: U
prio: 30
type: decide
blocked-by: []
status: backlog
owner: ""
created: 2026-09-05
summary: "FORK, not settled. `bug-p-a-generic-routines-implementation-type-parameters-are-not-checked-against-its-interface` reproduces at HEAD and the scope rule points straight at `rejected/` — a type parameter renamed between a routine's interface and its implementation is produced by a mistake and nothing else, and CLAUDE.md is explicit that us accepting what FPC rejects is not a defect. What blocks the rejection is that its own summary names TWO LIVE CONFORMANCE FAILS (tgenfunc17.pp, tgenfunc18.pp, in an otherwise 347/2 run), and `rejected/` is not ranked — so rejecting leaves two red rows with nothing pointing at why, and the next reader files it again. Options: (a) `known-incompat/` with the two rows cited as expected FAILs; (b) implement the check anyway. Generalises past this ticket: a terminal folder that is LOADED but UNRANKED is the right home for a wrong report and the wrong home for a correct measurement that explains a live red."
---

# An unranked terminal folder is the wrong home for a measurement that explains a live red

- **Type:** decision — Track U
- **Found:** 2026-09-05 (frankS), during the Track P staleness pass
- **Concrete ticket that forced it:** `bug-p-a-generic-routines-implementation-type-parameters-are-not-checked-against-its-interface`

## The fork

The measurement is TRUE at `0bbd82cd7` (compiler/pascal26 sha `7fca108e4b85`):

```pascal
unit g1; {$mode objfpc} interface
generic procedure Test<T>(a: T);
implementation
generic procedure Test<S>(a: S); begin WriteLn('ran'); end;
end.
```

`specialize Test<Integer>(1)` from an importer prints `ran`. FPC rejects it.

**The scope rule says reject.** CLAUDE.md: *"Us accepting what FPC rejects is
not a defect."* The goal file adds the sharper test — an input *"whose two
readings differ only when the program is already wrong."* A renamed type
parameter is produced by a mistake and by nothing else; the positional binding
pxx uses gives that source the meaning its author intended. There is no real
source that WANTS the rename diagnosed, and *"evidence that settles it is real
source that wants the behaviour."*

**What stops the rejection is the folder, not the reasoning.** `rejected/` is
loaded so citations resolve, and it is not ranked. Two conformance rows —
`tgenfunc17.pp` and `tgenfunc18.pp` — fail on this and will keep failing. A
reader of that run finds two reds, greps the backlog, finds nothing ranked, and
files the ticket again. The rejection is correct and it destroys the pointer.

## Options

**(a) `known-incompat/`, with the two conformance rows cited as expected FAILs.**
That folder is for a measurement that is *true and reproducible and still not a
defect*, recorded as CHOSEN rather than tolerated — which is exactly this. The
two reds become documented expectations with a citation, and the run's shape
(347/2) is explained rather than merely observed.

**(b) Implement the check.** Cheap, zero runtime cost, and defensible on grounds
that have nothing to do with FPC parity: a diagnostic that catches a certain
mistake is worth having on its own. The cost is that it concedes the parity
framing the goal file is trying to retire.

**Recommendation: (a).** It is what `known-incompat/` is for, and it is the only
option that fixes the residual question — *why are these two rows red* — rather
than only the ticket. (b) is not wrong, but it settles a specific case while
leaving the general one open.

## The general question, which is the reason this is in U and not just a ticket move

**A terminal folder that is loaded but unranked is the right home for a WRONG
report and the wrong home for a CORRECT measurement that explains a live red.**

`rejected/` currently carries both meanings. The four terminal folders are
documented as saying different things, and they do — but the axis they are cut
on is *is the report right*, while the axis that matters for a red test row is
*does anything still point at this*. A correct-but-chosen divergence with a
failing conformance row attached needs to stay findable from the red, and
`known-incompat/` is the only unranked folder whose name carries that claim.

If U agrees, the durable output is not this ticket's placement but a line in
the folder rules: **before filing to `rejected/`, ask whether any red test row
cites the behaviour. If one does, the folder is `known-incompat/`.**
