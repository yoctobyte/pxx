---
track: W
prio: 60
type: decide
blocked-by: []
summary: "DECIDED 2026-08-27 by the owner: `via` gets a GitHub deploy key with write access, scoped to the website repo, accepting the security cost to unstall Track W. Records the bound the decision was made INSIDE — one repo, never the compiler repo, never a PAT — because that bound is the whole difference between the accepted risk and a much larger one, and it is the part that erodes silently."
status: decided
---

# DECIDE: `via` gets a write-capable deploy key, scoped to the website repo

- **Type:** decide (owner call — a risk acceptance, nobody else can make it)
- **Track:** W (website)
- **Status:** DECIDED 2026-08-27
- **Owner:** the user

## DECIDED — grant it, and the reasoning is the owner's

> *"i think via needs deploy keys. yes, security risk. but, limited issue — no
> private data, easy recoverable. for now we care fast(er) development."*

Earlier the same day the owner had agreed **not** to grant push access, on the
argument below. The reversal is deliberate and informed, not a lapse: the cost
of the no-key posture turned out to be a **structurally stalled lane**, not a
manual step, and that changed the trade.

## What the no-key posture actually cost — this is why it flipped

Track W could not be held end to end by any single session:

- `ianweb` holds the lane, sits on `via`, and has the tree — but no push rights.
- The boxes with push rights had no W worker, and lost the one they had when
  `frank2-af` became coordinator.

Consequence: six production files, deployed and serving since 2026-08-20,
**could not be committed home by the only session able to see them**, and the
one workaround left — moving an 18KB patch between hosts over the agent channel
— was itself a judgement call that stacked unanswered with the human. Two
one-line questions, individually low-priority, collectively a dead lane. See
[[bug-web-production-tree-is-uncommitted-and-is-the-only-copy]].

## The argument AGAINST, recorded so the bound below is understood

Not preserved to relitigate — the owner has decided — but because the bound is
only meaningful if the reasoning behind it survives:

`via` terminates a public Cloudflare tunnel, runs four gunicorn apps, and holds
a mirror of a self-hosting compiler's repo. A write credential there means app
RCE becomes repo write. A compiler is the canonical supply-chain target: a
malicious commit to `pxx` reproduces itself past the point where reading the
source catches it.

The owner's counter is specific and correct **for the website repo**: no private
data of consequence, and a bad commit there is trivially revertible. That
counter does **not** transfer to the compiler repo, which is exactly why the
scope below is the load-bearing part of this decision.

## THE BOUND — the decision is only as safe as this stays true

| | |
| --- | --- |
| repo | **`pxx-website` ONLY** |
| **never** | the `pxx` compiler repo — that is the supply-chain target and nothing about "no private data, easy recoverable" applies to it |
| credential type | a per-repo **deploy key**, never a personal access token (a PAT carries the whole account) |
| access | read-write, the minimum that unstalls the lane |
| recommended | branch protection on `main`, so a compromised key can push a branch but not rewrite history |

**How this erodes, since that is the realistic failure:** not by anyone deciding
to widen it, but by a future session hitting friction on the `pxx` repo and
reaching for the credential that already exists on the box. The answer is no,
and the reason is in this ticket rather than in someone's context.

## What this does NOT change

The **manual deploy gate stays** (`deploy/DEPLOY-STATUS.md`: *"Deploys stay
manual on purpose: auto-deploy would let a compromised GitHub account run code
on the host"*). A key that lets `via` **push** is a different thing from
auto-deploy letting a push **execute** on `via`. This decision unblocks the
first; it says nothing about the second, and the gate that caught
`frank2-af` pushing-then-asking-for-a-pull today remains in force.

## Steps

1. **`ianweb`:** generate a keypair on `via` (`ssh-keygen -t ed25519`), print
   the **public** half. It must never send the private half anywhere.
2. **The owner:** add that public key to the `pxx-website` repo's Deploy Keys
   with *Allow write access* checked. Repo settings, not account settings — the
   distinction is the bound above.
3. **`ianweb`:** commit the six files (split: pull hardening / zero-byte guard
   with its resilience test / dashboard badge) and push.
4. That resolves the p70's remaining half and retires the patch-transfer
   question entirely.
