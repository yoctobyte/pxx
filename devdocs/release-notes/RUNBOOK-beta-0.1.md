# Release day runbook: beta 0.1 "Blaise"

This is the order of work for release day, with the exact commands and what
each should print. It was written on 2026-09-28 by frankD. Each "Expect" line
says where it came from: a run on that day (with the compiler and tree), the
v446 release dry run of 2026-09-27/28, or the script's own source when no run
has printed it yet.

Nothing in steps 1 to 4 tags, publishes or deploys. Step 5 lists what only
the owner can say yes to.

Names used below:

- **vNNN**: the final pin the release is frozen on.
- **SRC**: the pin's *source* commit, the tree its binary was built from. It
  is the last field of the pin's line in `stable_linux_amd64/default/pin.log`.
- **REL**: the commit that will be tagged. It is SRC plus documentation
  commits only.

The order is: freeze, pin, restamp, check the freeze again, dry run on the
release host, walk the tarball, owner's yes.

## 1. The freeze

**Announce it.** The coordinator sends this to every live seat (`ListAgents`),
on the owner's word:

> FREEZE for beta 0.1, on the owner's word. From now until the owner says the
> release is out, nothing under `compiler/` or `lib/` lands on master. Docs
> (`docs/**`, `devdocs/**`) may land. If you think a fix must go in, send it to
> frankuser; do not push it.

**Check it.** Run this after the pin, again before the dry run, and again
right before tagging:

```sh
git fetch -q origin
SRC=$(git show origin/master:stable_linux_amd64/default/pin.log | tail -1 | awk '{print $NF}')
git log --oneline "$SRC"..origin/master -- compiler lib
```

Expect: **no output**. Any commit it prints is in the release tree but not
in the pinned binary's source.

- A commit under `compiler/` makes the release binary differ from the pin, and
  `release.sh --publish` refuses (it compares the two byte for byte). That is
  what happened to the v446 dry run: `50329e2988`, a compiler fix after v446's
  source commit, made it end with `NOT A PIN (release e5dbc12b1a99 vs pin v446
  ae3466a018d8)`.
- A commit under `lib/` does not change the binary, but `lib/` is read when a
  program is compiled, so the release would ship code no pin was measured
  with.

Either way the fix is the owner's call: revert the commit, or cut a new pin.

The check does fire. On 2026-09-28 against v448 (SRC `cfc7c6a65d`) it printed
16 commits, among them `a652418125`, which sits between v448's source commit
and its pin commit `c4244eeaa7`. So a pin commit can already carry a `lib/`
change its binary was not built from; the check above catches that too.

## 2. The final pin (the coordinator does these)

On the development box, in the coordinator's checkout, under the owner's lock:

```sh
PXX_ALLOW_FULL_SUITE=1 make stabilize
make pin
```

`make stabilize` runs the full suite, then prints
`=== stabilize: 4-iteration fixedpoint check ===` and compares two more
generations. `make pin` prints `pinned -> stable_pinned (vNNN, <sha256>).`,
then `froze <n> builtin RTL source(s) -> ...`, then
`pin verify: pinned still builds lib/rtl (uses SysUtils)` (from the Makefile).
**If it prints `PIN VERIFY FAILED`, the pin has already moved: run
`make revert` first**, then diagnose.

Commit with the usual subject, `chore(stable): pin vNNN -- binary sha256
<first 12 hex>`, then pull, rebase and push. Then, from RESTAMP.md step 1:

```sh
tail -1 stable_linux_amd64/default/pin.log      # "... pinned vNNN <sha256> (was ...) <SRC>"
git log -1 --format='%h %s' --grep='chore(stable): pin vNNN --'
```

**Check that the tree rebuilds the pin.** In a clean worktree at REL:

```sh
cp stable_linux_amd64/default/pinned compiler/pascal26 && make
cmp compiler/pascal26 stable_linux_amd64/default/pinned && echo BYTE-IDENTICAL
```

Expect `converged after 1 round(s)` and `BYTE-IDENTICAL`. Measured on
2026-09-28 at v448's pin commit `c4244eeaa7`: both, sha256 `b2b325036c3b` for
both files. This is the same comparison `release.sh` makes, so if it fails
here, the release will say `NOT A PIN`.

Then announce the pin: vNNN, the pin commit, the sha256, SRC.

