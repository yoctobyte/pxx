# Addendum, 2026-09-16 — value parity on 7bf3860e0, and a toolchain that can be restated

Untracked, written by the lekkerzeilen seat. Beside
`bug-n-the-demo-leaks-16-mb-per-two-minutes-on-a-real-world-and-it-is-not-in-the-render-path.md`,
which is not modified by this file. Everything here was measured on this box;
nothing is quoted from a message.

## The stamp

    pascal26_sha   4bc890e6604c0103
    runtime_sha    4b46a93b191a0ad4      (sha256 of compiler/builtin/*.pas + Makefile)
    pxx_head       693c910b4             (contains 7bf3860e0; tier green; 0 tracked files dirty)
    demo_head      9521e53               (lekkerzeilen, + 7 uncommitted lines in app.py)

**This is the first artifact in the whole investigation whose toolchain is
completely restatable.** Every earlier arm had at least one unstamped or
uncommitted component: the compiler binary moved in a shared checkout, or the
program-side runtime (`compiler/builtin/*.pas`, thirteen files including the
allocator) changed without moving `pascal26_sha`, or both. `runtime_sha` exists
because of that second case, which is invisible to a compiler sha by
construction — a fix can add 117 lines to `pylib.pas` and leave `pascal26_sha`
untouched.

## Value parity — the demo's first wrong-VALUE check, and it passes

Four assertions against the **real** `lekkerzeilen` modules, compiled as an
in-package main:

    measure("abcde", 1.25)     37.5                    CPython 37.5    ok
    measure("abcde", 2)        60                      CPython 60      ok
    VALK.keel(0.5)             -0.3038233955393718     exact           ok
    keel fractional at every station of the hull                       ok

Both truncations found on 2026-09-15 are gone, and so is the compile-time
narrowing that briefly replaced one of them:

- `text.measure` returned **37** for 37.5 on `3aa02900de0f` — a return
  expression reading a bare parameter whose only typeable atoms were int-valued.
- `lines.VALK.keel(0.5)` returned **0** for -0.3038 — subscripting a **call
  result** directly in a return (`return self.section(t)[0][1]`). Binding the
  call to a local first was always correct, which is what made it bisectable.
  Fixed at `592bcc8eaaf3b215`.
- On `592bcc8eaaf3b215` `measure(line, 1.25)` briefly became a **compile
  error**, because `scale` narrowed to int on the strength of **one** observed
  call site. 191 of 357 typed parameters rested on a single site, 80 of them
  int. Resolved by not claiming ints at all.

A refusal to build counts as a parity failure exactly as a wrong number does:
both mean pxx and CPython disagree about what the code means.

The test lives at `tests/test_value_parity.py` in the lekkerzeilen tree, new and
untracked. It is green under CPython so the suite stays green in the normal
workflow, and it only bites when the suite is put through a pxx build.

## Static census — the hot path is still untouched, and this is the gate

    function        unannotated baseline    demo_p26local    lz7bf (this sha)
    Grid.at         12492 B / 481 calls     12492 / 481      12492 / 481
    Quat.rotate     24674 B / 864 / 0 SSE   24674 / 864 / 0  24674 / 864 / 0
    Vec3.__add__     6260 B / 210           6260 / 210       6260 / 210
    Vec3.dot         6645 B / 225           6645 / 225       6645 / 225
    TiledGrid.at    19608 B                 21143            19660
    World.number     1922 B / 36            2170 / 42        2170 / 42

**`Quat.rotate` is byte-identical to the unannotated baseline and still emits
zero SSE floating-point instructions across 864 calls**, although Quat's fields
type float from 11 sites. Scalar call-site typing types the object you already
knew about and leaves the operand you did not: `rotate(self, v)` reads `v.x`,
and `v` is a **method** parameter. An unresolved receiver is what makes a field
read dynamic; that is unchanged.

**Consequence, agreed with the compiler seat: P16 stays unscored.** It predicts
2.8-5.5 fps once inference reaches the hot path, and no fps batch should be run
against a sha whose disassembly already says the lever did not pull — a null
would read as evidence against the theory rather than against the measurement.
The gate is the two static numbers above: `Quat.rotate` dropping below 24674 B
and its SSE count leaving zero. Until those move, an fps measurement is wasted.

## Correction of record

The bug-2 candidate list (method call on a shadow-bound name colliding with a
module-level def) was an **over-count**. `tools/valuecensus.py` collected
shadow-bound names file-wide rather than per scope, so a `forward, right, up =
basis` unpack at app.py:3720 caused every `forward.cross(...)` in a 4000-line
file to be listed. `app.py:3926-3927` was tested on this sha and the camera
basis matches CPython bit-for-bit, signed zero included. That list was names,
not sites.

**Fixed rather than relabelled, same day.** The pass is now scope-aware:
bindings are collected per function scope with module scope counted separately,
a later plain `name = ...` in the same scope cancels the shadow, and nested defs
are excluded from an enclosing scope both when pushed and when popped. That last
clause was a second bug found while fixing the first — filtering only at push
time still walked every top-level def's body back into module scope, which
double-reported every hit and briefly made the "fixed" count read 20, higher
than the 16 it replaced. **16 file-wide names -> 11 scoped sites**, camera-basis
family gone. 9 of the 11 are `handle.read()` on a file object colliding with
`def read` in atlas/facades/png; the other two are `kind.build()` (app.py:1072)
and `entry.lines()` (ui.py:704). Deliberately narrowed away and not covered: a
binding made in an enclosing scope and used inside a closure. Still candidates —
none of the 11 has been tested against CPython, so this is a shorter list of
things to check, not a count of defects.

## What is NOT claimed

The residual **11.5 kB/s** is unchanged and still unowned: `angular` at 47.85
bytes/vessel-step in the angular integrator inside `Body.step`, and 79% in code
that has never been instrumented. Nothing shipped on 2026-09-15 or 2026-09-16
touches either. And an RSS slope cannot distinguish a repaired leak from a
premature free — every figure here says "RSS growth absent", never "leak fixed".
