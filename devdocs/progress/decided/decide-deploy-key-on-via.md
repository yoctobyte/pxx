---
track: W
prio: 60
type: decide
blocked-by: []
summary: "RESOLVED 2026-08-27 — `via`'s account-level GitHub key is INTENTIONAL and the risk was already calculated by the owner (*\"this is actually good news / all working as intended. security risks all calculated\"*). No credential change needed; the scoped deploy key is unnecessary. Read this before treating that key as a finding — three sessions burned an afternoon routing around a wall that was not there, and the credential is not a discovery. Background: the premise of the original decision was FALSE. `via` has carried an ACCOUNT-level GitHub key since 2026-06-22 with read (and by ownership, write) reach into the `pxx` COMPILER repo. So there was never a no-push-key posture, the owner is accepting a risk he already carries in a WIDER form, and adding the scoped key while removing/scoping `~/.ssh/id_ed25519` is a net risk REDUCTION rather than a trade against velocity. Original decision: `via` gets a deploy key with write access scoped to the website repo, accepting a security cost to unstall Track W. Records the bound the decision was made INSIDE — one repo, never the compiler repo, never a PAT — because that bound is the whole difference between the accepted risk and a much larger one, and it is the part that erodes silently."
status: decided
---

# DECIDE: `via` gets a write-capable deploy key, scoped to the website repo

- **Type:** decide (owner call — a risk acceptance, nobody else can make it)
- **Track:** W (website)
- **Status:** DECIDED 2026-08-27
- **Owner:** the user

## RESOLVED 2026-08-27 — the key is INTENTIONAL. Do not re-raise it.

> *"this is actually good news / all working as intended. security risks all
> calculated."* — the owner, on being shown the finding below.

**`via`'s account-level GitHub credential is deliberate, known, and its risk was
already priced by the owner.** It is not a misconfiguration, not a leak, and not
something for an agent to flag, tidy, scope, or remove.

**Outcome:**

| | |
| --- | --- |
| `/home/ian/.ssh/id_ed25519` on `via` | **stays as it is.** Intentional. |
| the scoped deploy key `ianweb` generated | **not needed.** Inert; `rm` it or leave it unenrolled. |
| the 18KB patch-transfer question | **moot** — `via` can already push. Withdraw it. |
| the six uncommitted production files | `ianweb` can commit and push them directly, subject only to its own operator |
| the manual deploy gate | **unchanged.** Pushing was never the gated step; a push *executing* on `via` is. |

**Why this page exists at all — this is the part with future value.** Three
sessions spent an afternoon reasoning carefully from a false premise. `frank2-af`
argued against granting push access, `ianweb` agreed and declined to move a patch
between hosts on principle, the owner decided twice, and the roster and
[[bug-web-production-tree-is-uncommitted-and-is-the-only-copy]] both recorded a
"structurally stalled lane" — all of it routing around a wall that was not there.
Nobody was careless; the credential simply was not visible from any of the places
being reasoned from.

**So: an agent finding an account key on `via` has found a documented, intended
arrangement, not a hazard.** Check this page before escalating it. The cost of
re-discovering it is not a security incident, it is another afternoon.

`ianweb` was right to flag it rather than act on it, and right not to touch
someone else's credential — that judgement holds regardless of the outcome, and
is the reason the correct answer arrived in one round trip rather than after a
removal that broke something invisible from `via`.

## The two lessons worth more than the incident

Both are `ianweb`'s, recorded here because this page is where someone will land.

### 1. Push and deploy are different privileges on different boxes

They only look like one decision when the same agent could do both. **The
credential answers "can this box write to the repo." The gate answers "can a
commit start executing here."** Different questions, different owners.

Today collapsed them twice, in opposite directions:

- First, assuming **no key meant no path home** — which produced the
  patch-transfer workaround, the refusal to move it, and the stalled-lane
  framing, none of which a credential was actually blocking.
- Then, nearly reading **"the key is intentional" as clearance to pull** — which
  would have walked straight through `deploy/DEPLOY-STATUS.md`'s manual gate on
  the strength of an unrelated answer.

`via` could push all along and still should not deploy without a human. Both
halves are true simultaneously and neither implies the other.

### 2. Inherited facts are the ones nobody re-measures

Three sessions reasoned carefully for an afternoon on top of "via has no push
key", and **none of us ran `ssh -T git@github.com`** — one command, from the box
the fact was about, answerable in under a second. Cheapest check available and
the last one anyone did.

