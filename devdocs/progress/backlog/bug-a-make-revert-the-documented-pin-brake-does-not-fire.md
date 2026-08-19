---
track: A
prio: 60
type: bug
blocked-by: []
summary: "`make revert` is documented as the brake for a bad pin, and it cannot revert a pin in this tree — it restores compiler/pascal26 from a per-version `vN` binary and no `vN` binaries are kept, so it fails with 'Binary ... missing'. Found during a live bad-pin incident (v357), when the brake was reached for and did not fire."
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
