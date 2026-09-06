---
track: A
prio: 35
type: bug
blocked-by: []
summary: "`__pxxCharArrayToStr` stops at the first #0 within the array's capacity, and its own comment says that is FPC's rule. Measured 2026-09-06 against fpc 3.2.2: it is not. For `a: array[1..4] of Char = 'pq'` (bytes 112 113 0 0 on BOTH compilers — the padding is identical), fpc's `Writeln(a)` emits all four bytes and `Length(string(a))` is 4; pxx emits two and answers 2. Two observables, one cause. The comment is the load-bearing part of this ticket: it asserts a measurement that is false, so a reader who checks it stops looking."
status: backlog
owner: unassigned
---

# A Char array in a string context stops at the first #0 and FPC does not

- **Found:** 2026-09-06 (frankS), building the fixture for
  `bug-p-for-in-over-an-array-of-char-rows-yields-one-character`. A row using a
  SHORT literal (`'pq'` into a 3-char row) diverged, and the first guess —
  different padding — was wrong.
- **Measured at compiler `1268b32df468`** against fpc 3.2.2.

```pascal
type T = array[1..4] of Char;
var a: T = 'pq'; s: string;
begin Writeln(a); s := a; Writeln('len=', Length(s)); end.
```

```
fpc:  p q \0 \0 \n  len=4
pxx:  p q \n         len=2
```

**The padding is NOT the difference.** Both compilers store `112 113 0 0`,
verified by printing `Ord` of each element — from a scalar initialiser and from
inside an array-of-rows initialiser. The divergence is entirely in the
array-to-string conversion.

## The comment is why this was invisible

`WrapCharArrayToStringExpr` (`pasparser_lval.inc`) says:

> The helper stops at the first #0 within cap, which is FPC's rule and not a
> plain memcpy: an array[0..7] holding 'ABC'#0'EFGH' is the 3-character 'ABC'.

The behaviour is real and the attribution is false. FPC converts the whole
capacity. This is the same shape as
`bug-p-the-management-operator-refusal-names-four-operators-and-tests-two`
(frankA, the same day): a true statement about the CODE, written as a statement
about the RULE, in the one place a reader would check.

## Why it is not simply "fix it"

`test_char_array_is_a_string` and the `#0`-stopping behaviour are load-bearing
for C-interop buffers, where a fixed `array[0..N] of Char` genuinely holds a
NUL-terminated string and the trailing bytes are garbage rather than data.
Matching FPC would make every such conversion carry the padding. **Which
behaviour real Pascal code wants is the question, and it has not been asked** —
that is the work here, not the one-line change.

## What is safe to do first

Correct the comment. It costs nothing, it removes the false attribution, and it
is what stops the next reader concluding the behaviour is already verified
against FPC.
