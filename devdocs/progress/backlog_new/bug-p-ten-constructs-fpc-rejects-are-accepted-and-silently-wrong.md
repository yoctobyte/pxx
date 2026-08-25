---
slug: bug-p-ten-constructs-fpc-rejects-are-accepted-and-silently-wrong
title: "Ten constructs FPC rejects compile clean here, and five of them produce a silently wrong value"
track: P
prio: 55
type: bug
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "A 28-construct sweep of things fpc 3.2.2 rejects: pxx accepts 10 of them with NO diagnostic and exit 0. Laxness by itself is dialect policy, but five of these are not lax, they are WRONG -- `i[2]` on an Integer reads out of bounds (-2099249120), `for s := 1 to 3` makes the rest of the program not run, `New(i)` overwrites an Integer with a heap pointer, `Inc(s)` empties an AnsiString, `Length(i)` answers 1. That is the compat-tag escape rule: silent wrong behaviour is a bug, not a parity nitpick."
---

# The sweep

28 one-construct programs, each otherwise identical and valid, each rejected by
`fpc -Mobjfpc -O1`. Measured against pxx at `f687061db`. 18 are diagnosed; these
10 compile clean, exit 0, and print:

| construct | fpc | pxx exit | what actually happens |
| --- | --- | --- | --- |
| `i := i[2]` (i: Integer) | Illegal qualifier | 0 | **i becomes -2099249120** — an out-of-bounds read off a scalar |
| `for s := 1 to 3 do ;` (s: AnsiString) | Illegal counter variable | 0 | **the program produces NO output at all** — the trailing WriteLn never runs |
| `New(i)` (i: Integer) | Illegal qualifier | 0 | **i becomes a heap pointer** (264241264) |
| `Inc(s)` (s: AnsiString) | Incompatible type | 0 | **s is emptied** — `'x'` becomes `''` |
| `i := Length(i)` | Illegal qualifier | 0 | **answers 1** |
| `while i do ;` (i: Integer) | Type mismatch | 0 | no output — same disappearing tail as the `for` |
| `b := r < 1` (r: a record) | Illegal qualifier | 0 | answers FALSE off garbage |
| `F1(1) := 3` | Illegal expression | 0 | accepted, no effect |
| `with i do ;` | Illegal expression | 0 | accepted, no effect |
| `if i then ;` (i: Integer) | Type mismatch | 0 | treated as `i <> 0` |

# The line between dialect and defect

`devdocs/dev/` and CLAUDE.md are explicit that **PXX's dialect is deliberately
lax by default** and that FPC-parity strictness belongs behind `--strict-*`
flags. Two rows here are plainly that kind of laxness and should be left alone
(or flagged, not fixed): **`if i then`** and **`while i do`** with an ordinal
condition is the C rule, deliberate and useful — except that the `while` row
*also* swallows the rest of the program, which the `if` row does not, so the
two are not the same finding.

The other rows are not laxness in any useful sense. Nobody wants `Inc` on a
string to empty it, or `New` on an Integer to overwrite it with a pointer, or a
`for` loop over a string counter to delete the remainder of the program. The
compat tag's own escape rule covers exactly this: *"a compat finding that means
silent wrong behavior is promoted to a normal bug ticket in the owning lane"*.

# Ranked inside the ticket

1. **`for s := 1 to 3 do ;` and `while i do ;` losing the program tail** —
   control flow silently disappears, and that can hide in a large unit for a
   long time. Worst of the set; possibly one cause for both.
2. **`i[2]` and `New(i)`** — an out-of-bounds read and a scalar overwritten with
   a heap pointer. Memory-unsafe, and they are the two most likely to appear as
   a typo in real code (`i[2]` where `a[2]` was meant).
3. **`Inc(s)`, `Length(i)`, `r < 1`** — wrong values, contained.
4. **`F1(1) := 3`, `with i do`** — accepted and inert. Diagnostics wanted, no
   wrong behaviour.
5. **`if i then`** — deliberate dialect; only worth a `--strict-*` mention.

# Method, so it can be re-run

Each case is a program of the form: fixed header declaring `r: TR; c: TC;
i: Integer; s: AnsiString; b: Boolean; arr: array[0..3] of Integer;
d: array of Integer; p: PChar`, the one bad statement, then
`WriteLn(i, s, b, r.a)`. Compare `fpc -Mobjfpc -O1` error count against pxx's
exit status, then RUN the pxx binary — the run is what separates "lax" from
"wrong", and it is the step that turns this from a parity list into a bug
ticket. Generator kept in the session scratchpad; it is 40 lines and worth
rewriting rather than recovering.

# Related

- [[bug-p-an-assignment-is-not-type-checked-at-all]] — filed 2026-08-24 from
  the same kind of sweep, and since fixed for assignments: the four
  assignment rows in this sweep (`i := r`, `r := i`, `i := s`, `s := i`) are all
  correctly diagnosed now, which is why they are not in the table above.
- [[feature-a-error-does-not-halt-so-a-parse-can-be-speculative]] — the sweep
  came out of that ticket's slice-5 measurement; the diagnostics that DO fire
  and their recovery behaviour belong there, the missing ones belong here.
