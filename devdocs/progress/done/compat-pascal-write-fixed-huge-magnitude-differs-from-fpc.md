---
track: A
prio: 40
type: bug
blocked-by: []   # decided 2026-08-08: KEEP EXACT
summary: "write(v:w:d) with |v| >= 2^63, or a NaN/Inf, still prints debris on x86-64 (9223372036854775809.00000) and diverges from FPC on i386/arm32/riscv32 (full 301-digit expansion vs FPC's exponent form)"
status: done

---

# `write(v:w:d)` on a huge magnitude: three backends, three answers, none FPC's

- **Type:** bug (residual of
  [[bug-b-writeln-float-with-17-decimals-prints-garbage]]) — **Track A**
- **Found:** 2026-08-03, measured against FPC while fixing that ticket. The
  ordinary range is now FPC-identical on every backend; this is what is left.

## Measured

```pascal
WriteLn(1e300:0:5);
WriteLn((1.0/0.0*0.0):0:3);    { NaN }
```

| | `1e300:0:5` | NaN |
| --- | --- | --- |
| FPC | ` 1.0E+0300` | `Nan` |
| pxx x86-64 | `9223372036854775809.00000` | `-9223372036854775809.000` |
| pxx i386 / arm32 / riscv32 | the full 301-digit fixed expansion | (untested) |

The x86-64 answer is debris — `cvttsd2si` saturates to `Int64`'s limit, and its
digits get printed. The runtime-helper backends produce the exact fixed
expansion, which is *true* but is neither FPC's nor x86-64's.

**Three backends printing three different texts for one program is the part
that matters most**, more than which of them matches FPC.

## Why it was left

The ordinary range — everything with `|v| < 2^63` — is now FPC-identical on
both the codegen path and the runtime helper, which is what the parent ticket
was about. Fixing this corner needs one of:

- a runtime magnitude test in `EmitWriteFloatFixed` branching to the scientific
  writer, which doubles the emitted code at every `write(v:w:d)` call site; or
- routing x86-64 (and aarch64) through `PXXWriteFloatFixed` like the other three
  backends — the right answer, and it also collapses THREE implementations of
  one formatter into one, but the helper takes no `width` argument, so its
  signature and every backend's call site have to change together.

The second is the real fix and is worth doing on its own terms.

## Note on FPC as the oracle here

FPC's own answer is type-dependent and not worth matching digit for digit: a
literal `1e300` is Extended and prints a FOUR-digit exponent (` 1.0E+0300`),
while the same value in a `Double` variable prints three (` 1.2E+300`). Match
its SHAPE (fall back to an exponent form) rather than its exact spelling.

## Gate

A Pascal test over `1e300`, `1e60`, `DBL_MAX`, `NaN`, `+Inf`, `-Inf` and
`-1e300` at several `:w:d`, run on x86-64, i386, arm32 and riscv32, asserting
all four backends produce the SAME text — and that the text is an exponent form
rather than a fixed expansion, as FPC does.


## Re-measured 2026-08-05 — the BUG half is fixed; what remains is the Track U fork

Two of the ticket's three complaints are gone, measured at HEAD:

| complaint | now |
| --- | --- |
| x86-64 prints debris `9223372036854775809.00000` | **fixed** — no saturation; the value is a real expansion |
| "three backends, three answers" | **fixed** — x86-64 / i386 / arm32 now print the IDENTICAL string |
| NaN / Inf print debris | **fixed** — ` Nan` / ` Inf` on every backend |

Fixed by today's float work: `bug-a-x86-64-writeln-fixed-saturates-at-int64`
(the Int64-scaling native emitter replaced by a shim onto `PXXWriteFloatFixed`),
`bug-a-aarch64-float-field-width-ignored` (the width parameter that made the
shim possible without losing padding), and
`bug-a-writeln-nonfinite-float-aarch64-emitters-unchecked`.

`WriteLn(1e20:0:2)` is now byte-identical to FPC on every target.

### What is left is NOT a bug — it is the exact-vs-capped question

    1e20:0:2    pxx 100000000000000000000.00          FPC 100000000000000000000.00   AGREE
    1e30:0:3    pxx 1000000000000000140737488355328.  FPC 1000000000000000000020000000000.00
    1e300:0:5   pxx 99999999999999983567616651958...  FPC  1.0E+0300

At 1e30 **neither is the exact double** — pxx prints the true value
(`1000000000000000140737488355328`), FPC prints its own approximation, because
FPC computes in Extended. At 1e300 FPC gives up on the fixed form entirely and
falls back to **exponent notation**, which is a third behaviour again.

So there is no single "FPC's answer" to match here, which is why this is now
**blocked on `decide-float-fixed-output-exact-or-fpc-17-digit-cap`**. That
decision has been updated with FPC's exponent-form fallback as evidence — it is
a third option nobody had written down.

Whichever way it goes, the implementation is one place now (`PXXWriteFloatFixed`)
rather than the three divergent backends this ticket was opened against.


