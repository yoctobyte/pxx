---
slug: bug-t-a-cascade-ticket-concludes-harness-event-with-no-evidence
track: T
type: bug
prio: 40
status: done
blocked-by: []
summary: "file_cascade_ticket's Root-cause-suspects line falls back to 'likely a broken build or harness event' whenever no CASCADE_ROOT_JOBS entry is in the red set. That is a conclusion drawn from the absence of one narrow signal, printed with no hedge, and it is now directly contradicted by the Range section shipped in 8ec77190c — which on the live incident named the actual cause. Same defect class the Range work fixed for the sha: an auto-filed ticket asserting something it has no evidence for."
owner: pxx-a5
---

# A cascade ticket concludes "harness event" with no evidence for it

## The finding

`file_cascade_ticket` renders a **Root-cause suspects** line:

```python
", ".join("`%s`" % r for r in roots) if roots
else "none of the known root jobs — likely a broken build or harness event"
```

`roots` is `new_red` filtered against `CASCADE_ROOT_JOBS` — a short curated list
of jobs known to take many others down with them. So the fallback fires whenever
none of *those specific jobs* is red, and it converts that single narrow
absence into a positive claim about the cause.

**The first clause is true and useful.** "None of the known root jobs" is a fact
about the red set. **The second clause is invented.** Nothing in the filing path
looked at the build, the harness, the box, or the range before writing "likely a
broken build or harness event".

## Why it matters more now than it did yesterday

`8ec77190c` added a Range section that lists the commits in the range touching a
buildable file. On the live incident (`regression-cascade-4e27dc2be114`) the two
sections sit adjacent and disagree:

- Root-cause suspects: *"none of the known root jobs — likely a broken build or
  harness event"*
- Range: three buildable commits, one of them
  `e1109d7bcbf9 feat(A,N): a bare NilPy import resolves to Python, not a Pascal unit`
  — which **was** the cause.

A reader who trusts the first line stops looking. That is worse than the state
before the Range section existed, because the ticket now contains its own
refutation and gives no reason to prefer one half over the other.

This is the same defect class the Range work fixed one section lower: an
auto-filed ticket stating a confident conclusion it has no evidence for. Face 1
publishes **signal, not judgment** (`twatch.py` header: *"No AI, no judgment:
signal only"*), and this line is judgment.

## Shape

Say what was checked and stop:

> **Root-cause suspects in the red set:** none of the known root jobs
> (`CASCADE_ROOT_JOBS`). That is the only heuristic applied here — it does not
> imply a harness event; see the Range section for commits worth checking.

If a positive claim about a harness event is wanted, it has to be earned from
something the run actually observed — a build failure, a reseed, an infra
marker, `st["infra"]` — not from the absence of an entry in a curated list.

## Gate

`tools/twatch_cascade_range_devtest.py` extended with a case asserting the
suspects line makes no causal claim when `roots` is empty; `make tools-devtest`.

*Filed by Track T (plexus-T) 2026-08-19, after shipping the Range fix next to
it and declining to grow that ticket.*

---

## 2026-08-29 — fixed, exactly as the ticket's Shape section specified

`cascade_suspects_line(roots)`, extracted so the sentence an auto-filer emits is
a testable object rather than an expression buried in a format string. The empty
case now reads:

> **Root-cause suspects in the red set:** none of the known root jobs
> (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied
> here — it does not imply a harness event, and nothing in this filing looked at
> the build, the box or the range. See the Range section below for commits worth
> checking.

Fact kept, conclusion removed, and the reader is pointed at the section that
does have evidence.

**One deliberate addition beyond the ticket's wording: the known root jobs are
spelled out.** The ticket's draft said "the known root jobs (`CASCADE_ROOT_JOBS`)",
and a reader of the *filed ticket* cannot see that constant — naming a symbol
they cannot resolve is a smaller version of the same defect, telling them a check
happened without telling them what it was.

### Why the empty case could not simply be blanked

Saying nothing would have read as agreement — the same trap the corroboration
line documents one function away ("neither refuted nor confirmed: saying nothing
here would read as agreement"). The absence of a known root job **is** a real
observation and worth printing; only the causal inference drawn from it was
invented.

### Guards

8 checks appended to `tools/twatch_cascade_range_devtest.py`, per this ticket's
own Gate line. They pin the fact, the absence of a hedged guess, that
`harness event` may appear *only* inside the disclaimer, the pointer to the
Range section, that each root job is named literally, and — the direction it
would be easy to overshoot — that the disclaimer is **not** pasted onto the case
that does have suspects.

The `harness event` guard is anchored on the disclaimer rather than banning the
phrase, because the useful sentence is precisely the one that names what this
line does not mean. A guard that banned the words would have forbidden the fix.

Two mutations. Restoring the original literal fired **6 of 8**; pasting the
disclaimer onto the has-suspects case fired **2**.

### Third time today the mutation harness misled, so it is worth stating again

The first attempt at the restore-the-original mutation exited 1 while printing
**zero** FAIL lines — it had mangled the string concatenation rather than
replacing the sentence, so the run crashed. Read carelessly that is "the guards
caught nothing", which is the exact inverse of what happened. Re-applied as a
clean literal replacement, it fired 6.

That is the same failure recorded in `devtest_report.py` and hit twice more
earlier today. **A mutation run means nothing until you have confirmed the
mutation applied** — checking the return code is not enough when a crash and a
detection both exit 1; the tell is an empty or malformed report body.

## Log
- 2026-08-29 — resolved.
- 2026-08-29 — resolved, commit PENDING-COMMIT.
