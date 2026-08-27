---
slug: bug-a-the-specialization-splice-does-not-adjust-the-body-pass-spans
title: "The generic-specialization splice inserts tokens without calling AdjustPass2Spans"
track: A
prio: 35
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-08-25
summary: "InsertTokens/RemoveTokens keep the body pass's DeclItem spans and body-begin marker in step with a token-stream edit. The specialization splice hand-rolls its own insert and calls neither — it now adjusts the token->file map (that fix landed) but still not the Pass2 spans. Either Pass2Active is always false there, in which case say so in a comment, or the spans drift."
---

# Where

`compiler/pasparser_generic.inc`, the substitution loop's tail:

```pascal
  Inc(TokCount, subCount);
  AdjustSrcRanges(TokPos, subCount);   { added 2026-08-25 }
```

`InsertTokens` (`compiler/lexer.inc`) does the same shift and calls **both**
`AdjustPass2Spans` and `AdjustSrcRanges`. This site calls only the second.

# Why it was left alone

Found on the way past while fixing
[[bug-a-a-diagnostic-in-a-used-unit-names-the-wrong-source-file]]. The file-map
adjustment cannot change codegen — it only feeds a diagnostic's `in:` line — so
it was safe to land in that ticket. Adding `AdjustPass2Spans` here CAN change
codegen, so it was deliberately not bundled with an unrelated fix.

# What to settle

1. Is `Pass2Active` ever true while a specialization is spliced? If never, the
   missing call is a no-op and the answer is a one-line comment saying so,
   beside the `AdjustSrcRanges` call, so the next reader does not re-open this.
2. If it can be true, the still-pending `DeclItemStart`/`DeclItemEnd` and
   `Pass2BodyTok` are wrong by `subCount` for every entry above the splice, and
   the body pass then parses from the wrong token — which would show up as a
   routine body compiled from the middle of another, i.e. a spectacular and
   probably already-noticed failure. That it has NOT been noticed is weak
   evidence for answer 1; weak evidence is not an answer.

The same question applies to the two hand-rolled edits in
`compiler/pasparser_call.inc` (the operator-overload desugar), which likewise
now adjust the file map and not the Pass2 spans.

# Gate

`make compiler/pascal26` + `tools/gate.sh quick`. If the call is added, a
generic specialization inside a routine that the body pass defers is the shape
to test.

---

# Settled — ANSWER 1, 2026-08-27

**`Pass2Active` is never true while any of these splices runs.** The missing
`AdjustPass2Spans` is a no-op, and the fix is the comment the ticket asked for —
now at the splice in `pasparser_generic.inc`, with a shorter pointer to it beside
the two in `pasparser_call.inc`.

The ticket said *"That it has NOT been noticed is weak evidence for answer 1;
weak evidence is not an answer."* Agreed, so both halves were done.

## The structural argument

Pass 2 replays recorded `DeclItem` spans through `ParseSubroutine`, and nothing
else. Every caller of a splice is a **declaration** parser:

| splice | enclosing routine | reached from |
| --- | --- | --- |
| `pasparser_generic.inc:1033` | `ParseSpecialization` | `ParseTypeSection` |
| `pasparser_generic.inc:1053` | `FlushPendingClassSpecializations` | `ParseTypeSection` |
| `pasparser_generic.inc:1121` | `BufferGenericMethod` | `ParseSubroutine` — see below |
| `pasparser_generic.inc:1231` | `SpecializeInlineGenericFuncUses` | `ParseGenericFunctionDef` |
| `pasparser_call.inc:225`, `:245` | `ParseOperatorDef` | `ParseProgram` / `ParseUnit` |

`BufferGenericMethod` is the one that looks reachable, and is not — for a reason
the compiler already relies on and already documents. `GenericMethodBuffered`
(`defs.inc`) exists so the pass-1 driver does **not** record a generic method
impl as a replayable DeclItem: *"replaying it in pass 2 would double-buffer and
corrupt the token stream."* That is a stronger claim than this ticket's, and it
is load-bearing today.

The remaining worry — a `specialize` written *inside a routine body*, which pass
2 does parse — does not splice from the body: it resolves a **declaration-level**
specialization. This is the same hoisting that
`SpecializeInlineGenericFuncUses` was added to give the *function* form
(`compat-pascal-inline-generic-specialization`, closed earlier this session); the
class form has always had it.

## The measurement

1. `if Pass2Active then Error('PROBE-PASS2-ACTIVE-AT-SPLICE');` at **all five**
   sites. Then: full self-host fixedpoint, `gate.sh quick`, 346 Pascal
   conformance tests, 220 C conformance tests, the fgl corpus — **nothing
   halted**.
2. The same probe as a `Warn`, to prove the sites are exercised rather than
   merely quiet. A program written to put a specialization **and** an
   operator-overload desugar inside routine bodies reached them **five times**,
   every time `pass2=false` — including the variant with **no** declaration-level
   `specialize` at all, where the only spellings are inside a body.

Point 2 is the one that mattered: without it, point 1 is the "weak evidence"
this ticket refused to accept.

## Verified

`make compiler/pascal26` reports fixedpoint `a97b3a4554e5`, **byte-identical to
the pre-instrumentation build** — this commit is comments only. `gate.sh quick`
GREEN.

## Log
- 2026-08-27 — resolved, commit 451874636.
