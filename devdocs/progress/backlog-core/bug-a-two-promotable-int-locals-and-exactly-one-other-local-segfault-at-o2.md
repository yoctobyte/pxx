---
slug: bug-a-two-promotable-int-locals-and-exactly-one-other-local-segfault-at-o2
track: A
prio: 80
type: bug
status: backlog
owner: ""
created: 2026-09-22
found-by: franks-5b
tags: [nilpy, promotable-int, o2, codegen, refcount, segfault]
blocked-by: []
summary: "A NINE-LINE NilPy program with no classes, no imports and no library calls SEGFAULTS at -O2, which is the shipped default level, and it reproduces identically on pin v418 (fda77c48b8ee) and at HEAD. TRIGGER, THREE CONDITIONS, all required and all measured: (1) a function frame with EXACTLY THREE locals, (2) EXACTLY TWO of them tyPromoInt64 (tk=28) -- one promo-int runs clean and so do THREE -- and (3) a promo-int reaching `print` WITHOUT an explicit str(). Condition 3 was missing from this ticket's first version: every variant in the original table happened to end `print(acc)`, so the print read as scaffolding. `print(str(acc))` runs CLEAN on the identical frame where `print(acc)` segfaults, which puts the defect in the IMPLICIT promo-int -> AnsiString conversion on the write path rather than in the frame layout or the loop. Two promo-ints plus zero, two or three other locals all run clean; plus exactly ONE other local crashes, and the third local's type does not matter -- Int64 (tk=13), AnsiString (tk=23) and Double (tk=19) all segfault -- nor does its declaration position (first, middle, last all crash). Reducing to ONE promo-int makes it run. LEVEL MATRIX: -O0 clean, -O1 clean, -O2 SEGV, -O3 clean; the default with no -O flag is -O2 and therefore crashes. FAULTING INSTRUCTION is a refcount release sequence -- `cmpq $0x40000000,-0x10(%rax)` (the saturation check) then `decq -0x10(%rax)` -- with rax=0x2aa6428c, i.e. a promo-int's INLINE payload being dereferenced as a heap bignum pointer. So a release is emitted against a slot whose tag says the payload is not on the heap, or against the wrong slot entirely. NOT a missing tag check in general, because the same two promo-ints are clean at every other local count. NOT yet attributed to a pass: the compiler exposes no per-pass flags, so isolating it needs Track A instrumentation. Found while building a benchmark for perf-n-one-computed-getattr-in-any-imported-module-boxes-every-method-in-the-program, where the coarse getattr arm MASKED it -- boxing every method to tyVariant removes the promo-int pair, so the arm that ticket wants narrowed is currently hiding this crash."
---

# Two promotable-int locals plus exactly one other local segfault at -O2

## The repro, complete

```python
def main():
    v0 = 0
    acc = 0
    i = 0
    while i < 3:
        acc = acc + 1
        i = i + 1
    print(acc)

main()
```

    ./compiler/pascal26 repro.py out     # default -O, i.e. -O2
    ./out                                # Segmentation fault (core dumped), rc=139

No class, no import, no method call, no library call. `v0` is never read
after its initialiser and never appears in the loop.

## What the compiler inferred

    PXXDBG n.locals main v0  tk=13    { Int64 }
    PXXDBG n.locals main acc tk=28    { tyPromoInt64 }
    PXXDBG n.locals main i   tk=28    { tyPromoInt64 }

`acc` and `i` are promotable ints because they are incremented and could grow;
`v0` cannot, so it stays a plain `Int64`. That inference looks correct. The
defect is downstream of it.

## The trigger, measured rather than reasoned

Holding the two promo-ints fixed and varying the OTHER locals:

| other locals | rc |
| ---: | --- |
| 0 | 0 |
| **1** | **139 (SIGSEGV)** |
| 2 | 0 |
| 3 | 0 |

**A prediction that was wrong and is recorded so nobody re-runs it:** the 2-pass
/ 4-fail / 3-crash shape looked like stack misalignment (3 x 8 = 24 bytes, not
16-aligned), so I predicted odd counts crash and even pass. Measured 1..8 total
locals: only 3 crashes. **It is not an alignment parity.**

