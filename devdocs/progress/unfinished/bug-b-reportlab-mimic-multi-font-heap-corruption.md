---
track: N
prio: 30
type: bug
summary: "ROOT-CAUSED to bug-p-constructor-with-a-defaulted-variant-param-corrupts-memory and largely fixed by a workaround. The original font-count table was WRONG — an artefact of small samples against an intermittent fault. A rarer residual remains"
status: working
owner: agent-AN
---

# reportlab mimic: 4+ distinct fonts corrupts the heap

- **Type:** bug (memory corruption, intermittent) — Track B (`lib/pcl`)
- **Opened:** 2026-08-09
- **Found by:** the differential harness built for
  [[feature-lib-reportlab-fidelity-vs-oracle]] — `tools/reportlab_diff.py`,
  which reproduces it on 2 of its 3 cases.

## ROOT-CAUSED 2026-08-09 — and my first diagnosis here was wrong

**Retracting the font-count claim.** This ticket originally said "font COUNT,
not a particular font", with a table showing 4 setFont+draw at 2/12 and one font
at 0/12. That was **an artefact of small samples against an intermittent
fault**: the `positions` case, which uses ONE font, later failed on three
consecutive harness runs. Do not trust the table that used to be here; it is
removed rather than corrected, because its shape was the error.

**The actual cause** is [[bug-p-constructor-with-a-defaulted-variant-param-corrupts-memory]]:
a class constructor with a defaulted `Variant` parameter smashes the stack when
the caller omits the argument. `Canvas.Create(filename, pagesize = 0)` is
exactly that shape, and `canvas.Canvas("out.pdf")` is exactly that call.

How it was found, since the path matters: gdb on the faulting run showed the
crash inside `__crtl_utoa` — printf formatting, nowhere near PDF code — with the
whole stack overwritten by ASCII (`0x7c7c7c7c…` = `'|'`, argument bytes decoding
to `'FFFF'`). Reduction then went library -> Pascal-direct -> 12 lines with no
library at all.

Driving the mimic **from Pascal** made it deterministic — 25/25 crashes — which
is what turned an unfixable intermittent bug into a tractable one. From NilPy
the same defect is intermittent because the stack layout differs.

**Fixed here by a registered workaround** (`devdocs/dev/track-b-workarounds.md`):
two constructors, the one-argument form forwarding an explicit `0`, so the
defaulted-parameter path is never taken. Pascal-direct went 25/25 -> **0/30**,
and the harness's `text_fonts` and `positions` cases now pass consistently and
match reportlab to 0.000029 pt.

## Residual, still open — and my earlier measurements of it were WORTHLESS

**Correcting this ticket again.** It previously said the residual was "sensitive
to the output path length, not to the font count", citing 0/30 clean runs from
Pascal and NilPy with a short path against 1/30 with a long one. That reasoning
does not hold, and the method was the problem.

The crash rate is **ASLR-sensitive and varies enormously between loops of the
SAME binary**: 4/50 in one run of a loop and 13/20 in the next, with the binary
verified byte-identical (`md5sum` equal; the compiler's executable output is
deterministic — only `.map` files differ between compiles). So **a 0/N run
proves nothing here**, and every "0/30 clean" I recorded was luck being read as
evidence. Path length, font count and compile-then-run all looked causal for the
same reason and none of them survived a control.

What IS solid:

- **One consistent signature**, every catch:
  ```
  SIGSEGV in __crtl_utoa (out=0x7c7c7c7c7c7c7c5a, v=0xFFFFFFFFFFFFFFFF,
                          base=0x7C7C7C46, upper=0x46464646)
  #1..#N  0x7c7c7c7c7c7c7c7c in ?? ()
  ```
  The whole stack is overwritten with `0x7c` (`'|'`), and the garbage arguments
  decode to `0x46464646` (`'FFFF'`). Text is being written over the stack, and
  the fault lands in printf formatting only because that is what runs next.
- It survives the constructor fix (which was a real and separate bug), so it is
  a second defect with the same *shape*: something writing formatted characters
  past a buffer.
- `lib/vendor/pdfgen` driven from C is still clean, so the Pascal layer remains
  the place to look.

**How to measure it properly next time:** fix the binary, run at least 100
iterations, and compare rates only between runs of the SAME executable in the
SAME session — and never treat a zero as a fix. `setarch -R` to disable ASLR
would make the rate stable enough to bisect against.

