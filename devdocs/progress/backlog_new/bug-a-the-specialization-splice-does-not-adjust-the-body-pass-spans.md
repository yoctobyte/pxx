---
slug: bug-a-the-specialization-splice-does-not-adjust-the-body-pass-spans
title: "The generic-specialization splice inserts tokens without calling AdjustPass2Spans"
track: A
prio: 35
type: bug
blocked-by: []
status: backlog_new
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
