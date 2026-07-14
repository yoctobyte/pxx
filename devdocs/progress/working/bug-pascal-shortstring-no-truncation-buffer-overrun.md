---
summary: "string[N] assignment does not truncate: pxx writes past the buffer and clobbers the next variable"
type: bug
prio: 78
---

# `string[N] := <longer>` does not truncate — it overruns the buffer

- **Type:** bug (silent memory corruption). **Track P** (Pascal frontend — shortstring
  assignment semantics); may land in Track A if the fix belongs in the assign helper
  rather than the frontend's type lowering.
- **Status:** working
- **Opened:** 2026-07-14
- **Found by:** Track T, probing candidate constructs for
  [[feature-pasmith-widen-grammar]] before generating them. **T owns the tool, never
  the bug** — filed here, not fixed there.
- **Related:** [[bug-frozen-string-unsupported-riscv32-xtensa]] (b345, `string[N]`
  frozen inline strings on riscv32/xtensa) — same type, different defect.

## What happens

A `string[N]` (shortstring) has a **fixed capacity of N characters**. Assigning a
longer value **truncates to N** — that is the defined behaviour, and it is why the type
is safe to place inline in a record or on the stack. pxx does not truncate. It writes
the whole source string into the N-byte slot.

```pascal
program sn2;
{$mode objfpc}
var
  a: string[4];
  b: string[4];
begin
  b := 'BBBB';
  a := 'aaaaaaaaaaaaaaaa';   { 16 chars into a string[4] }
  writeln('a=[', a, '] len=', Length(a));
  writeln('b=[', b, '] len=', Length(b));
  if b <> 'BBBB' then writeln('*** b was CLOBBERED by the assignment to a');
end.
```

**FPC 3.2.2** (correct):

```
a=[aaaa] len=4
b=[BBBB] len=4
```

**pxx (HEAD, 49728c23):**

```
a=[aaaaaaaaaaaaaaaa] len=16
b=[] len=7016996765293437281
*** b was CLOBBERED by the assignment to a
```

`b`'s length byte and contents are destroyed: the twelve characters that did not fit in
`a` were written straight over the variable next to it. `Length(b)` then reads a garbage
qword.

Concatenation has the same hole — `sh := sh + 'zz'` on a `string[8]` yields a length of
12 under pxx and 8 under FPC.

## Why this is worse than a wrong number

Every other `string[N]` defect we have shipped was *loud* or *local*. This one writes
outside the object. A `string[N]` field in a record overruns into the next field; a
local overruns into the next local (which is what the repro shows); on the stack it can
reach a saved register or a return address. The program keeps running and produces
plausible output, so nothing in the test suite has to fail for this to be corrupting
data — which is exactly the class the fuzzer exists to catch, and the reason it is filed
at prio 78 rather than as a `compat-` parity item.

## Where to look

The truncating store belongs wherever a shortstring assignment is lowered: the source
length must be clamped to the declared capacity `N` (and the stored length byte set to
`min(len, N)`) before the copy, for **assignment, concatenation, and passing by value**
alike. Check `Length()` reads the clamped byte afterwards.

## Acceptance

- The repro above prints `a=[aaaa] len=4`, `b=[BBBB] len=4` under pxx.
- `sh: string[8]; sh := 'abcdefghij'` gives `Length(sh) = 8`; `sh := sh + 'zz'` keeps it
  at 8.
- A `test/test_*.pas` regression covers assignment, concatenation, a `string[N]` record
  field, and a `string[N]` local, each with an oversized source, and asserts the
  neighbour is intact.
- pasmith's `string[N]` rung ([[feature-pasmith-widen-grammar]]) can then be enabled;
  it is currently held back because every generated program that truncates would report
  this one bug.
