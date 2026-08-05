# Handoff — bug hunt, night of 2026-08-05 (third night)

**A self-prompt for a fresh context, not a spec.** `CLAUDE.md` remains the
authority on gating. Predecessor: `2026-08-05-track-b-bughunt-night2.md`.

Tree state at handoff: clean, everything pushed, `gate.sh quick` GREEN (incl.
the FPC seed canary), `gate.sh lib` GREEN, `make test` GREEN, self-host
fixedpoint converges in one round. No lane locked — `working/` is empty.

---

## The prompt

> Continuing the bug hunt. Everything is pushed and green; nothing is
> half-landed.
>
> **Recommended track: A + P.** This is my recommendation from the queue data,
> *not* a user ruling — the user asked the question and we did not close it, so
> confirm before assuming.
>
> The case: five of the six remaining urgents are A or P, and B has none. More
> to the point, **A and P are the same file set** — the Pascal frontend was never
> carved out the way C/N/Z were, so it lives in the shared `lexer.inc` /
> `parser.inc`. Three of last night's fixes were slugged `bug-p-` and every one
> of them edited `parser.inc`, which is A's ground. The board already knows this:
> its top A item is literally `bug-p-string-char-relational-compares-lengths`
> **tagged [A]**. "Pure A" and "A+P" describe the same thing; taking P
> explicitly just makes the accounting honest.
>
> Holding A locks out P automatically. So B, C and N are exactly what a
> concurrent agent can hold without touching you — and C's urgent (prio 80) is
> the best thing to hand over, precisely because `clexer`/`cparser` are carved
> out.
>
> **Do not spend time on float formatting or libm rounding.** The user has said
> so three times. Wrong *values* and crashes are in scope; ULP-chasing is not.
> **Benchmarks are also not a priority** (user, 2026-08-05) — the P-state work
> below is filed and can stay filed.
>
> **The loop that works is not the ticket queue — it is the differential
> probes.** They are now indexed in **`devdocs/dev/differential-probes.md`**;
> read that before adding cases. Five of last night's seven fixed bugs came from
> adding case batches to two of them, including two silent-wrong-value bugs in
> the backends. The method: pick an area nobody has covered, write ten cases,
> triage, fix what is yours, file what is not.

---

## What landed (7 bugs + the docs; 4 were silent wrong values)

| | |
| --- | --- |
| `fix(A)` **aarch64 signed-vs-unsigned compare** | `-1 < Byte(1)` was FALSE. That backend decided compare signedness with `TypeDivideUnsigned` — a *division* question — instead of the shared `TypeCompareUnsigned`. Both frontends, every `-O`. |
| `fix(A)` **32-bit virtual calls dropped 64-bit arg halves** | Every 32-bit backend's `IR_VIRTUAL_CALL` pushed one word per arg. Invisible unless the *result* was also 64-bit, which is why the ticket's narrowing table looked so odd. `TMemoryStream.Position` segfaulted on i386. Also fixed by-value `set` through a virtual call (i386 said 1, riscv32 said 0, FPC says 3). |
| `fix(P)` **procedure used as a value** | `n := f.DoIt` assigned stack junk; `f.DoArg(3) + 1` was 4 — the argument read back out of the return register. |
| `fix(P)` **selector on a ctor result dropped** | `TThing.Create(2).n` returned the instance pointer. |
| `fix(P)` **`.Free` off any designator** | `a[0].Free`, `r.f.Free`, `(o as T).Free` did not compile. |
| `fix(B)` **`TCriticalSection` was a no-op stub** | Found *because* of the line above. See "one bug behind another". |
| `fix(B)` **crtl `msync`/`mremap`/`ioctl`**, `InterLocked*`, Format `%n`/`%m`/`*`, `CurrToStr` | Missing or unreachable library surface. crtl unimplemented declarations 7 → 2. |

Also: `devdocs/dev/differential-probes.md` (the probes were undiscoverable — three
of five were referenced only from handoffs and closed tickets, which CLAUDE.md
explicitly says are not instructions).

---

## Best leads, roughly in the order I would take them

