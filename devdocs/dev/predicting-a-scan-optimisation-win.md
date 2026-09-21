# Predicting a scan-optimisation win before building it

**Measured 2026-09-21, four programs, step counts spanning 176x.** Removing a
linear-scan step from the pxx compiler costs **8.0–9.4 ns**. So you can state
the win from a step COUNT, before writing the optimisation.

    win_seconds  ~=  steps_removed  x  9 ns
    share        ~=  win_seconds / current_wall_clock

## The measurement

    ./compiler/pascal26 -dPXX_UCLS_STATS -dPXX_UCLSIDX_OFF compiler/compiler.pas compiler/p26_stats
    ./compiler/p26_stats <your flags> <subject> /tmp/out.bin 2>&1 | grep 'UCLS calls=' | tail -1

prints `calls=`, `UClsCount=`, `scanned>=`, `realsteps=`, `pool=`, `toks=`.
**`realsteps` is the number to use.**

## The four rows it rests on

    program          steps removed    saved    ns/step   share
    lekkerzeilen         ~4305 M      34.38s     7.99     38.7%
    uforth                 309.3 M     2.90s     9.38     28.4%
    render_backend          57.9 M     0.50s     8.64      6.4%
    key_analysis            24.3 M     0.40s    16.4      12.5%

Two independent derivations agree on lekkerzeilen: **7.99 ns/step** from the
saving, **9.9 ns/step** from a PC profile (`FindUClassImpl` 31.1% + `UNameMatch`
10.6% + `UsesRankOf` 6.1% = 47.8% of 88.789s over 4.305e9 steps).

**The key_analysis row is the one to DISTRUST, not the one to explain** — a
0.40s saving read at 0.10s rep resolution on the smallest subject, honest
interval 12–20 ns. Left as measured.

## Three ways to misuse this

**1. `scanned>=` IS NOT `realsteps`.** `PxxFUCIters` adds `UClsCount` once per
call; `FindUClassImpl` runs up to THREE full scans, and scan 1 (routine-local
types) ranks by `ScopeHopsToProc` and **has no early exit**, so it runs to
completion on every call. The counter is a **lower bound**.

**2. THE RATIO BETWEEN THEM DOES NOT TRANSFER BETWEEN PROGRAMS.** Measured
`realsteps`/`scanned>=`: **2.97, 2.48, 2.30, 2.03** (lekkerzeilen,
key_analysis, render_backend, uforth). It is set by how often scans 1 and 2
fail — a property of the program's scope structure. This lane projected uforth
by scaling its counter by **lekkerzeilen's** 2.97 and came out **46% high**.
Measure `realsteps` on the program you are talking about.

**3. DENSITY IS A RESTATEMENT, NOT EVIDENCE.** Steps removed per second of
compile is monotone with the share (48.5 / 30.3 / 7.6 / 7.4 M per second ->
38.7 / 28.4 / 12.5 / 6.4 %) and **cannot fail to be** — it is density times a
near-constant. It names the quantity to ask about for a new program; it
corroborates nothing.

## What is NOT established

That 9 ns/step generalises beyond `FindUClass`-shaped work: a tight loop over
compact parallel arrays, whose first test is an integer length reject, calling a
non-inlined `UNameMatch`. **A differently-shaped scan may cost differently and
nobody has measured one.** Also unexplained: 8–9 ns is ~25–30 cycles for that
loop, which is slow enough that the residual is probably not instruction count —
so a second, smaller win may exist in how `UClsNOff`/`UClsNLen`/`UClsUnitIdx`/
`UClsOwnerProc` are laid out. Speculation, not a finding.

Full method, both refuted hypotheses and the retraction:
`devdocs/perf/lekkerzeilen-build-time.md`.