Varying the third local's TYPE and POSITION — all still crash:

| variant | third local | rc |
| --- | --- | --- |
| plain first | `v0 = 0` (tk=13) | 139 |
| plain middle | `v0 = 0` | 139 |
| plain last | `v0 = 0` | 139 |
| plain is a string | `v0 = 'q'` (tk=23) | 139 |
| plain is a float | `v0 = 1.5` (tk=19) | 139 |
| **only one promo-int** | `acc` never incremented, so tk=13 | **0** |

So the condition is **two `tyPromoInt64` locals and exactly one other**, and
nothing else about the third local matters.

## Optimisation level

| level | rc |
| --- | --- |
| -O0 | 0 |
| -O1 | 0 |
| **-O2** | **139** |
| -O3 | 0 |
| default (no flag) | **139** |

`-O2` is the proven default, so every ordinary invocation hits it.

## Where it faults

Built `-g -O2`, under gdb:

```
Program received signal SIGSEGV
=> 0x40022a:  cmpq   $0x40000000,-0x10(%rax)
   0x400232:  jae    0x400260
   0x400234:  decq   -0x10(%rax)
   0x400238:  jne    0x400260
rax  0x2aa6428c   (715539084)
```

That is the refcount release sequence — saturation check at `0x40000000`, then
decrement, then skip the free when nonzero. `rax` holds `715539084`, which is a
small integer, not a heap address: **a promo-int's inline payload is being
dereferenced as a bignum pointer.**

## What is NOT established

- **Which pass.** The compiler has no per-pass flags (`--help` lists only
  `-O0..-O3` and `-OO`), so attributing this needs Track A instrumentation.
- **Whether the bug is the release's TAG CHECK or its SLOT INDEX.** Both fit the
  evidence. The same two promo-ints are clean at every other local count, which
  argues against a simply-missing tag check and for something layout-dependent.
- **Whether Pascal or C front ends can reach it.** `tyPromoInt64` is what the
  NilPy frontend infers for a growable integer; no attempt was made to produce
  the same frame from another language.

## Why it had not been found

The shape needs an *unused* extra local beside two loop counters, which is what
a hand-written test rarely has and what real code has constantly. It is also
**masked by boxing**: when
`perf-n-one-computed-getattr-in-any-imported-module-boxes-every-method-in-the-program`'s
coarse arm fires, every method takes variant params and results, the promo-int
pair disappears into `tyVariant`, and the crash goes with it. My first benchmark
for that ticket ran clean *because* it contained a computed `getattr`; deleting
the getattr is what produced the segfault. **Narrowing that arm will unmask this
in programs that currently work.**

## CHEAP DISCRIMINATOR OFFERED, AND ITS PREMISE CHECKED AGAINST THE SOURCE — 2026-09-22

**`frankh-c0` (author of the `--dce`-at-default-`-O2` promotion) offered the one
cheap discriminator so whoever takes this does not start cold: run the repro at
`-O2 --no-dce`.** It did not claim the bug and is not taking it.

Its stated reasoning was that *"clean at -O3"* is a strange row for a
pass-ordering bug **if** DCE is on at `-O2` and off at `-O3`. **That conditional
resolves in the direction that makes the row stranger, not less strange.**
Checked here by READING THE SOURCE — no build was run, and this is a source
reading, not a behavioural measurement:

```
compiler/compiler.pas:2207   if (OptLevel >= 2) and not DceOff and (TargetArch <> TARGET_WASM32) then
                               DceEnabled := True;
compiler/compiler.pas:1040   DceOff := False;                    { initialised }
compiler/compiler.pas:1179   DceOff := True; DceEnabled := False; { --no-dce, the ONLY setter }
compiler/defs.inc:4697       DceOff : Boolean;   { --no-dce: keep every body even at -O3 }
```

`grep -rn DceOff compiler/` returns five hits and they are all accounted for
above plus `compiler.pas:2270` (`EspBareBoot`). **So DCE is ON at `-O2` AND at
`-O3`** — `defs.inc`'s own comment says so in as many words — **and nothing in
the `-O3` path turns it off.**