| ticket | one line |
| --- | --- |
| `feature-a-unify-32bit-call-argument-marshalling` | **the one I would do first.** Each 32-bit backend writes the by-value argument ladder out once per call KIND; the virtual copy had none, which *was* last night's urgent bug. Fixing the structure stops the next one. |
| `bug-p-string-char-relational-compares-lengths` [A] | urgent, prio 85, top of the queue |
| `bug-a-i386-int64-arg-high-half-uninitialized` | urgent; smells adjacent to the virtual-call fix — check whether it is the same family before assuming it is not |
| `bug-a-static-array-of-managed-whole-assign-loses-data` | urgent, silent data loss |
| `bug-p-program-function-does-not-shadow-used-unit` | urgent |
| `compat-pascal-index-a-function-call-result` | `Copy(s,2,3)[1]` and `Make[1]` do not parse; `b.ArrP(3)[0]` hits IR_UNSUPPORTED. The *loud* half of the family whose silent half I fixed |
| `bug-b-futex-helpers-are-trapped-behind-pxxclone` | would turn `TCriticalSection` from a spinlock into a real blocking mutex — body-only change once split |
| `bug-a-uses-sysutils-silently-no-ops...` | `uses SysUtils` off the search path is a silent no-op; the build blames the program |
| `bug-t-three-network-tests-flake...` | cost ~20 min of A/B work last night to disprove three phantom findings |

---

## Hard-won, would repeat

- **Track T caught a false positive that four local gates missed.** The
  no-result-call check wrongly rejected `GetBox.Poke;`. `gate.sh quick`,
  `gate.sh lib`, 34/34 demos and all 257 probe cases were GREEN with it in
  place; only T's full tier, run against my exact sha, named the file and line.
  That is an argument for pushing **sooner**, not for widening the local gate.
  Read `tools/twatch.py --status` and act on what lands.
- **A `[known]` tag can hide a second, worse bug behind the first.**
  `thread-critical-section` was tagged for a compile failure. Fixing that let it
  run, and it reported 7403 where FPC says 8000 — `TCriticalSection` had been a
  no-op stub the whole time. **When you fix the reason for a tag, untag and
  re-run before assuming the case is green.**
- **Measure the push order, do not derive it.** The i386 64-bit arg pair goes
  `hi` then `lo`. I reasoned my way to the opposite first (that path builds a
  leftmost-DEEPEST frame, so surely the pair mirrors too) and got
  `21474836481` = `5*2^32 + 1`, halves swapped. One build to find out.
- **Check what a variable already means before reusing it.** In arm32's
  `IR_VIRTUAL_CALL`, `j` held the VMT slot. Using it as the new word counter
  made a *no-argument* virtual method dispatch through the wrong slot — the
  working case broke while the target case started passing.
- **`ParseFactor` is not purely an expression path.** `ParseStatementAST` hands
  two statement shapes to the expression parser (`(o as T).M;` and
  `GetBox.Poke;`). Both need `StmtCallDepth` to stand a check down. I found the
  first with a probe and missed the second entirely.
- **A/B baselines lie in two specific ways, both hit in one night.** A baseline
  built from `tail -25` of a 37-line report read as a huge regression; and
  `comm -23` against a run that was killed part-way reports every *unreached*
  test as "fixed". Compare full outputs, or restrict to the range actually
  covered.
- **Long background runs get killed here.** `lib_cross_sweep` died part-way
  three times. Split it (`test/lib_[a-k]*` / `[l-z]*`) rather than restarting
  the whole thing, and keep the halves comparable.
- **A watcher-filed regression outlives its fix unless someone closes it.**
  `regression-test-core-csocket-loopback-b88` sat at the HEAD of Track B's
  ranked queue at prio 70, pointing at work already done, with 58 commits in its
  bisect range. Check the top of your lane's queue against reality before
  claiming it.
- **When a probe case suddenly reports a *value* divergence rather than a
  compile failure, look twice.** That is what `TCriticalSection` and the
  `WaitFor`-signature drift both looked like.

## Untested areas, if you want a fresh case batch

`Currency` beyond arithmetic; variant records; `array of const` past the basics;
class helpers (blocked on the parser — `compat-pascal-class-helpers`); and on
the C side `volatile` / `restrict` / bitfields-in-unions. A virtual method
taking a 5-8 byte by-value record is untested on 32-bit and works only by
coincidence today — see the unify ticket.
