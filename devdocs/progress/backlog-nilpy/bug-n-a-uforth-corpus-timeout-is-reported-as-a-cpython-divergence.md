---
slug: bug-n-a-uforth-corpus-timeout-is-reported-as-a-cpython-divergence
track: N
type: bug
prio: 55
blocked-by: []
summary: "Six `timeout N` literals are hardcoded inside the test-nilpy and test-uforth recipes. The three uforth ones are the damaging pair of shapes: `wait $pp || true` discards timeout's exit 124, the kill truncates p.out mid-stream, and the truncation is then reported as `DIFF <corpus>` — a pxx-versus-CPython divergence — and counted into `bad`. A machine under load thus manufactures a Nil-Python frontend finding. Filed by Track T, which owns the harness but not the Makefile."
---

# A uforth corpus timeout is reported as a pxx-vs-CPython divergence

Filed by **plexus-T** out of
[[bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic]],
which measured the whole class. **T owns the tool, never the bug** — and it does not
own `Makefile` either, so the recipe-side half of that ticket lands here, in the lane
that owns the tests these recipes run.

## The damaging one first

`Makefile:9409-9410` and `:9428-9429` (the uforth corpus and word-set arms) run the two
implementations in parallel and reap them like this:

```make
	( cd "$(UFORTH_SRC)" && timeout 180 "$$wd/uforth" < "$$wd/in.txt" ) > "$$wd/p.out" 2>&1 & pp=$$!; \
	( cd "$(UFORTH_SRC)" && timeout 180 python3 uforth.py < "$$wd/in.txt" ) > "$$wd/c.out" 2>&1 & cp=$$!; \
	wait $$pp || true; wait $$cp || true; \
	if diff -q "$$wd/p.out" "$$wd/c.out" > /dev/null 2>&1; then ok=...; \
	else bad=$$((bad+1)); echo "  DIFF $$f"; ...
```

`wait $$pp || true` throws the exit status away. When the pxx arm is killed at 180s its
`p.out` is **truncated mid-stream**, the `diff` therefore fails, and the recipe prints:

```
  DIFF <corpus>
  @@ -1,2 +1 @@
    a
  -b
```

That is not a signal that was lost. It is a **false signal that was created**, and its
stated subject is Nil-Python: a differential divergence against the CPython oracle,
counted into `bad`, ending in `test-uforth: FAIL — N of M corpora differ from CPython`.
Whoever picks that up chases a frontend bug that is really a busy box.

Measured by T with a scratch recipe of exactly this shape (a producer truncated at 1s
against a complete oracle): the comparison block reports `DIFF f` with the tail missing,
and no part of the output distinguishes it from a real divergence.

**The discriminator that would fix it is one line**: `wait $$pp; prc=$$?` and, when
`prc` is 124, report a TIMEOUT rather than entering the diff at all. A truncated stream
must never be compared — a partial answer is not a wrong answer.

## The other three sites in this lane

`test-nilpy`'s recipe carries three more hardcoded ceilings. These lose a signal rather
than inventing one, so they are the lower half of this ticket:

| line | shape | what make reports |
| --- | --- | --- |
| `Makefile:411` | `timeout 120 xvfb-run -a $$bin \|\| { echo "... EXITED NONZERO under Xvfb"; exit 1; }` | `Error 1` — distinctive log line, but it conflates a timeout with any nonzero exit |
| `Makefile:2423` | `test "$$(timeout 20 ...)" = "..."` | `Error 1` — command substitution discards the status; what fails is `test` |
| `Makefile:2556` | `test "$$(timeout 60 ...)" = "..."` | `Error 1` — same |

`Makefile:411` is the load-sensitive one: a **GUI binary under a virtual X server** on a
**fixed 120s** ceiling, inside a 2700-job tier.

## What Track T has already done, so this ticket is only the recipe half

- The report now carries each job's learned baseline beside its duration (`exp_dur` next
  to `dur`), so an overlong red is at least **legible** without re-running it by hand.
- `testmgr` now retries a failure that ran far longer than its learned duration **while a
  co-tenant run was live** (`Manager._inner_timeout_shaped`), which covers the plain
  `Error 1` shapes above under contention.

Neither reaches this ticket's headline. A false `DIFF` is not a timeout to testmgr under
any reading: the job fails, the log says divergence, and the duration only says the box
was busy — it cannot say *the comparison should not have been made*. **Only the recipe
knows that, because only the recipe saw the 124.**

## Do NOT fix this by raising the constants

Recorded on the parent ticket and repeated here because it is the tempting move: raising
a ceiling trades a false red for a slower suite and still leaves a reader unable to tell
the two kinds of red apart. The defect is structural, not per-constant.

## Gate

Track N's: `test-nilpy` green + self-host byte-identical. `make test-uforth` skips
cleanly when no uforth tree is present, so verify the change with the tree cloned.
