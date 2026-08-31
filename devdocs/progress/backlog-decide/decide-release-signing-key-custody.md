---
track: U
prio: 25
type: decide
blocked-by: []
keep-open: "the private-key custody half is human-only and an agent must not originate a credential; the agent-work half is decided and re-filed, so nothing important waits"
status: backlog
owner: ""
summary: "feature-release-checksums-repro sits at the head of Track A's queue and cannot be finished by an agent: signing a release needs a PRIVATE KEY the user generates and holds, and a public key committed to the repo. Which tool (minisign vs GPG vs sigstore), who holds the secret, and where the public half is published are all human calls. The checksum and reproducible-build halves are agent-work and are listed below as what to do once this is answered."
---

# Who holds the release signing key, and which tool?

Filed 2026-08-24 while working Track A's queue.
[[feature-release-checksums-repro]] ranks first among the ready Track A tickets
and stops dead at its own step 2. Everything else in it is ordinary work; this
is the part no agent should decide or execute.

## Why it is a decision and not a task

Signing needs a secret. An agent must not generate a release signing key, must
not hold one, and must not put one in a repo or a CI secret on its own
initiative — that is the user's custody call, and getting it wrong is exactly
the supply-chain failure the ticket exists to prevent.

## What already exists (so the answer is cheaper than the ticket reads)

`tools/release.sh` and `.github/workflows/release.yml` already do most of step 1
and step 3:

- `MANIFEST.sha256` — SHA-256 of every prebuilt binary, attached to the GitHub
  Release as a separate asset.
- `selfcheck.sh` — rebuilds each binary on the downloader's own host and diffs
  against that manifest. The reproducible-build claim is already MACHINERY, not
  just copy.
- The release job is manual-dispatch only and refuses to publish unless the gate
  and the reproduction both pass.

What is missing on the agent side is small: a `SHA256SUMS` covering the
published TARBALL itself (today a downloader can only verify the binaries after
extracting), and the verify-it-yourself prose. Neither needs a key.

## The fork

1. **minisign** — one line to sign, one line to verify, printable public key
   that fits in a README. No web of trust, no keyring, no expiry management.
2. **GPG** — familiar to distro packagers, works with existing keyservers, and
   is what some downstreams will expect. Much more ceremony, and key hygiene is
   the usual failure point.
3. **sigstore / cosign keyless** — no long-lived secret to hold at all; identity
   comes from the CI's OIDC token. Removes the custody question entirely, at the
   cost of depending on a third-party transparency log and being unfamiliar to
   anyone verifying by hand.
4. **Checksums only, no signature, for now** — publish `SHA256SUMS` in the
   public repo and lean on the reproducible build as the real defense. Weakest
   against a compromised release pipeline, strongest against doing nothing.

## Recommendation

**minisign (1), with option 4 shipping first** as its own step: the checksum and
reproducible-build halves are agent-work, carry no secret, and deliver most of
the anti-impersonation value the ticket argues for — a clone site cannot make
its binary match a hash published in a repo it does not control, and cannot make
it rebuild byte-for-byte at all. Signing then hardens the pipeline rather than
being the thing that blocks the pipeline.

Whoever answers this: the second half of the answer is **where the private key
lives** (a GitHub Actions secret, or offline with releases signed by hand).

## Once answered

Unblock [[feature-release-checksums-repro]] and do, in this order: SHA256SUMS
for the tarball; the reproducible-build doc wired to the existing `selfcheck.sh`;
the signature step; then the download-page copy (Track W/D).

---

# PARTLY DECIDED 2026-08-25 — **option 4 ships now; the custody half is REFUSED and stands open for the owner**

Handled by an agent under the no-human-available rule
(`devdocs/progress/decided/README-agent-decisions.md`). This is the one ticket
of the thirteen cleared that day that an agent **may not** fully answer, so it
is split rather than settled.

## DECIDED — what ships now (agent work, no secret involved)

**Option 4, immediately, as its own step**, exactly as the ticket's own
recommendation frames it. This is a derivation from what already exists rather
than a preference: `tools/release.sh` and `.github/workflows/release.yml`
already produce `MANIFEST.sha256` and `selfcheck.sh`, and the release job
already refuses to publish unless the gate and the reproduction both pass. The
reproducible-build claim is **machinery, not copy**.

So the anti-impersonation value the ticket argues for is mostly already built,
and the gap is small and key-free:

1. a `SHA256SUMS` covering the published **tarball** (today a downloader can
   only verify binaries after extracting);
2. the verify-it-yourself prose, wired to the existing `selfcheck.sh`.

A clone site cannot make its binary match a hash published in a repo it does not
control, and cannot make it rebuild byte-for-byte at all. Signing then *hardens*
a working pipeline instead of *blocking* one — which is the whole reason to
decouple these.

**Tool preselected: minisign.** One line to sign, one to verify, a printable
public key that fits in a README, no keyring or expiry management. GPG's
ceremony is where key hygiene fails, and sigstore trades the custody question
for a dependency on a third-party transparency log plus unfamiliarity to anyone
verifying by hand. This half is a recommendation the owner can overturn at zero
cost, because nothing is built against it yet.

## REFUSED — what an agent must not decide or execute

**Who holds the private key, and where it lives** (a GitHub Actions secret, or
offline with releases signed by hand).

An agent must not generate a release signing key, must not hold one, and must
not place one in a repo or a CI secret on its own initiative. That is not
caution — it is the precise supply-chain failure this ticket exists to prevent,
and no principle in the governing set authorises an agent to originate a
credential. This stays open for the owner and is flagged as such; it is the only
genuinely human-only item in the Track U sweep of 2026-08-25.

**Nothing waits on it.** Steps 1-3 below are unblocked and carry all the
downloadable-integrity value; only step 4 needs the answer.

## Re-filed as work

[[feature-release-checksums-repro]] is **unblocked** and re-prioritised to the
key-free steps, in this order:

1. `SHA256SUMS` for the published tarball — Track A/T tooling, prio 45.
2. Reproducible-build doc wired to the existing `selfcheck.sh` — Track D, prio 40.
3. Download-page copy — Track W/D, prio 35. **Claims discipline applies**: this
   is *output* reproducibility of our own build, so say "rebuilds byte-for-byte
   from source on your host and matches the published manifest". Do not let it
   drift toward any gcc comparison.
4. The minisign signature step — **blocked on the owner**, prio 25. Do not start
   it, and do not generate a key to unblock it.