## 3. Restamp the pages (frankD, once the pin is announced)

`devdocs/release-notes/RESTAMP.md` is the full procedure. In a fresh worktree
at `origin/master`:

```sh
python3 devdocs/release-notes/restamp.py markers
python3 devdocs/release-notes/restamp.py identity --pin vNNN
git diff --stat
python3 devdocs/release-notes/restamp.py check --pin vNNN
```

Rehearsed on 2026-09-28 against v448 at `42eee8e1f6`, in a throwaway worktree
that was then removed:

- `markers: latest pin v448; 0 changed`
- `identity: v448, commit c4244eeaa7, sha256 b2b325036c3b, source cfc7c6a65d`
- `git diff --stat`: 5 files, 10 lines: `AGENTS.md`, `CLAUDE.md`,
  `devdocs/release-notes/v0.1.0-beta.1.md`, `docs/reference/known-issues.md`,
  `docs/release-notes/index.md`.
- `check against v448: 46 items`.

Rehearsed again on 2026-09-28 against v450, after AGENTS.md stopped naming
a pin (so `identity` no longer touches it), in a throwaway worktree that was
then removed: `markers: latest pin v450; 0 changed`; `identity: v450, commit
3503825c2f, sha256 c19cc2d531e4, source 70f62b5544`; `git diff --stat`: 4
files, 9 lines (`CLAUDE.md`, the two release-notes pages,
`docs/reference/known-issues.md`); `check against v450: 58 items`.

**Known false positive in `check`:** `docs/release-notes/index.md:87` is
listed as draft wording, because it says "The table is the same as with the
draft pin v425". That sentence is history, not a draft marker. Leave it.

Work through the rest of the `check` list as RESTAMP.md step 4 says: drop
"(next pin)" lines the pin does not carry, move "Fixed since v441" rows that
the pin carries into "Fixed in this release", and remove the draft banner and
title. Then run the credential check (RESTAMP.md step 5, counts only, both
0), read the whole diff, and commit and push. Run the freeze check from
step 1 again: a restamp touches only docs, so it must still print nothing.

Note for timing: the documentation site pulls its content from GitHub by
itself, on a push webhook and a 5-minute timer
(`~/pxx-website/deploy/README.md`). Once the restamp is pushed, the pages
without the draft banner reach the site on their own, before the tag exists.

## 4. The dry run on the release host

