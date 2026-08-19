#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for the resolve -> sync citation loop (progress.sh + sync.sh).

The bug this pins (bug-t-resolve-cites-a-sha-the-rebase-then-rewrites): the
documented loop was

    git commit                       -> abc123
    progress.sh resolve <slug> abc123        # sha written into the ticket
    tools/sync.sh                            # pull --rebase + push -> def456

and sync.sh REBASES. On this fleet the watcher daemon publishes tstate every
few minutes, so origin has almost always moved and the rebase rewrites every
local commit. The sha in the ticket then exists only in the author's local
reflog — the one place the other box cannot look. Four tickets in one session
cited commits nobody could resolve.

The fix under test: `resolve` may omit the sha (writing PENDING-COMMIT), and
sync.sh fills it in AFTER the push, when the sha is final.

Everything happens in a throwaway bare repo + two clones under /tmp; the real
repo is never touched. Run: python3 tools/sync_pending_commit_devtest.py
"""
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

TOOLS = pathlib.Path(__file__).resolve().parent
PLACEHOLDER = "PENDING-COMMIT"
SLUG = "bug-scratch-widget-explodes"
TICKET = """---
summary: "the widget explodes"
type: bug
track: T
prio: 50
---

# The widget explodes

## Log
- 2026-08-03 — filed.
"""


def git(repo, *args, check=True):
    return subprocess.run(
        ["git", "-c", "user.name=devtest", "-c", "user.email=devtest@example",
         "-c", "commit.gpgsign=false", *args],
        cwd=repo, text=True, capture_output=True, check=check)


def build_scratch(tmp):
    """A bare origin, a dev clone carrying the tools, and a second clone that
    plays the watcher daemon pushing between our commit and our push."""
    origin = tmp / "origin.git"
    subprocess.run(["git", "init", "-q", "--bare", "--initial-branch=master",
                    str(origin)], check=True)

    dev = tmp / "dev"
    subprocess.run(["git", "clone", "-q", str(origin), str(dev)], check=True,
                   capture_output=True)
    (dev / "tools").mkdir()
    for name in ("sync.sh", "progress.sh", "progress.py"):
        shutil.copy2(TOOLS / name, dev / "tools" / name)
        (dev / "tools" / name).chmod(0o755)
    prog = dev / "devdocs" / "progress"
    (prog / "backlog").mkdir(parents=True)
    (prog / "done").mkdir(parents=True)
    (prog / f"backlog/{SLUG}.md").write_text(TICKET, encoding="utf-8")
    # BOARD.html is generated AND gitignored in the real repo; mirror that, or
    # the fixture invents a tracked generated file the tooling never has to
    # resolve.
    (dev / ".gitignore").write_text("devdocs/progress/BOARD.html\n", encoding="utf-8")
    # Filler tickets so backlog/ does not consist of the single file we later
    # move: git would read that as a DIRECTORY rename and conflict on where a
    # sister's new ticket belongs — an artefact of a 1-file fixture, not of the
    # tooling. The real backlog carries ~200.
    for i in range(3):
        (prog / f"backlog/bug-filler-{i}.md").write_text(
            TICKET.replace("the widget explodes", f"filler {i}"), encoding="utf-8")
    git(dev, "add", "-A")
    git(dev, "commit", "-qm", "seed")
    git(dev, "push", "-q", "origin", "master")

    daemon = tmp / "daemon"
    subprocess.run(["git", "clone", "-q", str(origin), str(daemon)], check=True,
                   capture_output=True)
    return origin, dev, daemon


def daemon_publishes(daemon, n):
    """What actually forces the rebase in production: tstate landing on master
    between a dev box's commit and its push."""
    git(daemon, "pull", "--rebase", "-q", "origin", "master")
    (daemon / f"tstate-{n}.json").write_text(f'{{"run": {n}}}\n', encoding="utf-8")
    git(daemon, "add", "-A")
    git(daemon, "commit", "-qm", f"tstate: run {n}")
    git(daemon, "push", "-q", "origin", "master")


def resolve_and_sync(dev, daemon, commit_arg):
    """One full loop; returns (pre-push local sha, ticket text on origin)."""
    argv = ["tools/progress.sh", "resolve", SLUG] + ([commit_arg] if commit_arg else [])
    subprocess.run(argv, cwd=dev, check=True, capture_output=True, text=True)
    git(dev, "add", "-A")
    git(dev, "commit", "-qm", f"fix(T): {SLUG}")
    local_sha = git(dev, "rev-parse", "--short=9", "HEAD").stdout.strip()

    daemon_publishes(daemon, 1)          # origin moves -> sync must rebase

    r = subprocess.run(["tools/sync.sh"], cwd=dev, text=True, capture_output=True)
    if r.returncode != 0:
        raise AssertionError(f"sync.sh failed: {r.stdout}{r.stderr}")
    landed = git(dev, "show", f"origin/master:devdocs/progress/done/{SLUG}.md").stdout
    return local_sha, landed


