---
track: A
prio: 30
type: bug
---

# Overload-resolution failure dumps compiler internals to stdout

Found 2026-07-19 (noted while filing `feature-nilpy-len-of-str`; re-filed
standalone so it is not lost in a resolved ticket).

```
$ pascal26 t.npy out
Mismatch in MatchProcCall: name = len, nArgs = 2
  arg[0] = 6
  arg[1] = 1
  Candidate idx 140: paramCount = 1
    param[0] = 6
  Candidate idx 141: paramCount = 1
    param[0] = 23
pascal26:2: error: no overload of len matches these arguments ()
```

`MatchProcCall` (`compiler/symtab.inc`, the `if not MatchQuiet` block) writes
raw internal state — symbol indices and TTypeKind ORDINALS — to stdout ahead of
the real diagnostic. It reads as leaked debug output: a user cannot act on
`param[0] = 23`, and it precedes rather than follows the actual error line.

Not wrong, just unpolished — the information is genuinely useful, so the fix is
presentation rather than removal:

- render type ordinals as NAMES (`str`, `TPyList`) instead of numbers;
- print it AFTER the error line, indented, as "candidates were:";
- gate it behind a verbosity flag, or emit it only when the candidate set is
  small enough to be readable.

Also note the trailing `()` on the error text itself ("...these arguments ()"),
which looks like an empty format slot.

Low priority: cosmetic, no wrong behaviour. Worth doing before any 1.0-facing
polish pass — a leaked-debug-looking dump is the kind of thing that reads as
unfinished to a first-time user.

## Log
- 2026-07-20 — resolved, commit 36fb2a55.
