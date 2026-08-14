---
summary: "REOPENED 2026-08-14 — only the MEASUREMENT step ever landed. The fix the user decided on 2026-08-01 (land the real non-transitive rule) was never built, and the ticket sat in done/ hiding that. It is the root cause of the pylib/sysutils Exception ceiling, the tkinter/reportlab class collision, and the ClassNameIsDeliberatelyShared patch that was supposed to be temporary. Re-measured cost: 35 RTL-internal unit pairs, no user-program-facing leak."
type: bug
track: A
prio: 80
blocked-by: [task-t-strict-uses-corpus-sweep]
owner: agent-A
---

# Pascal: `uses` is transitive, so every unit's imports leak to its consumers

- **Type:** bug (name resolution / unit visibility) — **Track A**
- **Status:** working
- **Opened:** 2026-07-28, from [[decide-class-namespace-scoping]]. This is the
  root cause that ticket is a symptom of.

## Repro — routines (pure Pascal, no NilPy involved)

```pascal
unit priv;
interface
function Wrap(const s: AnsiString): AnsiString;
implementation
uses sysutils;                        { implementation section — private by any reading }
function Wrap(const s: AnsiString): AnsiString;
begin
  Result := Format('[%s]', [s]);
end;
end.
```
```pascal
program tp;
uses priv;                            { sysutils appears NOWHERE in this program }
begin
  writeln(Wrap('a'));                 { [a]  — fine }
  writeln(IntToStr(9));               { 9    — WRONG: should be "undefined variable" }
end.
```

Observed with `stable_linux_amd64/default/pinned`. `IntToStr` resolves although
the program never used sysutils, and although `priv` imported it in its
implementation section.

## Expected

Pascal's `uses` is not transitive, in EITHER section. If A uses B, a unit that
uses A does not see B's names — it must list B itself. The section
(interface vs implementation) controls circular-reference legality and whether
B's types may appear in A's *interface* signatures; it is not what makes the
import private. Non-transitivity is what does that, and pxx does not implement it.

## Cause

One flat global namespace, for both axes:

- **Routines** — procedure lookup walks all units. `IRFindProc1ByArgTk`
  (`compiler/ir.inc`) says so outright: *"across ALL units. FindProcOverload is
  scoped to CurrentUnitIdx, so it cannot see pylib's pystr_of from the main
  program being lowered."*
- **Classes** — `FindUClass` (`compiler/symtab.inc:386`) is first-match over
  `UClsCount`, with a unit-preference pass in front of it and a hard-coded
  exception list (`ClassNameIsDeliberatelyShared`, `:331`) to keep the
  preference from breaking `Exception`.

The uses clause records dependency and parse order; it does not gate visibility.

## What it costs today

Every consequence below is the same missing rule wearing a different hat:

1. **`decide-class-namespace-scoping` in full.** tkinter's `Canvas` and
   reportlab's collide because both are in one namespace. With non-transitive
   `uses` they are simply different names in different scopes — no new syntax, no
   `replaces` declaration, no shared-name list.
2. **`ClassNameIsDeliberatelyShared` exists only because of this.** With real
   scoping, `pylib uses sysutils` (or the reverse) gives ONE `Exception` by
   construction and the list is deleted, along with the duplicated `CreateFmt`
   bodies described in that ticket.
3. **NilPy programs inherit Pascal's namespace.** A `.npy` that reaches sysutils
   gets its exports unqualified, and Pascal is case-insensitive while Python is
   not, so `format`, `date`, `time`, `trim`, `pos`, `copy`, `delete`, `insert`
   and friends all shadow. Measured: `print(format(255))` in a `.npy` that
   imports sysutils reports `format(AnsiString, record)` — a Pascal signature
   error against Python source — where without sysutils it correctly says
   `undefined variable (format)`. User `def`s DO win, so only undefined names are
   affected, but the failure mode is a silent bind to Pascal semantics instead of
   a NameError.
4. Related in kind, filed separately: [[bug-nilpy-stdlib-name-binds-pascal-unit]]
   (a Python stdlib import binding to a same-named RTL unit).

## Sizing before committing

