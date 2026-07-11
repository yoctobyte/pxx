---
prio: 62
---

# case-of-string: SEGFAULTS at runtime (worse than the missing diagnostics)

- **Type:** bug (Pascal frontend + lowering) — Track P (shared `parser.inc` —
  A-gated, sole-A confirmation before edit)
- **Status:** backlog — filed 2026-07-11 while scoping the case-label
  validation cluster from [[bug-pascal-missing-diagnostics-fail-tests]]
- **Owner:** —

## Symptom 1 — SEGFAULT (the news)

```pascal
var s: string; i: Integer;
begin
  s := 'cab';
  case s of
    'a'..'b': i := 1;
    'cab': i := 2;
    else i := 0;
  end;
  writeln(i);
end.
```

Compiles clean, **SIGSEGV at runtime**. Root cause visible in
`ParseCaseStatementAST` (parser.inc ~9053): every string label is collapsed to
`Ord(CurTok.SVal[1])` — i.e. case-of-string parses as case-of-first-CHAR — and
the selector is a STRING value (a pointer/struct in the value model), so the
emitted equality compares garbage and the branch logic walks off. There is no
string-case path at all (only the char-label special case for length-1
literals, which is what made this look implemented).

FPC supports `case string of` with full-string equality and ranges
(lexicographic). The tcase* conformance cluster exercises exactly this.

## Symptom 2 — no label validation (the original cluster)

15 headerless `{%FAIL}` conformance tests exposed by the headerless-program
fix (74d6c9eb) compile but must be rejected: duplicate case labels
(tcase10/11 …), inverted ranges `'abba'..'ababaca'` (tcase3), overlapping
ranges. Applies to ordinal cases too — validation simply doesn't exist.

## Fix sketch (order matters)

1. **String-case lowering**: detect a string-typed selector in
   ParseCaseStatementAST; keep labels as string literals (AN_STR_LIT), lower
   to chained full-string comparisons (or a compare helper); ranges =
   lexicographic `(s >= lo) and (s <= hi)`. Char selectors keep today's path.
2. **Label validation** on top: per case statement, collect (lo,hi) label
   intervals; error on lo>hi and on any overlap/duplicate. Ordinal: Int64
   intervals. String: string intervals, lexicographic.
3. Re-run `tools/run_pascal_conformance.sh` — burns the 15 "missing
   diagnostic: accepts invalid code" tcase skip entries + several
   `exit=139`/`exit=1` tcase runtime failures already in the skiplist (those
   segfaults are almost certainly THIS bug: tcase12/15/16/28/31/32 exit=139).

## Gate

`make test` + self-host byte-identical (+ test-opt; shared parser.inc under
A's no-concurrent-edit rule). New positive tests for case-of-string equality
+ ranges; negative tests for duplicate/inverted labels.