Next tool per the playbook: `-dPXX_OBJTRACE` with `grep <addr>`.

## 2026-08-09 (Track B): re-measured — it is NOT multi-font and NOT the heap

Went back to this with the differential harness and measured instead of
trusting the title. Both halves of that title are wrong.

**Not multi-font.** Crash rate over 12 runs of each harness case:

| case | fonts | rate |
| --- | --- | --- |
| `positions` | 1 | 7/12 ok |
| `text_fonts` | 4 | 6/12 ok |
| `many_fonts` | 5 | **9/12 ok** |

Flat, and the *most* fonts is the *best*. Varying `drawString` count 1..8 with a
single font is likewise flat (~18/20 at every count). Neither font count nor
string count is the variable.

**Not the heap — it is a stack overrun.** Caught under gdb (fault site is
consistently `rip=0x5c458e`):

```
mov %cl,(%rax)        <- unguarded byte store, SIGSEGV
rax = 0x00007ffffffff000   <- the stack GUARD PAGE
rbp = 0x00007fffffffccb0
```

The store address is `rbp-0x3c + index`, and the 32-bit index at `rbp-0x6c` had
run to **0x238c = 9100** (visible in the stack dump as `0x0000238c00000000`,
with `0x238d` next to it). So something walks a byte-write loop up the stack
from a small frame-local until it hits the guard page. The bytes going in are
ASCII digits and `0x7c`. That is a stack overrun, not heap corruption — which
also explains why `-dPXX_HEAP_DEBUG` only ever showed it as a rate, never as a
poisoned heap block.

**Minimal repro is three lines and has no text or fonts in it at all:**

```python
from reportlab.pdfgen import canvas
c = canvas.Canvas("out.pdf")
c.showPage()          # <- remove this line and it is 20/20 clean
c.save()
```

`showPage()` is the trigger: `save()` alone is **20/20 ok**, `showPage()+save()`
is **16/20**, and adding `setFont` (still no text) is **17/20** — i.e. the same
rate, so `setFont` adds nothing. Every earlier variable was noise on top of this.

**Ruled out along the way** (each measured, not argued):

- crtl `strncpy` — correctly bounded, so `force_locale`'s `strncpy(buf, .., 31)`
  in the vendored `pdfgen.c` cannot overrun;
- crtl float formatting — `snprintf("%f %g %.10f")` over the exact A4 constants
  and 1e-300 is **20/20 clean** and digit-correct;
- `__crtl_vformat` — every buffer write is guarded by `if (o + 1 < cap)`.

**A `-g` build does not crash** (0 in 60 runs) — the layout shift hides it. That
is what blocks naming the exact routine, since pxx emits no symbol table so the
frame is `?? ()`. Next step is to symbolize without perturbing layout: a map
file, or `PXXDBG=a.ir` on the `showPage` path in `mimic_reportlab_pdfgen.pas`.

**Retitle when picked up** — the slug still says `multi-font-heap-corruption`
and both halves are now disproven. Left in place only so existing links resolve.

## 2026-08-09 (Track B): isolated to the NILPY path — re-filed to Track N

Kept narrowing after the stack-overrun finding above, and the bug leaves Track B
entirely. Four builds, same calls, same library, same vendored C writer:

| driver | build | rate |
| --- | --- | --- |
| vendored `pdfgen.c` alone, `pdf_append_page` + `pdf_save` | **gcc** | 25/25 ok |
| vendored `pdfgen.c` alone, same | **pxx (C frontend)** | 25/25 ok |
| `Canvas.Create` + `showPage` + `save` | **pxx (Pascal)** | 25/25 ok |
| `canvas.Canvas(...)` + `showPage()` + `save()` | **pxx (NilPy)** | 16/20, 23/25 |

Controlled for the obvious confounder: the Pascal case was re-run writing to a
real file (25/25) and the NilPy case re-run writing to `/dev/null` (still
crashes), so the output path is not the variable. The Pascal program goes
through the *same* `mimic_reportlab_pdfgen` -> `mimic_reportlab_pdfbase` ->
`pdfgen.c` chain and links the same `pylib`.

So the shim, the bridge unit and the C writer are all clean; only the NilPy
frontend's lowering of these calls crashes. **Re-filed `track: N`.** It may
bottom out in shared IR (Track A) rather than `pyparser`/lowering — that is for
N to determine, and N owns the first look either way.