def cited_sha(text):
    m = re.search(r"commit ([0-9a-f]{7,40})", text)
    return m.group(1) if m else None


def on_origin(dev, sha):
    return git(dev, "merge-base", "--is-ancestor", sha, "origin/master",
               check=False).returncode == 0


def case_placeholder_is_filled_with_the_landed_sha(tmp):
    origin, dev, daemon = build_scratch(tmp)
    local_sha, landed = resolve_and_sync(dev, daemon, commit_arg=None)

    assert PLACEHOLDER not in landed, "placeholder survived onto origin"
    sha = cited_sha(landed)
    assert sha, f"no commit citation in the resolved ticket:\n{landed}"
    assert on_origin(dev, sha), f"cited {sha}, which is not on origin/master"
    assert not sha.startswith(local_sha[:7]), (
        f"cited the pre-rebase sha {local_sha} — the rebase should have moved it")
    return f"cited {sha} (pre-rebase was {local_sha})"


def case_explicit_sha_still_honoured(tmp):
    """Back-compat: `resolve <slug> <sha>` keeps writing exactly that sha, so
    a citation to a commit that landed EARLIER is not rewritten."""
    origin, dev, daemon = build_scratch(tmp)
    _, landed = resolve_and_sync(dev, daemon, commit_arg="deadbee")
    assert cited_sha(landed) == "deadbee", f"explicit sha not preserved:\n{landed}"
    return "explicit sha written verbatim"


def case_placeholder_filled_in_any_bucket(tmp):
    """A ticket resolved and filed onward in the same commit (done-followup/,
    for a fix that spawned a follow-up) must still get its sha. The first
    ticket ever resolved through this path did exactly that and the fill,
    scoped to done/ + decided/, walked straight past it."""
    origin, dev, daemon = build_scratch(tmp)
    subprocess.run(["tools/progress.sh", "resolve", SLUG], cwd=dev, check=True,
                   capture_output=True)
    followup = dev / "devdocs/progress/done-followup"
    followup.mkdir(parents=True, exist_ok=True)
    git(dev, "mv", f"devdocs/progress/done/{SLUG}.md",
        f"devdocs/progress/done-followup/{SLUG}.md")
    git(dev, "commit", "-qm", f"fix(T): {SLUG}")
    daemon_publishes(daemon, 1)
    r = subprocess.run(["tools/sync.sh"], cwd=dev, text=True, capture_output=True)
    assert r.returncode == 0, f"sync.sh failed: {r.stdout}{r.stderr}"
    landed = git(dev, "show",
                 f"origin/master:devdocs/progress/done-followup/{SLUG}.md").stdout
    assert PLACEHOLDER not in landed, "placeholder survived in done-followup/"
    sha = cited_sha(landed)
    assert sha and on_origin(dev, sha), f"cited {sha}, not on origin/master"
    return f"done-followup/ ticket cites {sha}"


def case_prose_mention_is_not_rewritten(tmp):
    """The fill must rewrite CITATIONS, not every occurrence of the word. The
    board's own README documents the placeholder by name, and a whole-directory
    fill turned that prose into a sha on 2026-08-03."""
    origin, dev, daemon = build_scratch(tmp)
    doc = dev / "devdocs/progress/README.md"
    doc.write_text("resolve writes PENDING-COMMIT; sync.sh fills it in.\n",
                   encoding="utf-8")
    prose_ticket = dev / f"devdocs/progress/backlog/{SLUG}-notes.md"
    prose_ticket.write_text("# notes\n\nWe should audit PENDING-COMMIT leftovers.\n",
                            encoding="utf-8")
    git(dev, "add", "-A")
    git(dev, "commit", "-qm", "docs: describe the placeholder")
    git(dev, "push", "-q", "origin", "master")

    resolve_and_sync(dev, daemon, commit_arg=None)

    landed_doc = git(dev, "show", "origin/master:devdocs/progress/README.md").stdout
    assert PLACEHOLDER in landed_doc, f"prose in README was rewritten:\n{landed_doc}"
    landed_note = git(dev, "show",
                      f"origin/master:devdocs/progress/backlog/{SLUG}-notes.md").stdout
    assert PLACEHOLDER in landed_note, f"prose in a ticket was rewritten:\n{landed_note}"
    return "prose mentions left alone"


