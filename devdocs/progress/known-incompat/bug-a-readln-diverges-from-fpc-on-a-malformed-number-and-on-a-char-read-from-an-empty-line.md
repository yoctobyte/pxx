---
slug: bug-a-readln-diverges-from-fpc-on-a-malformed-number-and-on-a-char-read-from-an-empty-line
title: "readln diverges from FPC on a malformed number (we answer 0, FPC halts) and on a Char read from an empty line (FPC then skips a whole line)"
type: bug
track: A
prio: 25
status: new
created: 2026-09-18
owner: ""
summary: "Two divergences left over from the 2026-09-18 readln cross-target census, both measured on x86-64/i386/riscv32/arm32/aarch64 (all five agree with each other) against FPC 3.2.2 {$H+}. (1) MALFORMED NUMERIC INPUT: FPC raises runtime error 106 and halts; we return a value and carry on — `-` with no digits -> 0, `x9` -> 0, `300` into a Byte -> 44, `40000` into a SmallInt -> -25536. (2) A CHAR READ FROM AN EMPTY LINE: both compilers hand back #10, and then FPC's readln SKIPS A FURTHER WHOLE LINE — on input `\\nALPHA\\nBETA\\n`, `readln(c); readln(s1)` gives s1=[BETA] under FPC and s1=[ALPHA] under pxx. FILED HERE RATHER THAN IN backlog-core BECAUSE (2) IS CHOSEN: FPC discards a line the program never saw, ours does not, and `on par with the LANGUAGE, not with FPC` prefers the answer that loses no data and leaves a mistaken program's mistake visible. (1) is the one with a real question in it and it is a POLICY question, not a mechanism one — see below."
---

# (1) Malformed numbers — the open question, stated as a goal

**Do we want `readln(n)` on input that is not a number to stop the program, or
to hand back a value and continue?**

FPC stops (RTE 106). We continue. Neither is a mechanism problem — both are one
line in the same parser — so this is worth deciding once rather than per row.

What is measured (2026-09-18, identical on all five backends):

| input | target | pxx | FPC 3.2.2 |
| --- | --- | --- | --- |
| `-` | Integer | `0` | RTE 106 |
| `x9` | Integer | `0` | RTE 106 |
| `300` | Byte | `44` | RTE 106 |
| `40000` | SmallInt | `-25536` | RTE 106 |

The argument for FPC's answer is that ours is the silent-wrong-value shape this
repo keeps paying for: a program reading numbers from a file gets plausible
garbage and no signal. The argument for ours is that halting is a poor default
for a library-grade runtime and the caller has no way to opt out. **Nobody has
made the case from real source yet**, which is what would settle it — find a
program that depends on either behaviour.

Note the `300 -> 44` row is the same wrap a cast gives, so it is at least
self-consistent with the rest of the language.

# (2) A Char read from an empty line — measured, and ours is chosen

```
input:  "\nALPHA\nBETA\n"
readln(c);  readln(s1);  readln(s2);

pxx   c=10  s1=[ALPHA]  s2=[BETA]
FPC   c=10  s1=[BETA]   s2=[]
```

Both agree the Char is #10 (that half was a genuine bug and was FIXED the same
day — `test_read_char_preserves_the_line_terminator.pas`). They differ on what
the enclosing `readln` does afterwards: ours has nothing left to skip, because
the terminator WAS the character; FPC skips to past the next one and eats
`ALPHA`.

Reading a Char from a line that has none is a program that has already made a
mistake. Given that, the behaviour that keeps the next line is the one that
leaves the mistake visible, so this is **chosen, not tolerated**, and a ticket
reopening it needs real source that wants FPC's skip.

# What is NOT divergent, so nobody re-measures it

Fifteen shapes, five backends, byte-identical to each other and (where FPC does
not halt) to FPC: blanks before a sign, a tab before a sign, leading zeros, an
in-range value into a Byte, two Chars from one line, two integers on one line, a
second integer past end of line, a string taking the rest of a line including
its inner and trailing blanks, a `string[N]` capacity clamp, the read/readln/Eof
interleave, the character scan loop, and a line longer than any buffer.
