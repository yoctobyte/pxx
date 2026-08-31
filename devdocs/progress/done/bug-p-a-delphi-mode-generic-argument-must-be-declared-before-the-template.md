---
slug: bug-p-a-delphi-mode-generic-argument-must-be-declared-before-the-template
track: P
prio: 55
type: bug
status: done
blocked-by: []
summary: "FIXED. In mode Delphi, `TE = TBox<TOuter>;` failed with `unknown type: TOuter` when TOuter was declared AFTER TBox in the same type section -- DelphiRewriteGenericUses spliced its minted alias behind the TEMPLATE, so everything the alias named had to exist by then, and the error pointed into the template's own body. The alias now anchors at position B, immediately before the declaration that USES it, found by a forward walk that tracks class/record body depth and remembers the last depth-0 `;`. The three cases this ticket listed as unanswered -- a use in a var section, a use in a routine body, several tuples anchored separately -- are the SAME walk stopping at the end of the type section instead of at the use, which is position C, and C is correct exactly there because every user is then later by construction. insertAt stays the sweep start and no longer doubles as the callers' did-work signal; the procedure is now a FUNCTION returning the tokens emitted. test_delphi_generic_arg_declared_later.pas, 7 arms, matches FPC 3.2.2. gate.sh quick GREEN."
owner: frankwasm
---


> **Lock released 2026-08-30 (frankP), fleet-wide pause before a re-pin — NOT
> abandoned.** Claimed, the anchor measured, then put back in `backlog/` because
> `working/` is a live lock and a lock behind a stopped session has to be chased
> by whoever runs the pin. Everything learned is in this file, not in a session:
> position **B** is the anchor (table above), the sketch that said otherwise is
> struck through with its measurement, and the three remaining cases are named.
> Nothing is half-applied — no compiler source was edited for this ticket.


# A mode-Delphi generic argument must be declared before the template

Found while fixing `bug-p-a-qualified-type-name-cannot-be-a-generic-argument`,
as the control that proved the two are unrelated. Filed separately because it
has nothing to do with qualified names.

## Repro — the SAME program in two declaration orders

FPC prints `8` for both. pxx compiles one and rejects the other.

```pascal
program q5;
{$mode delphi}
type
  TBox<T> = class          { template FIRST ... }
    V: T;
  end;

  TOuter = class           { ... argument type SECOND  -> pxx REJECTS }
    K: Integer;
  end;

  TE = TBox<TOuter>;
var
  e: TE;
begin
  e := TE.Create;
  e.V := TOuter.Create;
  e.V.K := 8;
  writeln(e.V.K);
end.
```

```
pascal26:5: error: unknown type: TOuter
  near: TOuter   class V  >>> TOuter  end
```

Swap the two type declarations so `TOuter` comes first and the identical program
compiles and prints `8`. The error line is `5` — inside `TBox`'s own body, at the
`V: T` field with `T` already substituted — which is the tell: the alias was
minted and spliced before `TOuter` existed.

## Cause

`DelphiRewriteGenericUses` emits `TBox$TOuter = specialize TBox<TOuter>;` at
`insertAt`, and for the pattern-A caller `insertAt` starts immediately behind the
template's own declaration. Everything the alias names must therefore already be
declared at that point. A Pascal type section imposes no such order — FPC
resolves the whole section — so any program that declares a helper type after the
generic that consumes it hits this.

objfpc does not have the problem: there the alias is not minted by the rewrite at
all, the `specialize` form is parsed where it is written, and prerequisites are
emitted at the use site.

## Why it is worth more than its repro suggests

"Declare the container before the thing it contains" is not a rule Delphi code
follows, and real Delphi-surface headers are ordered for readability. It is also
a SILENT-shaped failure from the author's point of view: the diagnostic points
into the TEMPLATE's body, at a line the author did not write, so the reported
location and the fixable location are nowhere near each other.

## The sketch below was WRONG. Measured 2026-08-30 (frankP), all three positions.

**Struck through rather than deleted, because the wrong idea is the obvious one
and the next reader will have it too.** The sketch said: put the alias
declarations at the END of the enclosing type section, reusing
`EmitLateNestedSpecDecls`. That does not work, and the reason is visible the
moment it is tried instead of reasoned about — **the alias's own USE is inside
the same section, before the end of it.**

Three hand-written positions for the identical program, minted name spelled
`TBox_TOuter` because `$` is not lexable in source:

| # | where the alias declaration goes | result |
| --- | --- | --- |
| A | behind the TEMPLATE — **what pxx does today** | `unknown type: TOuter` |
| B | immediately before **the declaration that uses it** | **compiles, prints `8`** |
| C | at the END of the type section — **the sketch** | `unknown type: TBox_TOuter` |

A fails because the alias names a type declared later; C fails because the alias
is named by a declaration that comes earlier. **Only B satisfies both
constraints, and it is the only anchor that can** — the use site is legal Pascal,
so everything the group names is already declared there by construction, and
inserting immediately ahead of that declaration cannot outrun anything that
refers to the alias.