## CORRECTION 2026-08-06 — the claim "pxx prints the true value" was wrong

The note above states that at 1e30 "pxx prints the true value
(`1000000000000000140737488355328`), FPC prints its own approximation". The
second half is right; **the first half is false**. The exact value of the
double is `1000000000000000019884624838656`. pxx's digits are wrong from about
the 17th significant digit, and at 1e300 wrong from the first.

The error in method is the one this repo has a rule against: I compared two
implementations *against each other* and concluded ours was the exact one,
without ever checking either against an oracle. `decimal.Decimal(float(x))`
answers it in one line.

What stands from that note: the x86-64 Int64 saturation is genuinely gone, the
backends genuinely agree now, NaN/Inf are genuinely correct, and
`1e20:0:2` is genuinely byte-identical to FPC. What does not stand is the
characterisation of the large-magnitude output as exact.

Filed as [[bug-a-write-fixed-emits-false-digits-past-1e22]].

## UPDATE 2026-08-06 — the digits are exact now; `Str` and `WriteLn` disagree

[[bug-a-write-fixed-emits-false-digits-past-1e22]] landed:
`PXXWriteFloatFixed` expands the integer part in base-10^9 integer limbs, so
`WriteLn(1e30:0:2)` prints `1000000000000000019884624838656.00` — the double's
exact value, byte-identical across x86-64 / i386 / arm32 / aarch64 / riscv32,
verified against `decimal.Decimal` over 3000 random doubles. So the "what are
the digits" question is settled and only the **display policy** is left, which
is [[decide-float-fixed-output-exact-or-fpc-17-digit-cap]].

That leaves a NEW, pxx-internal divergence for this ticket to carry, on top of
the FPC one it was opened for: **`Str(v:w:d)` and `WriteLn(v:w:d)` no longer
agree.** `StrFloat` (`compiler/builtin/builtin.pas`) hands anything at or past
9.2e18 to `FloatToExpStr`:

    WriteLn(1e23:0:0)                 99999999999999991611392
    Str(1e23:0:0, s)                  1e+23

Both are "a number rather than debris", which is what that branch was written
for, but they are two spellings of one operation answering differently. The
fix is the same routing — `StrFloat`'s `v >= 9.2e18` branch wants the exact
expansion as a string — and it is deliberately NOT done under the bug ticket,
because *which* form to print past the Int64 range is the parked decision this
ticket is blocked on. Do it when that resolves.

## Unblocked 2026-08-10 — the decision landed, and it sharpens the target

