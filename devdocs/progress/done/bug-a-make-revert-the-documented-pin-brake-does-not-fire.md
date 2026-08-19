---
track: A
prio: 60
type: bug
blocked-by: []
summary: "`make revert` is documented as the brake for a bad pin, and it cannot revert a pin in this tree — it restores compiler/pascal26 from a per-version `vN` binary and no `vN` binaries are kept, so it fails with 'Binary ... missing'. Found during a live bad-pin incident (v357), when the brake was reached for and did not fire."
status: done
owner: frank2-A
---

# `make revert`, the documented pin brake, does not fire

Filed 2026-08-19 by frank3-etree (Track B) out of the pin v357 incident
([[bug-n-pin-v357-breaks-tk-nilpy-callable-value-of-a-def-with-no-signature-record]]).

## The claim, and what actually happens

`CLAUDE.md` justifies using `stabilize-fast` rather than full `stabilize` partly
on the grounds that a bad pin is cheap to undo:

> `stabilize`'s ~25 minutes buys breadth that is cheap to undo (`make revert`
> moves `pinned` back)

`make revert` restores `compiler/pascal26` from a **per-version `vN` binary**.
This tree keeps none — the stable directory moved to a fixed-name overwrite
scheme (`929fa707c chore(stable): fixed-name overwrite scheme — kill vN churn +
dangling-symlink trap`). So the command fails with `Binary ... missing` and the
pin is not moved.

**What actually works: revert the pin COMMIT.** Every file under
`stable_linux_amd64/**` is tracked, so reverting the commit restores the previous
pin byte-for-byte, `VERSION` and `pin.log` included. That is what was used to
recover from v357 (`5a0e894b3`).

## Why this is worth a ticket rather than a doc tweak

The brake is reached for **only during an incident**, which is the worst moment
to discover it does not work. On 2026-08-19 a bad pin had Track B's gate red;
the documented recovery was recommended, attempted, and did not fire — the
recovery happened anyway because the coordinator knew the commit-revert route,
i.e. it depended on operator knowledge rather than on the documented procedure.

It is also a **silent-divergence** case of the kind
`devdocs/dev/root-cause-over-microfix.md` describes: the fixed-name overwrite
scheme was a good change that quietly invalidated a consumer nobody re-tested,
because the consumer only runs in emergencies. Worth grepping for other things
that assume `vN` binaries exist.

## Options

1. **Make `make revert` do the commit revert** — `git revert` the most recent
   commit touching `stable_linux_amd64/**`, or reset those paths to the previous
   pin. Keeps the documented name working, which is what the docs and the
   `stabilize-fast` rationale both lean on.
2. **Delete the target and fix the docs** to name the commit-revert route.
   Honest, but leaves the emergency path as prose rather than a command.

Recommend (1): the whole value of a brake is that it is one word you remember
under pressure.

## Gate

Track A's. Whatever lands must be **tested by actually reverting a pin**, not by
reading the recipe — that is precisely the failure being fixed.

## Resolved 2026-08-19 (frank2-A) — option 1, and a SECOND defect the filing missed

Option 1 as recommended, with one change of mechanism: `make revert` does not
`git revert` the pin commit, it **restores the tracked paths under
`stable_linux_amd64/default` from the commit that pinned the previous version**.
Same result, byte-for-byte, and it survives a pin commit that carried other files
alongside the stable dir (several do).

**The second defect:** the old target only `cp`-ed a binary onto
`$(COMPILER)` — `compiler/pascal26`, the *build output*, which the very next
`make` overwrites. It never touched `pinned` at all. So even in a tree that still
kept `vN` binaries it would not have done what `CLAUDE.md` says it does ("`make
revert` moves `pinned` back"), and Track B's ground would not have moved. The
missing-binary failure was the loud half of a target that was wrong in two ways.

**The grep the ticket asked for.** One other consumer assumes `vN`:
`revert-managed`, and it is **correct** — `stabilize-managed` (Makefile:9870)
still writes `$(STABLE_MANAGED_DIR)/v$$NV`, and `stable_linux_amd64/managed/`
does contain `v1`. Only the *default* dir moved to the fixed-name scheme, so the
two targets legitimately differ; a comment now says so, because the next reader
will see the asymmetry and want to "fix" it. Nothing else in `Makefile`,
`tools/`, `docs/` or `devdocs/` reads a `vN` path.

### Proven by firing it, not by reading it

In a `git clone --shared` scratch clone (never this checkout's live pin, which
still reads v365 / `92a09970011a`):

| step | result |
| --- | --- |
| `make revert` from v365 | `v365 -> v364`, pinned `f1806251f225` — matches `pin.log`'s own v364 line |
| tree vs the v364 pin commit | `git diff` empty — binary, VERSION, pin.log, `builtin/` all exact |
| commit it, `make revert` again | `v364 -> v363`, then `v363 -> v362`; each restored `pinned` executes |
| `make revert VERSION=363` | jumps straight there |
| dirty stable dir | refused: "has uncommitted changes" |
| `make revert VERSION=99999` | refused, exit 1 |

**Firing it found a bug that reading it would not have.** The first version
selected "the parent of the most recent commit touching the dir". That is right
once — and then the revert commit is itself the most recent commit touching the
dir, so a second `make revert` walked *forward* into the bad pin it had just
undone. In an incident that reads as "revert twice to drop two pins" and
silently re-blesses the thing you are running from. Selection is now by VERSION
value (newest commit whose `VERSION` is lower than the current one), which is
monotonic under repetition; the reason is recorded in the recipe's comment.

### Docs

`devdocs/dev/session-roster.md` carried an explicit "`make revert` does NOT do it
in this tree — use `git revert <the pin commit>`" note; updated. So was
`devdocs/dev/parallel-tracks.md`, which additionally advertised a `make pin
VERSION=N` that does not exist (`pin` takes no argument). `CLAUDE.md`'s claim
that "`make revert` moves `pinned` back" is now true and unchanged.

**Not pinned** — deliberately. This is a Makefile-only change and the pin is the
coordinator's morning call.

## Log
- 2026-08-19 — resolved, commit 0cc6e6cf5.