So the anchor is **the use site's own enclosing declaration**, not the section
end and not the template.

### What is left, and it is positional bookkeeping rather than design

The rewrite has the use's token index; it needs the start of the top-level
declaration containing it. That is not "scan back to the previous `;`" — a use
can sit in a class-body field (`F: TBox<TOuter>;`), where the nearest preceding
`;` is inside the class and a type declaration spliced there is nonsense. The
workable form is a FORWARD walk from the template's end to the use index,
tracking class/record/case depth, remembering the position after each depth-0
`;`; the last such position at or before the use is the anchor.

Cases that still need an answer before this is finished, none of them looked at:

- a use in a `var` / `const` section after the type section closed — there is no
  open type section to splice a bare `X = specialize ...;` into, so this needs
  the leading `type` keyword `EmitLateNestedSpecDecls` adds for exactly that
  reason;
- a use in a procedure body or parameter list;
- several tuples whose first uses are in different declarations — today they are
  emitted as one run at one point, and per-tuple anchoring makes them separate
  splices, each of which shifts every later index.

That last one is the reason this is not a small change: `insertAt` is a single
`var` cursor the fixed-point loop advances, and per-use anchoring turns one
ordered splice into several.

## Gate

`make compiler/pascal26` (the byte-identical self-host fixedpoint) + the repro in
both orders + `test/test_generic_qualified_arg_delphi.pas` (which pins the
working order and cites this ticket for the other). Track T sweeps the matrix.

## FIXED (frankwasm, 2026-08-31) — and all three "still need an answer" cases are answered

The anchor is position **B** as measured above, and the three open cases turned
out to be **the same walk stopping earlier**, not three separate changes.

`DGenDeclAnchor(fromIdx, useIdx)` walks forward from the current splice point to
the use, tracking class/record/interface/object body depth and paren depth, and
remembers the position after every depth-0 `;`. It returns the last such position
at or before the use. It stops early — keeping what it has — when the walk leaves
the type section (`var`, `const`, `begin`, a fresh `type`, `uses`, `asm`,
`implementation`/`threadvar`/`resourcestring`/`label`/`initialization`/
`finalization`, a bare `procedure`/`function` heading, or an unbalanced `end`).

**That early stop IS position C, and C is right there.** C failed for an
in-section use because the alias would land after a declaration that names it;
for a use in a `var` section or a routine body every user is later by
construction, so the end of the type section is exactly correct. One walk, two
answers, chosen by whichever boundary comes first — which is why this is smaller
than the ticket estimated rather than larger.

Three details that are not obvious from the sketch:

* **`case` is NOT counted as a body.** A record variant part introduces no `end`
  of its own, and in a type section `case` appears nowhere else.
* **`X = procedure(...)` is a procedural TYPE**, not a section terminator; a bare
  heading is. `Tokens[k-1].Kind = tkEq` separates them.
* **A bodiless `class;` / `class(TB);` opens nothing**, the same exemption
  `CollectNestedTypeNames` carries and the same bug it exists for.

### The per-tuple splice, which WAS the real cost

Each tuple now splices at its own anchor, so one ordered insertion became several
and every one shifts the indices after it. Handled by recording `seenUse[si]`
during the sweep (safe: the sweep only ever REMOVES tokens *after* the use it
just rewrote, so a recorded position never moves) and re-adding each insertion's
width to the uses at or after it.

`insertAt` stays the SWEEP START and only advances for a splice at or before
itself — so it can no longer double as the callers' "this round did work" signal.
It never really was one; it was a proxy, and the direct answer is the number of
tokens emitted. `DelphiRewriteGenericUses` is now a **function returning that
count**, and both fixed-point loops test it. The nested case then works for free:
an alias is itself a declaration, so the outer tuple's walk stops *after* the
inner alias the previous round emitted.

### Evidence

`test/test_delphi_generic_arg_declared_later.pas`, wired into `test-core`, seven
arms, `total ok 7 / 7` under both pxx and FPC 3.2.2 on the same source:

1. the plain case, argument declared below the template;
2. the use in a **class field** (nearest preceding `;` is inside the class body);
3. two tuples first used in **different declarations**;
4. a procedural type and a bodiless class in the crossed section;
5. **nested** `TBox<TBox<TLater>>`;
6. the use in a **var section** (open case #1);
7. the use in a **routine body** (open case #2).

Open case #3 — several tuples anchored separately — is arm 3 and is what the
shift bookkeeping exists for.

`gate.sh quick` GREEN; self-host fixedpoint converges in 1 round; the seven
existing `*delphi*generic*` tests all pass, including the cross-unit one that
exercises the second call site (`DesugarImportedDelphiGenericUses`), where the
walk correctly finds no open type section and falls back to today's position with
the caller's leading `type` keyword intact.

## Log
- 2026-08-31 — resolved, commit b613b5fcf.
