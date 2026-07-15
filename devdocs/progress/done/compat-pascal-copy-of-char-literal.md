---
summary: "Copy('a', i, n) — FPC promotes a char to a string, pxx rejects the program"
type: compat
track: P
prio: 55
---

# `Copy` on a char: FPC promotes char → string, pxx rejects

- **Type:** compat (Track P — Pascal frontend). The fuzzer owns the tool, never the
  bug — filed here, not fixed there.
- **Status:** done
- **Opened:** 2026-07-14
- **Found by:** `tools/pasmith_run.py`, seed 30014, the first run after the driver
  learned to score a **pxx compile failure as a finding** (it used to be filtered out
  and the program scored *clean*, so this had been invisible to every fuzz slice ever
  run).

## Repro (5 lines, no fuzzer needed)

```pascal
program t;
{$mode objfpc}
var s: ansistring;
begin
  s := Copy('a', 1, 1);
  writeln('[', s, ']');
end.
```

- **FPC 3.2.2:** prints `[a]`.
- **pxx (HEAD):**
  ```
  error: Copy: dynamic-array Copy needs a dynamic-array first argument
         (string Copy needs the strutils/sysutils unit)
  ```

## Cause

A single-quoted single character is typed **char**, not string — `'ab'` is a string
literal, `'a'` is a char. FPC promotes char → string where a string is wanted, so
`Copy` takes it. pxx's `Copy` dispatch (`compiler/parser.inc:8594`, the arm that
decides between string-Copy and dynamic-array-Copy) sees a non-string, non-array first
argument and errors out.

`Copy` on a string *variable*, a multi-char *literal*, and nested `Copy(Copy(s,…),…)`
all work — it is specifically the char-typed argument that falls through. So the fix is
in the argument-typing arm, not in `Copy` itself: a char in a string context should
promote, the same way it already does for `+` (`s := s + 'a'` compiles fine today,
which is what makes the inconsistency visible).

## Why it matters beyond the fuzzer

Char-where-string-is-expected is ordinary Pascal, and it already promotes for
concatenation in pxx. `Copy` disagreeing with `+` about the same promotion is the kind
of corner that makes real code fail to port for no reason a user can see.

Not promoted to a `bug-` ticket: this is a **loud** rejection of valid code, not silent
wrong behaviour (the escape rule in CLAUDE.md). It blocks nothing at runtime.

## Acceptance

The repro above compiles under pxx and prints `[a]`; a `test/test_*.pas` regression
covers char→string promotion for `Copy` (and, while in there, the other string
intrinsics that take a string first argument — `Pos`, `Length`, `Delete`, `Insert` —
which likely share the arm).

## Log
- 2026-07-15 — resolved, commit 85be5639.