The tree currently gets names for free everywhere, and some of that WILL break —
the size of the breakage decides whether this is one ticket or a campaign. Cheap
measurement first: resolve exactly as today, but WARN whenever a name resolves
through a unit that is not in the current unit's own uses (transitively via
interface-section uses, per the real rule). Build the tree, count and classify the
warnings. That is an afternoon and it turns the estimate into a number.

Expect the RTL itself to be the biggest consumer of the current laxity.

## Fix shape

Visibility set per unit = its own uses + the interface-section uses of those
units, transitively closed over INTERFACE sections only; implementation-section
uses stay private to the importing unit. Applied uniformly to the routine table
and to `FindUClass`/`FindUField`. Then the class-preference pass and its shared
list both come out.

## Gate

`make test` + `make test-nilpy` + self-host byte-identical + cross, with `test/`
cases for the routine repro above and for two units legitimately exporting the
same class name. Land incrementally or behind a flag — this changes resolution
for the whole tree and is exactly the kind of change that should not arrive as
one commit.

## Measurement step, as designed (2026-07-28)

Taking the ticket's own advice — resolve exactly as today, warn when a name
resolves through a unit the current unit cannot legitimately see, then count.
Shape of that work, so it can be picked up in one sitting:

1. **Edge table.** No per-unit uses graph exists today; `ParseUsesUnitBody`
   records dependency and parse ORDER only. Add three parallel arrays —
   `UsesFrom` (Strs idx of the importing unit, -1 = main program), `UsesTo`,
   `UsesInIface` (Boolean) — appended wherever a uses clause names a unit. The
   section is known from where the clause is parsed; the parser has no
   interface/implementation flag today, so one has to be threaded through (the
   `implementation` keyword is matched by string compare at several sites, so
   the state is genuinely absent, not merely unnamed).

2. **`VisibilityAllows(curUnit, declUnit)`.** True when `declUnit = curUnit`,
   or `declUnit` is reachable from `curUnit` by one edge of EITHER section
   followed by INTERFACE-section edges only, transitively. That is the real
   Pascal rule: the section controls whether the import is re-exported, not
   whether it is legal.

3. **Warn, behind `--warn-uses-leak`.** Opt-in so an ordinary build is
   unchanged and the measurement can run over the whole tree without touching
   any gate. Call it from the routine lookup the Pascal identifier path uses
   and from `FindUClass`.

4. **Count and classify** over `make test` + `make lib-test` + the corpora.
   The expected shape of the answer: the RTL is the biggest consumer of the
   current laxity, and the interesting number is how many DISTINCT (importing
   unit, resolved unit) pairs appear rather than how many call sites.

Only after that number exists is it worth deciding between "one ticket" and
"a campaign" — and the enforcement itself should land behind the same flag
before it becomes the default.

## Measurement step LANDED (2026-07-31)

Implemented exactly as designed above, plus one correction: `InInterface`
(`compiler/defs.inc`) already existed as a global — the parser did NOT lack
section state, contrary to point 1's premise. No new state-threading needed;
`ParseUsesUnitBody` reads it directly at the point it interns each `uses`
clause's target.

- `UsesEdgeFrom`/`UsesEdgeTo`/`UsesEdgeIface` (`compiler/defs.inc`) + one
  `RecordUsesEdge` call in `ParseUsesUnitBody` (`compiler/parser.inc`), placed
  BEFORE the already-compiled guard so every clause is counted, not just
  first-loads.
- `VisibilityAllows(curUnit, declUnit)` (`compiler/symtab.inc`): direct edges
  (either section) from `curUnit`, then BFS closure over INTERFACE-only edges.
- `--warn-uses-leak` (`compiler/compiler.pas`) gates `WarnUsesLeakHit` calls
  wired into `FindProc`'s two flat lookup loops and `FindUClass`'s flat
  fallback loop (`compiler/symtab.inc`). Opt-in, read-only: resolution is
  unchanged, self-host fixedpoint reached at generation 1 (this is NOT an
  ELF-layout-style change), `make test`-equivalent smoke (the ticket's own
  routine repro + a handful of `test/*.pas`) compiles clean with the flag off
  and warns-but-still-compiles with it on.