The premise arrived as an inherited fact and got **built on rather than tested**,
precisely because it arrived sounding settled. That generalises well past
credentials: this repo already knows "measure, do not reason" for root causes
(`devdocs/dev/debugging-playbook.md`) and *"every wrong root cause in this
repo's history was a plausible story nobody diffed against an oracle"*
(CLAUDE.md). This is the same failure one level up — not a wrong conclusion, a
wrong **premise**, and premises are less examined than conclusions because
nobody remembers deciding them.

**The practical form: when a chain of reasoning rests on a fact you did not
personally measure, price the check before building the workaround.** Here the
check was one command and the workaround was an afternoon.

## The measurement, kept because it is what makes the above checkable

**`via` has carried `/home/ian/.ssh/id_ed25519` since 2026-06-22**, fingerprint
`SHA256:MOUfGKeCqWlsWTp9tAhamOm4lVrfd+hJiSC2mCh2/9A`.

- `ssh -T git@github.com` from `via` answers **`Hi yoctobyte!`** — the bare
  account. A repo-scoped deploy key answers `Hi yoctobyte/pxx-website!`.
- `git ls-remote --heads git@github.com:yoctobyte/pxx.git` **succeeds from
  `via`**, returning `eda9c305f6d9 refs/heads/dev` — `frank2-af`'s own orphaned
  commit from that morning, matched against this checkout, so the read is real
  and current rather than inferred.
- Proven: account authentication and read to the compiler repo. Not tested:
  write, because testing write means writing.

## SUPERSEDED — the correction that reopened this (kept for the reasoning chain)

**`via` has had a write-capable GitHub credential since 2026-06-22.** Not a
deploy key. An **account** key, `/home/ian/.ssh/id_ed25519`, fingerprint
`SHA256:MOUfGKeCqWlsWTp9tAhamOm4lVrfd+hJiSC2mCh2/9A`.

Found by `ianweb` on `via` and **independently corroborated** by `frank2-af`:

- `ssh -T git@github.com` from `via` answers **`Hi yoctobyte!`** — the bare
  account. A repo-scoped deploy key answers `Hi yoctobyte/pxx-website!`. That
  difference is the whole point: a user key carries the account's permissions,
  and yoctobyte owns both repos.
- `git ls-remote --heads git@github.com:yoctobyte/pxx.git` **succeeds from
  `via`** and returns `eda9c305f6d9 refs/heads/dev`. That sha is `frank2-af`'s
  own orphaned commit from this morning, matched against this checkout — so the
  read is real and current, not inferred.
- What is proven: **account-level authentication and read access to the compiler
  repo.** What is not tested: write, because testing write means writing. Write
  follows from it being the owner's own account key, not from a measurement.

### What this does to the day's reasoning

1. **"No push key on `via`" was never true.** Every party argued for a posture
   that did not exist — `ianweb` argued for it, `frank2-af` argued for it, the
   owner decided on it twice. The 18KB-patch workaround, the refusal to move it
   between hosts, the "structurally stalled lane" framing in
   [[bug-web-production-tree-is-uncommitted-and-is-the-only-copy]] and in the
   roster: all of it was routing around a wall that was not there.

2. **The owner is accepting a risk he already carries, in a narrower form than
   he already has.** His bound — *"`pxx-website` only, never the compiler repo"*
   — is exactly right, and is **currently violated by the credential already on
   the box**.

3. **The erosion path recorded below is not a future hazard.** It said the danger
   was "a future session hitting friction on the `pxx` repo and reaching for the
   credential already sitting on the box." That credential is sitting on the box
   and has been for two months. Anything running as `ian` on `via` — including
   an RCE in any of the four gunicorn apps behind the public tunnel — can reach
   the self-hosting compiler's repo today.

### The recommendation now runs the OTHER WAY

Adding the scoped deploy key is **not** a risk increase traded against velocity.
Paired with removing or scoping `~/.ssh/id_ed25519` on `via`, it is a strict
**reduction**, and it lands the box on the bound the owner articulated instead
of leaving it wider than anyone believed. Same three steps, plus a fourth that
is the actual security win:

4. **Remove or scope `/home/ian/.ssh/id_ed25519` on `via`** once the deploy key
   is enrolled and proven, so account-level reach into `pxx` goes away.

`ianweb` has generated the scoped keypair — inert until enrolled, `rm`-able if
the owner re-decides, private half has not left `via`. It has deliberately **not
touched `id_ed25519`**: that is the owner's credential, may be load-bearing for
something invisible from `via`, and removing it is his call with full facts
rather than a tidy-up. Flagging, not acting — the correct line.

### Status: re-decided above. The owner's answer was that no change is needed.

## ORIGINAL DECISION (made on the false premise above)

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