**THEREFORE "CLEAN AT -O3" IS NOT EXPLAINED BY DCE BEING ABSENT THERE, AND THE
DISCRIMINATOR'S EXPECTATION FLIPS:**

- If `-O2 --no-dce` is **clean**, DCE is implicated only in combination with
  something `-O3` does differently — not on its own, because `-O3` has DCE too.
- If `-O2 --no-dce` still **crashes**, DCE is exonerated outright and the cause
  is a pass that `-O2` runs and `-O3` does not, or one whose behaviour `-O3`
  changes.

**Either way it is one build and it halves the search.** Run it before attributing
anything to a pass.

**Recorded by the coordinator, who did not run it and cannot** — no pxx work in
that seat. Everything above is c0's suggestion plus a source reading; the repro,
the 18 variants and the fault-site reading are `franks-5b`'s and are attributed
to it in this ticket's body. **A second reading of the fault site has been
requested from `frankb-8e`** (Track A, builds), because *"a promo-int's inline
payload dereferenced as a heap bignum pointer"* is 5b's interpretation of the
instruction sequence and register, and 5b flagged it as such rather than as
established.
## 2026-09-22, same day — the trigger is SHARPER and the third condition was missing

The section above is correct and incomplete, and the missing condition changes
where to look. **A promotable int must reach `print` without an explicit
`str()`.** Every variant in the original table happened to end `print(acc)`, so
the print read as scaffolding rather than as part of the trigger.

Holding the frame at three locals, two of them `tyPromoInt64`, and varying only
what is printed:

| what is printed | rc |
| --- | --- |
| `print(acc)` — a promo-int | **139** |
| `print(i)` — the other promo-int | **139** |
| `print(acc + 0)` — a promo-int expression | **139** |
| `print(acc)` then `print(i)` | **139** |
| `print(v0)` — the plain `Int64` | 0 |
| `print(7)` — a literal | 0 |
| `print('done')` — a string | 0 |
| `print(str(acc))` — **the same promo-int, explicitly converted** | 0 |
| no `print` at all (`return acc`) | 0 |

**`print(str(acc))` running clean while `print(acc)` segfaults is the sharpest
row here.** The value, the frame and the local composition are identical; only
the route to a string differs. So the defect is in the IMPLICIT promo-int ->
string conversion on the write path, not in `str()` and not in the loop.

And the promo-int count is **exactly two**, not "at least two":

| promo-ints among 3 locals | rc |
| ---: | --- |
| 1 | 0 |
| **2** | **139** |
| 3 | 0 |

## What the IR shows

`PXXDBG=a.ir:main` on the crashing program, at function exit:

    52: slotaddr a=557 ... tk=17
    53: arg      a=52  ... tk=17
    54: call     a=635 b=53 ... tk=23      { promo-int -> AnsiString }
    55: write    a=54  b=0  c=-2 ival=1 tk=23
    56: writeln  a=55  b=55 ...

`call 635` returns `tk=23`, a **managed AnsiString**, which must be released
after the write. The faulting instruction is a refcount release with a
non-pointer in `rax`. Declared locals in this program are `553 $pyresult`,
`554 v0`, `555 acc`, `556 i`; **`557` is a temporary**, and the composition of
the frame decides which slot that temporary lands in.

**That is a hypothesis with a confirmed prediction, not a conclusion.** The
prediction was stated before testing: *if the faulting release is the
post-print string release, removing the print removes the crash.* It does. What
is still unproven is which slot the release actually targets — the IR above is
pre-backend, and no one has read the emitted release site.

## A confound named rather than resolved

The four clean cases that introduce an intermediate (`s = str(acc)`,
`b = acc`) each add a local **and** route through a named variable, so those two
axes are entangled and those rows cannot separate them. `print(str(acc))` is
the row that does separate them — it keeps the frame at three locals and still
runs clean — which is why it carries the argument above and the others do not.

## Correction to this ticket's own earlier text

The first section says the third local's type does not matter. That is still
true as measured (Int64, AnsiString and Double all segfault) — but every one of
those variants printed a promo-int, so the table was varying one thing while a
second, unnamed condition was held fixed throughout. **The reduction had an
axis nobody enumerated, in a ticket whose own summary warns about a dead local
being one.**