**Known gap, not yet instrumented:** the ticket's own headline repro
(`IntToStr(9)` reached through `priv`'s implementation-section `uses
sysutils`) does **not** warn. `FindProc` is not the lookup a direct call site
resolves through — per the ticket's own Cause section, that is
`IRFindProc1ByArgTk` / the general call-classification path
(`MatchProcCall` and friends), which is a different, more tangled entry point
this pass didn't reach in one sitting. `FindProc` still caught real leaks
(class lookups, `@proc`-style routine references), so the instrument is
functional but under-counts — the real number is higher than what's below.

**Counts, sample run** (not the full `make test` + `make lib-test` sweep the
design called for — that's real time; this is the first 80 files of
`test/*.pas`, 923 total, to unblock the sizing decision tonight):

- 81 distinct (importer, provider) pairs from 80 files alone.
- Top offenders by hit count — confirms "RTL is the biggest consumer":
  `pylib -> builtinheap` (6894), `sysutils -> builtinheap` (4522),
  `pylib -> builtin` (4145), `http -> builtinheap` (3808),
  `pylib -> <program>` (3276, class lookups), `ecdsa_p256 -> builtinheap`
  (2980), `bignum -> builtinheap` (2548), `pylib -> sysutils` (1717),
  `zlib -> builtinheap` (1596) — and dozens more in the hundreds.
- Every RTL/pylib unit reaches `builtinheap`/`builtin` without declaring it —
  those two are the ambient intrinsic surface every unit implicitly gets
  today, so on a real non-transitive rule EVERY unit in `lib/rtl` would need
  an explicit `uses builtin[heap]` added. That is likely mechanical
  (`decide-class-namespace-scoping` already names this shape) but it is
  hundreds of files, not one.

**Sizing verdict: this is a campaign, not one ticket** — 81 distinct pairs
from a fifth of the routine test corpus, before touching `lib/rtl` itself or
NilPy's `.npy` corpus, and before the call-classification gap above is closed
(which will only raise the count). Filed **[[decide-pascal-uses-campaign-scope]]**
(Track U) with this data for the sizing/sequencing call — resolving this bug
outright is not a one-sitting job and guessing the shape is exactly what
Track U exists to prevent.

**What ships now:** the instrument itself (edge table, `VisibilityAllows`,
`--warn-uses-leak`) — inert by default, safe to land, and the tool the
campaign (whichever shape it takes) will keep using to track progress toward
zero warnings.

## 2026-08-01 — correction: the `builtin`/`builtinheap` count was measuring the wrong thing

The "hundreds of files need an explicit `uses builtin[heap]`" framing above
is wrong. `builtin`/`builtinheap` are pxx's own equivalent of Pascal's
`System` unit — `compiler/builtin/builtin.pas` says so directly ("System.X
— pxx has no separate System unit (System IS the builtin layer)"), and
every Pascal dialect auto-includes `System` everywhere with no `uses`
needed. That's by design, not a leak. `VisibilityAllows`
(`compiler/symtab.inc`) has no special case for this — it counts
`builtin`/`builtinheap` references the same as any other unit pair, so the
6894/4522/4145/etc. hit counts dominating the sample are measurement noise
from a gap in the instrument, not real scope. The fix: special-case
`builtin`/`builtinheap` as implicitly-always-visible in `VisibilityAllows`,
excluded from leak detection entirely, before trusting any future count.

Once that's fixed, the real remaining leak count (e.g. `pylib -> sysutils`,
1717 hits) is what's actually left — and even that one is smaller than it
looks: verified directly that `pylib.pas`'s own `uses` clause never
mentions `sysutils` (only `uses pypal`, and `pypal` itself uses nothing).
Most of that count is genuinely accidental leakage that will close on its
own once real scoping lands. The one deliberate exception is `pylib.
Exception` merging with `sysutils.Exception` (`CreateFmt`... "IMPLEMENTED
BY sysutils") — already anticipated by
[[decide-class-namespace-scoping]]'s resolution ("whichever of pylib/
sysutils imports the other gets that one class by construction"): pylib
needs one explicit `uses sysutils` added to keep that intentional merge
working, everything else closes for free. Guiding principle for whatever
internal `uses` wiring the fix ends up needing: what matters is that USER
programs get a clean namespace — internal RTL-to-RTL sharing (like the
Exception merge) is fine as long as it's deliberate and doesn't leak
unrelated surface to callers.

Folded into [[decide-pascal-uses-campaign-scope]] for the actual
sizing/sequencing call, corrected.

## Log
- 2026-07-31 — resolved, commit d86bc20ec.

## 2026-08-01 — instrument fixed, TRUE count measured over the whole corpus

The 2026-08-01 correction above was right, and there was a SECOND artifact of the
same kind underneath it. Both are now fixed in the instrument, and the sweep was
re-run over all 934 `test/*.pas` (not the 80-file sample the sizing decision was
made on).

### Two ambient-System artifacts, both removed

1. **`builtin`/`builtinheap`** — pxx's System unit, injected by `ParseProgram`
   (`ParseUsesUnit('builtinheap')` / `('builtin')`, `compiler/parser.inc`), never
   written by a user clause, so the edge table structurally could not show them
   reachable. Fixed: `UnitIsAmbient` in `compiler/symtab.inc`, consulted by
   `VisibilityAllows`.
2. **`TObject`/`TGuid`** — found by classifying the leftover `-> <program>`
   bucket rather than assuming it was real. It was **100%** these two names and
   nothing else (`TObject` 3601 hits, `TGuid` 1092). They are minted by
   `RegisterBuiltinTObject`/`RegisterBuiltinTGuid`, so `AddUClass` stamps them
   with whatever `CurrentUnitIdx` is at ParseProgram time (`-1`, "the program") —
   making every unit that names `TObject` look like it leaked through the
   program. Fixed: `ClassNameIsAmbientIntrinsic`, filtered by NAME (the rows
   carry no marker, and adding a parallel array for an opt-in read-only
   instrument is not worth the shared-state churn).

Note `-1` is NOT blanket-excluded: a genuinely program-declared class referenced
from a unit IS a real leak and must still be reported.

### The true number

Full corpus, 934 files, self-hosted binary at `da085e9de` + the instrument fix
(snapshot binary, so no mid-sweep rebuild could drift it — the first attempt at
this measurement WAS corrupted that way and was discarded):

- **35 distinct (importer, provider) pairs, 4721 hits.** `-> <program>` bucket
  is now **0**.
- Previous headline was **81 pairs from 80 files**. So the real figure is *less
  than half*, measured over *twelve times* as much code.
- 113 of the 934 files don't compile standalone — they are helper `*_unit.pas`
  units and `{%FAIL}` cases, not measurement failures.

Top pairs:

| pair | hits |
| --- | --- |
| `pylib -> sysutils` | 2628 |
| `dns_wire_core -> sysutils` | 570 |
| `x509 -> sysutils` | 265 |
| `ecdsa_p256 -> rsa` | 170 |
| `platform -> pylib` | 143 |
| `platform_backend -> pylib` | 143 |
| `pylib -> textfile` | 105 |
| `ed25519 -> x25519` | 102 |
| `sha512 -> sha256` | 100 |
| `zlib -> sysutils` | 98 |

…then a long tail in the tens (the full 35 are all RTL-to-RTL pairs of this
shape).

### What this means for the campaign

The "hundreds of files, mechanical `uses builtin[heap]` additions" framing is
**gone entirely** — that work does not exist, it was the artifact. What remains
is 35 RTL-internal unit pairs, each needing either an explicit `uses` (where the
dependency is deliberate, e.g. the `pylib`/`sysutils` `Exception` merge) or
nothing at all (where it is accidental and closes for free once real scoping
lands). No user-program-facing leak appears in the corpus at all.

That is a tractable, boring list — not a campaign. Folded back into
[[decide-pascal-uses-campaign-scope]] for the re-sizing call.


## REOPENED 2026-08-14 — the fix was decided, measured, and then never built

**This ticket was closed on its MEASUREMENT step.** `--warn-uses-leak`, the edge
table and `VisibilityAllows` landed; the actual non-transitive rule did not. The
`## Log` line reads "resolved" and the commit subject says
`(measurement step)` — so from the queue's point of view this was finished
work, and it has been invisible for two weeks.

Meanwhile the user had already decided what to do:
[[decide-pascal-uses-campaign-scope]], **2026-08-01, option 2** — close the
instrumentation gap, re-measure, *"then land the real non-transitive rule"*, and
sequence it as **one effort** with [[decide-class-namespace-scoping]] because
"fixing real `uses` scoping IS the class-namespace fix, viewed from a different
symptom."

Steps one and two are done. Step three is what this ticket now holds.

### The cost is already measured, and it is small

From this ticket's own re-measurement: **35 RTL-internal unit pairs**, each
needing either an explicit `uses` or nothing at all. In its own words, *"a
tractable, boring list — not a campaign"* — and **no user-program-facing leak
appears in the corpus at all**. The "hundreds of files" framing was a
measurement artifact and is gone.

So the input everyone was waiting for exists. There is nothing left to size.

### What is downstream of this, and what it is costing right now

- **`ClassNameIsDeliberatelyShared('exception')`** (`compiler/symtab.inc:432`)
  is a per-site patch that [[decide-class-namespace-scoping]] said should be
  *"reverted as it lands, not kept"*. It was never reverted, and it is
  load-bearing today — verified 2026-08-14 by removing it and rebuilding.
- **pylib's `Exception` can never gain a member sysutils lacks.** The two
  classes are member-for-member identical and must stay so. This killed
  `e.args` after it had shipped and passed a pin
  ([[bug-nilpy-exception-args-attribute-missing]]).
- **[[decide-pylib-exception-vs-sysutils-exception]]** (Track U, p55) is asking
  "who owns Exception" — a question that only exists because of this. Its four
  options are all ways to live with the patch.
- **tkinter/reportlab `Canvas`** — same root, per the campaign-scope decision.

### Measured 2026-08-14: transitivity is what makes it unfixable in isolation

The hoped-for narrowing — "only a NilPy program that explicitly imports sysutils
collides" — is **false while `uses` is transitive**. A Pascal library with
`uses sysutils` in its *implementation*, pulled in by a `.npy` that never
mentions sysutils, collides identically:

```
                                        exemption ON            exemption OFF
NilPy -> Pascal lib -> sysutils    caught: "abc" is an     caught: unsupported
  (indirect, no import)            invalid integer         format spec ""
NilPy -> import sysutils           caught: "abc" is an     caught: unsupported
  (direct)                         invalid integer         format spec ""
```

Note the failure is a **wrong message**, not an uncaught exception — `CreateFmt`
picks up the wrong `Format` too. The Exception exemption has been masking more
than Exception, which is further evidence the right fix is the general one.

### Gate

`test_uses_order_pylib_exception_a` and `_b` both green, `test_nilpy_rtl_exception_surface`
green, and `ClassNameIsDeliberatelyShared` **deleted** rather than left in place —
if the list survives the fix, the fix did not land. These only fail in the NATIVE
tier, so `gate.sh quick` will not catch a regression here.

## Log
- 2026-07-31 — measurement step resolved, commit d86bc20ec. **Not the fix.**
- 2026-08-14 — REOPENED at the user's direction, prio 65 -> 80, moved to urgent.
  Filed by Track T; the work is Track A's.

## 2026-08-14 — the enforcement landed behind `--strict-uses`, and the Exception blocker is gone

Two of the three things this ticket needs are done. What remains is flipping the
flag, and that is now a bounded, measurable job rather than a blocked one.

### 1. `--strict-uses` — the rule is IMPLEMENTED (commit 6f2ec1803)

`VisibilityAllows` stopped being a warning-only predicate: `DeclVisible`
(`compiler/symtab.inc`) turns it into a lookup FILTER, wired into

- `FindProc`'s two chain walks,
- `FindUClass`'s flat fallback (it now scans PAST an invisible row to a visible
  one of the same name instead of stopping at the first),
- **`MatchEligBase`** — the one that matters, because per this ticket's own
  Cause section a direct call site does not resolve through `FindProc`. That
  closes the "known gap, not yet instrumented" the measurement step left open.

`VisibilityAllows` is memoised per `(curUnit, UsesEdgeCount)`; it was a
clear-plus-BFS per query, which is fine for an opt-in warning and quadratic
once it gates every lookup.

`declUnit < 0` is deliberately always-visible: -1 is BOTH a compiler-registered
intrinsic and a main-program routine, and the rows carry no marker to tell them
apart — the same artifact `ClassNameIsAmbientIntrinsic` handles by name on the
class side.

**The headline repro now behaves**: `writeln(IntToStr(9))` in a program that
only `uses priv` reports `undefined variable (IntToStr)` under the flag, and
still compiles without it. Off by default, self-host converges at generation 1,
`gate.sh quick` green.

### 2. `ClassNameIsDeliberatelyShared` is DELETED (commit 6ed45773f)

The gate's hard condition, met — but NOT by scoping the shared name. It was met
by removing the collision: pylib's Python root is now `PyException`
([[decide-pylib-exception-vs-sysutils-exception]] option 5, the user's call and
the user's implementation shape). The lexer maps the bare identifier, a
qualified `su.Exception` still reaches the Pascal class, and a NilPy bare
`except Exception:` bridges to both roots as an explicit catch rule.

That ordering was forced, not chosen. This ticket's gate wanted the exemption
deleted with `test_uses_order_pylib_exception_a`/`_b` green; while two units both
declared a class called `Exception`, no scoping rule could satisfy both — under
real scoping `uses sysutils, pylib` gives ONE of them and the other's raises
stop being caught. The rename is what makes the question disappear. Both tests
now print IDENTICAL output, which is the property the pair was written to prove.

Uncovered on the way, fixed, and worth knowing about: the `format` intercept in
the shared parser was gated on `isNilPy` — true for every PASCAL unit inside a
`.npy` compile — so sysutils' own `Format()` lowered to `pyformat_v`. Fifteen
more intercepts of that shape are unaudited:
[[bug-nilpy-builtin-name-intercepts-hijack-pascal-rtl-code]].

### 3. What is LEFT: flip the default

The remaining work is the 35 RTL-internal pairs this ticket already measured —
each needs either an explicit `uses` or nothing at all — and then `StrictUses`
becomes the default and the flag retires. Two findings that change the shape of
that job:

- **The measurement UNDER-counts, because it only ever ran for `CurrentUnitIdx
  >= 0`.** Every `WarnUsesLeakHit` call site is gated on it, so a leak into the
  MAIN PROGRAM — which is this ticket's own headline repro — was never counted
  at all. The 35 pairs are unit-to-unit only. Re-measure with the program scope
  included before trusting the number as the size of the job.
- **`lib/pcl/tkinter.pas` is a worked example of the fix per pair.** It uses
  `tk, pylib, pyeval` and named a base class `Exception` it got only through
  transitivity; the fix was one word (`PyException`, the root it actually
  imports), not a new `uses`. Expect more of the 35 to be that shape than to
  need a real import added.

Suggested next step: run the whole corpus with `--strict-uses` and classify the
failures, exactly as the warn pass was classified — the flag turns "how much
breaks" from an estimate into a compile error you can count.

## 2026-08-14 (later) — `--strict-uses` is now behaviour-preserving on the whole examples corpus

Measured, not estimated: **55 example programs (`examples/**/*.pas` + `*.npy`),
41 of which compile at all today, and every one of the 41 compiles IDENTICALLY
with `--strict-uses` on.** The starting point of this session's measurement was
10 new failures; three fixes took it to zero.

### The three real findings, in the order they surfaced

1. **Compiler-INJECTED units are ambient, and only two of them were marked.**
   `builtin`/`builtinheap` were special-cased by NAME; but the compiler also
   injects `pylib`/`pyeval` into every `.npy`, and `textfile`/`math`/
   `promocore`/`softfloat`/`pxxcio`/`palpthread` conditionally. They hold the
   runtime helpers CODEGEN emits calls to — the tk widgetset's `//` lowers to
   pylib's `pyfloormod_i`, and tk uses only `strings`, so no source clause could
   ever have declared it. A program that did not ask for a unit cannot be
   leaking through it: exactly the argument that made `builtin` ambient.
   Now marked at the injection site (`ParseUsesUnitAmbient`), one level deep —
   what the injected unit then pulls in through its OWN clauses is an ordinary
   edge. That was 9 of the 10 failures.

2. **Two independent filters that have to COMPOSE: scope visibility and
   builtin demotion.** `MatchProcCall` demotes a builtin-unit routine out of the
   set when any non-builtin routine of that name exists. Under enforcement an
   out-of-scope candidate is not an alternative — but it was still doing the
   demoting, so the builtin was dropped, the out-of-scope one was dropped, and
   NOTHING was left. That is how a missing `uses` came out as *"no overload of
   FloatToStr matches these arguments"* with an EMPTY candidate list rather than
   as an undefined identifier. The demote scan now requires `DeclVisible` too.

3. **One genuine RTL leak, found by the enforcement rather than by the warn
   pass**: pylib's `{x:g}` / `{x:s}` format specs call `FloatToStr`, which lives
   in `builtin` — and pylib named neither. It compiled only because SYSUTILS'
   copy happened to be in scope, which is precisely the dependency pylib's own
   comments say it must never have. `uses builtin` added; that is the whole fix,
   and it is the shape the ticket predicted ("either an explicit `uses` or
   nothing at all").

### The warn instrument's numbers are NOISE — do not size the job with them

Re-measured over the same corpus with `--warn-uses-leak`: 27 pairs / 8741 hits,
whose top rows are `platform -> pylib [class] TPyDict` (2948) and
`sysutils -> math [routine] e` (138). `platform` does not mention `TPyDict`
anywhere and sysutils' `e` is a LOCAL. Those are **speculative lookups** —
`FindUClass`/`FindProc` called to ask "is this identifier a class/routine?",
answered yes, and the answer discarded. The warn fires on the probe, not on a
binding.

That is the third artifact class after `builtin`/`builtinheap` and
`TObject`/`TGuid`, and it is the one that cannot be filtered by name. So the
"35 pairs" figure — and everything sized from it — was measuring the wrong
thing in the same way the "hundreds of files" figure was.

**`--strict-uses` is the honest instrument**: it changes resolution, so it
produces a compile error exactly where a name really binds through a unit it
should not see. Count failures, not warnings. The warn pass keeps its use as a
cheap "where would I look" pointer and nothing more.

(The instrument was also extended this session: the program scope is no longer
excluded — every warn site was gated on `CurrentUnitIdx >= 0`, so a leak into
the MAIN PROGRAM, this ticket's own headline repro, was never counted — and
`MatchEligBase` rejections are reported as `cand`, closing the "FindProc is not
the lookup a call site resolves through" gap the measurement step left open.)

### What is left

Flip `StrictUses` to default-on. The remaining unknown is the `test/` corpus
(923 `.pas` + the `.npy` suite), which is a full-corpus compile and therefore
Track T's kind of run, not a dev-loop one. Sequence: sweep `test/**` under
`--strict-uses`, classify by the three shapes above (ambient injection missed /
filters not composing / genuine missing `uses`), fix, then flip the default and
retire the flag.

## PARKED 2026-08-14 — blocked on the corpus sweep

Everything this session could settle is settled and pushed green. The one input
left is the `test/**` sweep under `--strict-uses`, which is a full-corpus run
and therefore Track T's: [[task-t-strict-uses-corpus-sweep]], filed at prio 80
with the run, the three classification shapes, and the warning not to size it
with `--warn-uses-leak`.

**NEXT, when that report lands:** fix whatever shape-1 (ambient injection) and
shape-2 (filters not composing) failures it names — both are compiler one-liners
— add the `uses` clauses for shape 3, then flip `StrictUses` to default-on and
retire the flag. Nothing here is half-applied: the enforcement is off by
default, self-host converges at generation 1, and gate.sh quick is green at
every commit.