def case_generated_boards_autoresolve(tmp):
    """Two agents both touching tickets conflict on the GENERATED boards every
    time, and the resolution is always the same: discard both sides, regenerate.
    sync.sh knew only BOARD.md, so the day board-md started emitting
    BOARD-brief.md and BOARD-done.md it began handing that mechanical conflict
    back to a human mid-rebase."""
    origin, dev, daemon = build_scratch(tmp)

    # the sister agent files a ticket and regenerates the boards
    (daemon / "devdocs/progress/backlog/bug-sister-ticket.md").write_text(
        TICKET.replace("the widget explodes", "the sister ticket"), encoding="utf-8")
    subprocess.run(["tools/progress.sh", "board-md"], cwd=daemon, check=True,
                   capture_output=True)
    git(daemon, "add", "-A")
    git(daemon, "commit", "-qm", "docs(tickets): sister ticket")
    git(daemon, "push", "-q", "origin", "master")

    # ...while we resolve ours and regenerate them too -> both sides differ
    subprocess.run(["tools/progress.sh", "resolve", SLUG], cwd=dev, check=True,
                   capture_output=True)
    subprocess.run(["tools/progress.sh", "board-md"], cwd=dev, check=True,
                   capture_output=True)
    git(dev, "add", "-A")
    git(dev, "commit", "-qm", f"fix(T): {SLUG}")

    r = subprocess.run(["tools/sync.sh"], cwd=dev, text=True, capture_output=True)
    assert r.returncode == 0, f"sync.sh could not resolve the boards: {r.stdout}{r.stderr}"
    boards = git(dev, "ls-tree", "--name-only", "origin/master",
                 "devdocs/progress/").stdout.split()
    generated = [b for b in boards if "BOARD" in b]
    assert generated, "test setup: no generated board files at all"
    for b in generated:
        text = git(dev, "show", f"origin/master:{b}").stdout
        assert "<<<<<<<" not in text, f"{b} landed with conflict markers"
    # both agents' work survived the regeneration
    brief = "".join(git(dev, "show", f"origin/master:{b}").stdout for b in generated)
    assert "sister ticket" in brief, "the sister's ticket was lost in the resolve"
    return f"{len(generated)} generated board(s) auto-resolved"


def case_check_flags_a_dead_citation(tmp):
    """The audit that caught this by hand, made cheap."""
    origin, dev, daemon = build_scratch(tmp)
    resolve_and_sync(dev, daemon, commit_arg="deadbee")
    out = subprocess.run(["tools/progress.sh", "check", "--strict"], cwd=dev,
                         text=True, capture_output=True).stdout
    assert "WARN-DEAD-COMMIT" in out, f"check missed the dead citation:\n{out}"
    assert SLUG in out, f"check did not name the ticket:\n{out}"
    return "check --strict reports WARN-DEAD-COMMIT"


def _pending(dev):
    r = subprocess.run(["tools/progress.sh", "pending"], cwd=dev,
                       capture_output=True, text=True)
    return [l for l in r.stdout.splitlines() if l.strip()]


def case_frontmatter_spelling_is_filled(tmp):
    """The spelling that was NEVER filled.

    `resolve` writes the Log form (`commit PENDING-COMMIT`); workers hand-write
    the frontmatter form (`commit: PENDING-COMMIT`). sync grepped only the Log
    form, and every worker-written instance has the colon — so the fill was
    effectively dead code while `check`, testing by bare substring, counted both
    and reported a number that could never go down.
    """
    origin, dev, daemon = build_scratch(tmp)
    t = dev / "devdocs/progress/backlog" / f"{SLUG}.md"
    t.write_text(t.read_text().replace("---\n\n# The widget",
                                       "commit: PENDING-COMMIT\n---\n\n# The widget"))
    git(dev, "add", "-A")
    git(dev, "commit", "-qm", "worker writes the frontmatter placeholder by hand")
    _, landed = resolve_and_sync(dev, daemon, commit_arg=None)
    assert PLACEHOLDER not in landed, (
        "the frontmatter spelling survived onto origin:\n" + landed)
    m = re.search(r"^commit: ([0-9a-f]{7,40})", landed, re.M)
    assert m, f"frontmatter field not filled:\n{landed}"
    assert on_origin(dev, m.group(1)), f"cited {m.group(1)}, not on origin"
    return f"frontmatter field cites {m.group(1)}"


