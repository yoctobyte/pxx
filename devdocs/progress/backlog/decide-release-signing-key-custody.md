---
track: U
prio: 50
type: decide
blocked-by: []
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
