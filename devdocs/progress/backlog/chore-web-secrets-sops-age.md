---
prio: 45
blocked-by: [feature-web-track-w-bootstrap]
---

# Website secrets: SOPS + age, encrypted-in-git, paper-backed key

- **Type:** chore (security / ops)
- **Track:** W (website)
- **Status:** backlog — designed 2026-07-12. **Do this BEFORE the first config commit**, not
  after. Retrofitting means rewriting history and rotating everything.
- **Owner:** —
- **Blocked-by:** feature-web-track-w-bootstrap

## The goal, stated honestly
The private repo *is* meant to be a backup (versioned, diffable, replicated — plus other
backups elsewhere; life is long). That's the right instinct. The trap is **plaintext secrets
in git**:

- Git is **append-only forever**. A secret committed once survives its own deletion. A leak is
  not "fix the file" — it is "rewrite history AND rotate every credential", discovered at the
  worst possible moment.
- "Private" is a **runtime** property, not a durable one: repos get flipped public, accounts get
  compromised, collaborators get added, repo backups land somewhere sloppy — and, most
  concretely here, **agents run with push access**. A wrong-remote push must be boring, not
  catastrophic.

## The fix: commit the secrets ENCRYPTED
Keep the git backup, the versioning, the replication — the repo holds **ciphertext**. Then the
backup stops being a secret and you can be generous with copies of it. That is the whole point.

- **SOPS + age** — the pick. Encrypts **values, not whole files**, so `config.yaml` still diffs
  readably (keys/structure in the clear, values as ciphertext). Keeps git's actual benefit
  instead of storing an opaque blob.
- Rejected alternatives: `git-crypt` (transparent, whole-file, simpler, worse diffs);
  `ansible-vault` (fine only if we're already in Ansible).

## Rules (non-negotiable)
1. **The age private key NEVER goes in git** — not even the private repo. It is the one thing
   living outside.
2. **Agents never get the decryption key.** Only the deploy host and the user hold it. An agent
   can edit ciphertext and push; it cannot read a credential. This neuters the wrong-remote-push
   scenario by construction.
3. **`gitleaks` pre-commit hook** on the website repo from commit one — catches the day a real
   key gets written into a plain file at 2am, by human or agent.
4. Mailing-list / forum / user data (PII) is **never** in git at all, encrypted or not. That's a
   DB backup, a different mechanism.

## Key backup: PAPER primary, USB only as convenience
USB flash **loses charge unpowered** (cells drift within a few years), connectors go obsolete,
and it fails **silently** — you find out on the day you need it. Paper in a drawer is readable
in 20 years with no dependencies.

An age key is **one line** (`AGE-SECRET-KEY-1…`, ~74 chars, Bech32) → trivially printable, and
Bech32 carries a **checksum**, so a typo on re-entry fails loudly instead of silently yielding a
wrong key. (For GPG one would need `paperkey` to strip the blob down; age needs nothing. Another
point for age.)

Printing checklist:
- Print the key **and a QR of it** side by side — QR to scan it back in seconds, text as the
  fallback when no scanner works: `qrencode -o key.png "$(cat keys.txt)"`.
- Monospace font. Write the **date** and **what it decrypts** on the page ("website repo SOPS
  key, 2026-07"). Future-you will not remember.
- **Two copies, two physical locations** — paper's failure mode is fire/flood, not decay.
- **Laser, not inkjet** (inkjet fades and runs if it ever gets damp).

## Runbook — agent WALKS THE USER THROUGH THIS STEP BY STEP
The user has explicitly asked to be guided at implementation time; do not just hand over a
script. Confirm each step's output before moving on.

```bash
# 1. install
apt install age gitleaks && curl -L <sops-release> -o /usr/local/bin/sops   # pin a version

# 2. generate the key (ONE line; this is the crown jewel)
age-keygen -o ~/.config/sops/age/keys.txt
#    -> prints the PUBLIC key: age1....   (public key is safe to commit)

# 3. .sops.yaml in the repo root — public key only
#    creation_rules:
#      - path_regex: secrets/.*
#        age: age1....

# 4. write + encrypt
sops -e -i secrets/prod.yaml     # encrypt in place; commit the CIPHERTEXT
sops secrets/prod.yaml           # opens decrypted in $EDITOR, re-encrypts on save

# 5. paper-backup the private key (see checklist above), THEN
#    verify you can restore from the paper copy before trusting it.
```

**Step 5 is the one people skip.** Verify the paper copy actually decrypts (type it back into a
scratch file, decrypt with it) *before* declaring done. An unverified backup is not a backup.

## Acceptance
Website repo: gitleaks hook active; `secrets/**` committed as ciphertext; a `sops -d` round-trip
works on the deploy host; the age key exists on paper in two locations **and has been verified by
a from-paper restore**; the key is in zero git repos.

## Log
- 2026-07-12 — designed with the user. Paper-over-USB was the user's call; correct, and adopted.