The release host is a spare 24-thread box; cap it with `taskset -c 0-18`
(19 cores, the owner's cap there). The coordinator has the route to it. Its
checkout is `~/pxx`.

```sh
cd ~/pxx
git status --short                               # must print nothing
git pull -q --ff-only origin master
git log --oneline -1                             # must be REL
tail -1 stable_linux_amd64/default/pin.log       # must name vNNN
```

Checked read-only on 2026-09-28: the host has 24 threads and fpc 3.2.2 (the gate
runs `make test-fpc`), `~/pxx` had no local changes, at `149a4354b8`, and its pinned binary was
v448's `b2b325036c3b`. `gh` is not installed there, and `taskset` is. Its load was 18.9 at the
time, so check `uptime` before starting.

**The 19-core cap.** `release.sh` has no core option. It runs `make test`,
`make test-fpc`, `make cross-bootstrap`, `make lib-test` and `make demos` as
plain `make` targets, then builds the tarball and runs the selfcheck.
`--max-cores` belongs to `tools/testmgr.py`, which `release.sh` does not use.
To hold the whole run and all its children to 19 cores, use `taskset`:

```sh
cd ~/pxx
nohup setsid bash -c 'RELEASE_BUMP=preminor:beta RELEASE_CODENAME=Blaise PXX_ALLOW_FULL_SUITE=1 \
  taskset -c 0-18 tools/release.sh; echo "RC $? after $SECONDS s"' \
  > ~/release-vNNN.log 2>&1 &
```

`RELEASE_BUMP=preminor:beta` picks the version without a prompt. With no `v*`
tag on origin (checked on 2026-09-28: only `archive/` and `checkpoint-` tags)
it computes `v0.1.0-beta.1`. Without `--publish` it is a dry run: it creates
no tag and pushes nothing.

**How long.** The v446 dry run took 7,075 s (just under 2 hours) on the
development box, not on the release host, which has not run it yet. A red gate row stops the run: the
first v446 attempt ended at `RC 2` after 2,352 s on a red `test-core` row.
Demo failures listed in `tools/release-xfail.txt` are tolerated; nothing else
is.

**What the end of the log looks like.** From the v446 dry run, which was
timed with `/usr/bin/time` rather than the `RC ... after ... s` line above:

```text
    selfcheck: PASS

================ REHEARSAL COMPLETE ================
 tag:      v0.1.0-beta.1
 codename: Blaise
 dist:     dist/pxx-v0.1.0-beta.1/  (+ tarball, MANIFEST.sha256)
 built at: 5530a7defb  compiler e5dbc12b1a99
 pin:      NOT A PIN (release e5dbc12b1a99 vs pin v446 ae3466a018d8) -- cut a pin on this tree first
 mode:     DRY-RUN — nothing tagged or published.
           re-run with --publish to cut it for real.
TIME 7075.40 s
RC 0
```

On release day the `pin:` line must instead read
`release binary == pin vNNN (<first 12 hex>)`. That wording is from
`release.sh`'s `pin_identity`; no run has printed it yet. `NOT A PIN` means
stop: go back to step 1's check.

`ls -l dist/` after the v446 run:

```text
SHA256SUMS
pxx-v0.1.0-beta.1/
pxx-v0.1.0-beta.1.tar.gz          34,110,880 bytes
selfcheck-v0.1.0-beta.1.log
```

**Walk the tarball as a reader would**, following the README's four lines:

```sh
cd ~/pxx/dist && sha256sum -c SHA256SUMS          # pxx-v0.1.0-beta.1.tar.gz: OK
mkdir -p /tmp/relwalk && cd /tmp/relwalk
tar xzf ~/pxx/dist/pxx-v0.1.0-beta.1.tar.gz && cd pxx-v0.1.0-beta.1
./install.sh --yes                                 # exit 0
./pxx test/hello.pas /tmp/hello && /tmp/hello      # Hello, World!
./selfcheck.sh                                     # ends with "selfcheck: PASS"
```

With the v446 tarball: the checksum was `OK`, `install.sh` exited 0, hello
printed `Hello, World!`, and `selfcheck.sh` took 199 s and printed
`OK  gen1 == gen2`, `OK` for x86_64, i386, aarch64 and arm32 reproducing, and
`selfcheck: PASS`.

## 5. What is left for the owner's yes

None of these has been done, and nobody but the owner starts them.

1. **The tag and the GitHub release.** On the release host, in the same checkout, with
   the same environment: `tools/release.sh --publish`. It refuses unless the
   release binary is the pin and the checkout is clean and in sync with
   origin. It asks three seatbelt questions and for the tag to be typed. It
   then commits `release: v0.1.0-beta.1, codename Blaise` to
   `devdocs/release-notes/CODENAMES`, pushes it, creates the annotated tag and
   pushes it. **Pushing the tag publishes nothing:**
   `.github/workflows/release.yml` has no tag trigger and runs only when it
   is dispatched. `release.sh` dispatches it with `gh`, but `gh` is not
   installed on the release host, so there it prints `gh not found — finish the release
   by hand:` and `Actions -> release -> Run workflow -> tag=v0.1.0-beta.1`.
   That button is the step that publishes: the workflow rebuilds on GitHub's
   runner, runs the gate and the reproduction selfcheck for the tag, and then
   creates the release. (`--local` would publish from the host's `dist/` with
   `gh`, using `devdocs/release-notes/v0.1.0-beta.1.md` as the body, and also
   needs `gh`.) This is read from `release.sh` and `release.yml`; none of it
   has been run.
2. **Codeberg.** No Codeberg remote is configured: on 2026-09-28 the
   development checkout had only `origin`, GitHub, and the release host's
   `origin` is GitHub too. Whether and how
   to mirror is the owner's call.
3. **The website.** Content follows GitHub by itself (step 3). Deploying the
   site's code is separate and manual, on the host, per
   `~/pxx-website/deploy/README.md`: `git pull --ff-only` in the site
   checkout, then `sudo systemctl restart pxxweb`. Owner only.
4. **The announcement.** A draft for the owner to edit exists outside the
   repository; the coordinator has its path. It is not published anywhere.

After the release, lift the freeze with a message to every seat.