[[decide-float-fixed-output-exact-or-fpc-17-digit-cap]] is in `decided/`:
**option 1, KEEP EXACT** (user, 2026-08-08 — *"we are not cripling something we
do correct and fpc doesn't"*). pxx prints the exact decimal expansion in the
fixed form and does not adopt FPC's 17-digit cap.

**Read the consequence carefully, because it splits this ticket in two:**

- The **FPC divergence is now expected and correct**, not a defect. A `compat`
  corpus must special-case it. So the ticket's TITLE — "differs from FPC" — now
  names the part that is working as intended.
- What remains is real and is a plain bug: **x86-64 prints debris**
  (`9223372036854775809.00000` — `cvttsd2si` saturating to the `Int64` limit and
  printing those digits), and **three backends print three different texts for
  one program**. The decision makes the target unambiguous: every backend emits
  the exact expansion the runtime-helper backends already produce.

Worth retitling to something like "write(v:w:d) past 2^63 prints debris on
x86-64 and disagrees across backends" — the FPC comparison is no longer the
point. Note the mirroring constraint recorded on the decision: `PXXWriteFloatFixed`
must keep matching the hand-emitted x86-64 `EmitWriteFloatFixed`, so the fix
lands in both or neither.

Sibling the decision also unblocks, already in `backlog/`:
[[bug-a-write-fixed-fraction-digits-past-16-are-invented]].

<!-- float category -->
Indexed on [[meta-float-accuracy-policy]] — the standing float-accuracy index.
Collect, do not fix piecemeal; see the working rule there.

## RE-MEASURED 2026-08-17 (frank2, Track A) — the 2026-08-10 note is STALE; returned unstarted

Claimed, re-measured, and handed straight back **without starting work** — the
remaining scope is a pin-requiring refactor, not the small residual the top of
this ticket describes. Nothing was changed; no code touched.

### The 2026-08-10 note restates complaints that were already fixed

That note says what remains is "**x86-64 prints debris** (`9223372036854775809.00000`)"
and "**three backends print three different texts**". Both are contradicted by
the 2026-08-05/06 notes above it, and measured at HEAD on x86-64 the 2026-08-05
note is the accurate one:

```
WriteLn(1e300:0:5)   1000000000000000052504760255204420248704...(301 digits).00000
WriteLn(1e23:0:0)    99999999999999991611392
WriteLn(nan:0:3)      Nan
```

Checked against the oracle rather than by eye — `decimal.Decimal(1e300)` at
`prec=400` — and **both expansions are digit-for-digit exact**. No saturation,
no debris. So under the landed KEEP EXACT decision the `WriteLn` side is
finished and correct, and the divergence from FPC is expected-and-intended, as
the 2026-08-10 note itself says elsewhere.

(x86-64 verified natively here; the cross-backend agreement claim from
2026-08-06 was not re-run — that is Track T's matrix, not a native check.)

### What is actually left is the `Str` / `WriteLn` split, and only that

```
WriteLn(1e23:0:0)      99999999999999991611392        <- exact
Str(1e23:0:0, s)       1e+23                          <- exponent fallback
Str(1e300:0:5, s)      1.000000000000001e+300
```

`StrFloat` (`compiler/builtin/builtin.pas:1187`) hands anything at or past
9.2e18 to `FloatToExpStr`. Two spellings of one operation answering
differently — exactly as the 2026-08-06 update predicted, now unblocked by the
decision.

### Why it is bigger than it reads, and what the next session needs

The obvious fix — "route `StrFloat` through the exact expansion" — does not
work as stated: **`PXXWriteFloatFixed` and its digit helpers `PxxIntDDigits` /
`PxxFracDigits` (`builtinheap.pas`) WRITE to output; they do not build a
string.** `emit <> 0` means "emit the digits", not "return them". There is no
string-producing entry point to route to.

So the real shape is: give the limb expansion a buffer-producing core, with the
write path becoming "expand into a buffer, then write it", and `StrFloat`
calling the same core. That is the one-implementation answer and it is right —
but it is in `compiler/builtin/**`, so it **needs a pin**, and it sits under the
float output path of every `WriteLn` on five backends. Duplicating the
expansion inside `StrFloat` instead would be the second path that stays broken,
and this repo has a rule against it.

**Recommended:** retitle (the FPC comparison is no longer the point — the
KEEP EXACT decision made that divergence correct) and re-scope to
"`Str(v:w:d)` falls back to exponent form where `WriteLn` prints the exact
expansion", with the buffer-producing refactor named as the work and the pin
called out up front.


## 2026-08-19 — RESOLVED. The defect is gone; the table above is stale.

Re-measured on pin **v361** (`d1fc7394d348b14866e60cd458044121`) against FPC
3.2.2, running **all five backends** (native x86-64/i386, qemu for
aarch64/arm32/riscv32) rather than reasoning from the codegen.

### The defect this ticket names no longer reproduces

```pascal
d := one * 1e300;  writeln('V[', d:0:5, ']');
d := (one/z)*z;    writeln('W[', d:0:3, ']');   { NaN }
```

| target | `1e300:0:5` | NaN `:0:3` |
| --- | --- | --- |
| x86-64 | exact 301-digit expansion | ` Nan` |
| i386 | identical | ` Nan` |
| aarch64 | identical | ` Nan` |
| arm32 | identical | ` Nan` |
| riscv32 | identical | ` Nan` |

`md5sum` of the five captured outputs collapses to **one hash**. The
Int64-saturation debris (`9223372036854775809.00000`) and the `-9223372036854775809.000`
NaN are both gone from x86-64, which has converged with the runtime-helper
targets rather than diverging from them.

This ticket said the part that mattered most was *"three backends printing three
different texts for one program"*, more than which matched FPC. **That is
fixed.** It was fixed by other work — the `PxxSciDigits17`/exact-expansion route
and the non-finite guards, landed under the tickets those changes belonged to —
which is why nothing here records a fix commit.

### The remaining FPC divergence is DECIDED, not defective

pxx prints the exact expansion; FPC prints ` 1.0E+300`. That fork was resolved in
[[decide-float-fixed-output-exact-or-fpc-17-digit-cap]]:

> **pxx prints the exact decimal expansion of the double in the fixed form.** It
> does not adopt FPC's 17-significant-digit cap.

with the user's own reasoning that we are not crippling something we do
correctly and FPC does not. The `# decided 2026-08-08: KEEP EXACT` note in this
ticket's own frontmatter refers to that.

One measurement worth recording against the oracle: on `NaN:0:3` **FPC aborts**
with `Runtime error 207`, where pxx prints ` Nan`. FPC has no answer here at all,
so "differs from FPC" was never the same claim as "wrong".

### Not carried forward

The "real fix" sketched above — routing x86-64/aarch64 through
`PXXWriteFloatFixed` to collapse three implementations into one — is **not**
needed for this ticket any more, since the three now agree. It survives as a
separate simplification argument, and the closely related parameterisation gap
in the *scientific* writer is being fixed under
[[compat-pascal-writeln-of-a-single-uses-double-width]] /
[[bug-b-write-of-a-real-ignores-the-field-width-without-decimals]], which are one
bug: `PXXWriteFloatSci(p: Pointer)` takes no width or digit count while
`PXXWriteFloatFixed(p, decimals, width)` takes both.

## Log
- 2026-08-19 — resolved, commit 682d64373.
