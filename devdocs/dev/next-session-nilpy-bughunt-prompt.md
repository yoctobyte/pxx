> **STALE (2026-08-17).** The ticket this points at
> (`bug-nilpy-nonlocal-capture-in-an-escaping-closure-fails-to-parse`) is DONE.
> Kept as a record of that session, not as a dispatch. For current assignments
> see `devdocs/dev/session-roster.md`; for the queue, `progress.sh next --track N`.

# Next session: Track A+N, bughunting / bugfixing

_Written 2026-08-06 at the end of a long A+N session, as a prompt to self.
A record of where things stand and what worked — **not** a set of standing
instructions. CLAUDE.md wins over anything here, especially about gating._

## Start here

You are **Track A + N** (compiler core + Nil-Python frontend), doing
**bughunting and bugfixing**. Everything is pushed, `working/` is empty, the
gate is green. Nothing is half-applied.

```
git pull --rebase
tools/progress.sh next --track N
```

The top of the N queue is where the last session stopped deliberately:

**`bug-nilpy-nonlocal-capture-in-an-escaping-closure-fails-to-parse` (prio 65)** —
a `nonlocal` write through a closure that outlives its frame **SIGSEGVs**. The
ticket's title says "fails to parse"; that was true when it was filed and is not
any more — it was re-measured 2026-08-06 and the slug deliberately left alone so
existing links keep working. Read the re-measurement section at the bottom, not
the top.

It was left undone on purpose: it needs a heap cell per captured `nonlocal` plus
the body's by-ref parameter repointed at it, which is real work rather than
something to start with 20 minutes left. The ticket already reasoned its way to
that design and the boundary is measured (read-only captures, parameter
captures, the list-cell workaround and same-frame calls all work — only the
by-ref cell through an escaped closure faults).

## What worked, and is worth repeating

Read `~/.claude/projects/-home-rene-frank2/memory/frank2-bughunt-real-algorithms-beat-unit-probes.md`
first — it is the short version. The long version:

1. **Real programs beat unit probes, by a lot.** ~40 focused probes over
   arithmetic, strings, lists, dicts, classes, slicing, closures and exceptions
   came back almost entirely green. Then a **matrix multiply** broke instantly,
   a **tokenizer + recursive-descent parser** found two bugs, and a **record
   aggregation** found a third. Six of those programs are now in
   `tools/pydiff.py probe` (14/14 green) — extend that corpus, don't rebuild it.
2. **After fixing one instance, grep the bug CLASS.** One
   `grep AllocVar(..., tyInteger)` found a second live 32-bit range counter in
   another file. This is the highest-yield minute in the loop.
3. **A/B every find against `stable_linux_amd64/default/pinned`** before
   believing it is yours. It separated "pre-existing" from "I broke it" twice.
4. **`PXXDBG` earns its keep.** `n.caps` named a bogus capture outright;
   `a.ir` showed a store that was never emitted; `n.locals` showed a 32-bit
   binding. Do not theorise about an inferred type — print it.

## Rules that got written down today — read before filing a bug

- **NilPy is UPWARD compatible with CPython** (now in CLAUDE.md's Track N
  entry). *If code works on CPython it must work on NilPy* — one direction only.
  Us accepting what CPython **rejects** is a language feature, not a defect.
  Before filing "we are laxer than CPython", ask whether a program CPython
  *accepts and runs* can observe it. Worked example, both halves, in
  `nilpy-semantics-divergences.md`: a mutable tuple is NOT a bug;
  `isinstance(t, list)` answering True IS.
  I nearly filed a non-bug for want of this rule, and separately recommended
  *refusing* `del x` — which would have rejected valid CPython.
- **`normalise-dont-special-case.md`** (new): when a construct is reachable
  through two shapes, normalise rather than growing a second path. Five of
  today's bugs were "the ticket fixed the path it could see". If you fix one arm
  of a double case, grep for the sibling before closing.
- Set **iteration order** is an explicit NON-divergence — the language specifies
  none and CPython's own is randomised per process. Do not chase it.

## Traps paid for in cash

- **Never run `gate.sh` (or any `make`) while a corpus sweep is in flight** — it
  replaces `compiler/pascal26` mid-run and every remaining program "fails". Cost
  two full re-runs and a moment of believing in 130 regressions.
- You cannot `cp` the compiler elsewhere and run it — units are exe-anchored, so
  a copy dies with *"no unit named builtinheap"*. `pydiff.py --pxx` needs an
  ABSOLUTE path.
- Embedded probe sources in `pydiff.py` must be **raw** strings or the program's
  own `\n` escapes are eaten.
- The per-fix loop is `make compiler/pascal26` + repro + `tools/gate.sh quick` +
  push. **Do not widen it** because a change "touched something shared" — that
  is named in CLAUDE.md as the trap, and today's changes touched every `while`
  loop and every `and`/`or` in NilPy without needing more.

## Open work with usable ground already done

- `bug-nilpy-int-of-a-long-decimal-string-narrows` **and**
  `bug-nilpy-int-of-a-variant-held-bignum-raises` — **one problem, two sides**:
  `int()` cannot express a result wider than Int64. An attempt is written up in
  the first ticket, including why it failed: the frontend types every `int()`
  `tyInt64` and `write` reads its argument's type *before* lowering it, so
  retyping the node during lowering is too late. Fix the type in the frontend
  (three inference sites), then both fall out. `pyint_v` already exists in pylib
  and is never emitted.
- `meta-constant-normalisation` — the umbrella the user asked for. Its first
  item is *one shared "is this constant?" predicate*, since `IsWideIntLit`,
  `InlineArgIsPure` and the container-literal scan each re-derive a private one.
- `bug-nilpy-list-tuple-and-set-are-indistinguishable-to-isinstance` is DONE, but
  it left `decide-nilpy-set-as-a-distinct-type-or-a-list` (Track U) with one live
  question: should `[1] - [2]` raise? The kind tag now makes it answerable.
- `bug-nilpy-for-range-counter-survives-with-the-wrong-value` carries a genuine
  perf fork on the hottest construct in the language — measure before choosing.

## Session shape that worked

Hunt with real programs → measure against CPython and against `pinned` → fix →
`gate.sh quick` → `.npy` test wired into `make test-nilpy` → resolve the ticket
with the measurement in it → push. Push often; unpushed work is work Track T
cannot see.

Fourteen fixes landed this way in one session, every one with a CPython-diffed
regression test.