def case_check_and_sync_agree(tmp):
    """The property that was never true: the number `check` prints and the work
    `sync` can do are the same set. They were a Python substring test and a
    shell grep literal, and nobody had put them side by side."""
    origin, dev, daemon = build_scratch(tmp)
    subprocess.run(["tools/progress.sh", "resolve", SLUG], cwd=dev, check=True,
                   capture_output=True)
    git(dev, "add", "-A"); git(dev, "commit", "-qm", f"fix(T): {SLUG}")
    r = subprocess.run(["tools/progress.sh", "check"], cwd=dev,
                       capture_output=True, text=True)
    m = re.search(r"PENDING-COMMIT: (\d+) resolved", r.stdout + r.stderr)
    counted = int(m.group(1)) if m else 0
    listed = len(_pending(dev))
    assert counted == listed == 1, (
        f"check counted {counted}, pending listed {listed} — they must be one set")
    return "check counts exactly what sync can fill (1 == 1)"


def case_open_bucket_placeholder_is_not_owed_a_sha(tmp):
    """A placeholder in backlog/ or working/ is NORMAL — the ticket has not
    landed and there is no commit to cite. Filling it would invent a citation
    for work that has not happened."""
    origin, dev, daemon = build_scratch(tmp)
    t = dev / "devdocs/progress/backlog" / f"{SLUG}.md"
    t.write_text(t.read_text().replace("---\n\n# The widget",
                                       "commit: PENDING-COMMIT\n---\n\n# The widget"))
    git(dev, "add", "-A"); git(dev, "commit", "-qm", "still open, placeholder present")
    assert _pending(dev) == [], "an unresolved ticket was reported as owing a sha"
    r = subprocess.run(["tools/progress.sh", "check"], cwd=dev,
                       capture_output=True, text=True)
    assert "PENDING-COMMIT:" not in (r.stdout + r.stderr), \
        "check counted a placeholder in an OPEN bucket"
    return "an open ticket's placeholder is left alone by both tools"


def case_refill_cites_the_resolve_not_the_previous_fill(tmp):
    """The -S trap. sync used `git log -1 -S PENDING-COMMIT`, which finds where
    the occurrence COUNT CHANGED — in either direction. On any ticket a previous
    sync already filled, that is the FILL commit, so the ticket would cite the
    tool that wrote the citation. Measured on the live repo: 3 of 4 sampled
    tickets resolved to `docs(progress): record the shas the resolves landed as`.
    """
    origin, dev, daemon = build_scratch(tmp)
    _, landed = resolve_and_sync(dev, daemon, commit_arg=None)
    resolve_sha = cited_sha(landed)
    t = dev / "devdocs/progress/done" / f"{SLUG}.md"
    git(dev, "pull", "-q", "--rebase")
    t.write_text(t.read_text() + "\n- 2026-08-19 — reopened, commit PENDING-COMMIT.\n")
    git(dev, "add", "-A"); git(dev, "commit", "-qm", "docs: a second citation")
    daemon_publishes(daemon, 2)   # a DIFFERENT publish: run 1 already landed
    r = subprocess.run(["tools/sync.sh"], cwd=dev, text=True, capture_output=True)
    assert r.returncode == 0, f"sync.sh failed: {r.stdout}{r.stderr}"
    again = git(dev, "show", f"origin/master:devdocs/progress/done/{SLUG}.md").stdout
    assert PLACEHOLDER not in again, "second placeholder not filled"
    shas = set(re.findall(r"commit ([0-9a-f]{7,40})", again))
    assert shas == {resolve_sha}, (
        f"expected both citations to name the resolve {resolve_sha}, got {shas}")
    return f"a refill still cites the resolve ({resolve_sha}), not the fill commit"


CASES = [
    case_placeholder_is_filled_with_the_landed_sha,
    case_explicit_sha_still_honoured,
    case_placeholder_filled_in_any_bucket,
    case_prose_mention_is_not_rewritten,
    case_generated_boards_autoresolve,
    case_check_flags_a_dead_citation,
    case_frontmatter_spelling_is_filled,
    case_check_and_sync_agree,
    case_open_bucket_placeholder_is_not_owed_a_sha,
    case_refill_cites_the_resolve_not_the_previous_fill,
]


def main():
    rc = 0
    for case in CASES:
        name = case.__name__.removeprefix("case_").replace("_", "-")
        with tempfile.TemporaryDirectory(prefix="sync-devtest-") as td:
            try:
                note = case(pathlib.Path(td))
            except AssertionError as e:
                print(f"  FAIL {name}: {e}")
                rc = 1
            else:
                print(f"  ok   {name} — {note}")
    print("resolve/sync citation loop OK" if rc == 0
          else "resolve/sync citation loop BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