Track B's part is done: the shim was fixed (one-arg ctor, exact A4, `PChar()`),
and `text_fonts` matches real reportlab to 0.000029 pt whenever it completes.

**Note for whoever takes it:** both builds emit a C/Pascal name-collision
warning (`nan` vs `NaN`, `bcmp` vs `BCmp`, "binding to the C declaration"). The
Pascal build is clean despite its warning, so a collision is not sufficient on
its own — but silent same-signature collisions are the known hazard class here
(`test/cmath_no_pascal_hijack.c`) and are worth ruling out early.

## 2026-08-15 (Track N): the faulting routine is NAMED, and the '|' flood is a CONSEQUENCE

Measured against a self-hosted fixedpoint at 7473a64ab. Repro is the ticket's
own three lines, writing to `/dev/null`.

**Rate:** 0/40 with ASLR on, **2/40 under `setarch -R`**. So disabling ASLR does
not make it deterministic — layout is not the only variable, and the ticket's
suggestion to bisect under `setarch -R` will not work as written. Something else
nondeterministic feeds this.

**The faulting routine is crtl's `__crtl_utoa`** (`lib/crtl/src/stdio.c:102`),
established by mapping the address rather than guessing: the image is a single
`LOAD` at `0x400000`, so `rip=0x644e41` is file offset `0x244e41`; `objdump -D -b
binary` there gives the store, and the same instruction sequence appears exactly
once in `compiler/pascal26 -S`, under the label `__crtl_utoa`. That
independently confirms the original gdb signature, which had been recorded when
the frame was `?? ()`.

**State at the fault** (gdb, frame offsets read from the emitted prologue —
`out` at `rbp-8`, `v` at `rbp-16`, `base` at `rbp-20`, `upper` at `rbp-24`,
`n` at `rbp-64`, `tmp[32]` at `rbp-60`):

```
base=0x7C7C7C46  upper=0x46464646  n=9533
v=0xFFFFFFFFFFFFFFFF  out=0x7c7c7c7c7c7c7c7c
tmp: "a4470449" "0e39da1c" "ffffffffffffffffffff" "FFFF" "||||" ...
```

Read that buffer left to right and the mechanism falls out:

1. The first **16 digits are correct lowercase hex** — so `base` was 16 and
   valid, and the loop was working.
2. Then `v` sticks at all-ones and the loop writes `f` forever. It stops
   shrinking at exactly the iteration where it should have reached 0.
3. At digit 32 `tmp` overflows its own frame — `tmp[32..35]` is `upper`,
   `[36..39]` is `base`, `[44..51]` is `out`. **The routine smashes its own
   parameters**, which is why `base` becomes `0x7C7C7C46` and the digits turn
   into `F` and `|` (`'0' + 76` = `'|'` for a garbage base).
4. With `base` garbage the loop cannot terminate at all, and `n` walks up the
   stack to the guard page — the `0x7c` flood and the `SIGSEGV` on
   `mov %cl,(%rax)` with `rax = 0x7ffffffff000`.

**So the stack full of `'|'` is the LAST step, not the first.** Every previous
round of this ticket started from that flood and looked for something writing
text over the stack; there is no such thing. There is one small buffer that
overflows into its own frame after the loop that fills it fails to terminate.

**What is NOT wrong:** 64-bit unsigned division. `tools`-free C probe of the
same loop compiled by pxx — variable base, constant base, dividends with the
high bit set (`0xc1ad93e094407044`, which is the shape of the value being
formatted here), bases 8/10/16, plus `while (d) d = d / 16` — is byte-identical
to gcc. Whatever stops `v` shrinking is not the plain divide.

**A probe INSIDE the loop does not fire.** Instrumented `__crtl_utoa` to write
`n/base/v/nextv` through `__pxx_write` whenever `n >= 20`: the build still
crashes at the same rate (3/40) and **never prints a line**. That has to be
explained before any in-loop instrumentation is trusted — either the crashing
path is not the one instrumented, or the write is lost. It is the next thing to
settle, ahead of any further theory.

**Independent of the trigger:** `__crtl_utoa`'s digit loop has **no bound on
`n`**. A wrong `base` turns a `printf` into an unbounded stack write rather than
a wrong string, which is what makes this catastrophic instead of cosmetic.
Filed as [[bug-c-crtl-utoa-digit-loop-is-unbounded]] — deliberately NOT fixed
here, because bounding the loop would hide the defect that is still unnamed.

**Still open:** why `v` stops shrinking. Parked here rather than guessed at.
