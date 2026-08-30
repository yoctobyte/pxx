#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Fast progress-board helper for devdocs/progress/.

The old shell implementation is kept as tools/progress.sh.reference. This version
keeps the same command surface but parses every ticket once, renders BOARD.md
atomically, and avoids hundreds of grep/sed/awk subprocesses.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import os
import math
import re

_DUP_STOP = {
    "a", "an", "the", "is", "and", "or", "to", "of", "in", "for", "on", "it",
    "that", "not", "be", "are", "so", "its", "has", "have", "with", "by", "as",
    "at", "from", "but", "no", "does", "do", "can", "when", "why", "what",
    "which", "than", "then", "this", "bug", "feature", "chore", "decide",
    "regression", "meta", "idea",
}
import shutil
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict, deque
from dataclasses import dataclass
from pathlib import Path

# Inline-markdown patterns for the BOARD.html render, hoisted out of inline().
# See the note at their use site: same semantics, ~30% off a full render.
_RX_WIKI = re.compile(r"\[\[([A-Za-z0-9_-]+)\]\]")
_RX_CODE = re.compile(r"`([^`]+)`")
_RX_STRONG = re.compile(r"\*\*([^*]+)\*\*")
_RX_EM = re.compile(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])")
_RX_DEL = re.compile(r"~~([^~]+)~~")
_RX_LINK = re.compile(r"\[([^\]]+)\]\((https?://[^)]+)\)")


ROOT = Path(__file__).resolve().parents[1]
PROG = ROOT / "devdocs" / "progress"
STATUSES = [
    "urgent",
    "working",
    "unfinished",
    "blocked",
    "backlog",
    # Everything filed from 2026-08-24 onward (user: "any new tickets filed are
    # fair game, just they go into backlog_new"). RANKED exactly like backlog/ —
    # the split is a FILING convenience, not a parking lot: sorting is by DATE
    # (list the folder) instead of by a judgement call at filing time, because
    # backlog/ had grown to where "gross compiler issue" and "cosmetic nitpick"
    # were indistinguishable and both were called `bug-`. Contrast float/ and
    # experimental/, which are loaded but deliberately NOT ranked.
    "backlog_new",
    "experimental",
    "rainy-day",
    # Track F parks here. Listed so the folder is LOADED (board, check, blocker
    # resolution see it) — NOT so it is ranked: ready/next read only
    # RANKED_STATUSES (urgent/backlog/backlog_new/unfinished), which is the
    # whole point of the lane.
    "float",
    "done-followup",
    "decided",
    "done",
    "rejected",
]

# Statuses whose table is a RECORD of finished work rather than project state.
# BOARD.md carries a count and a pointer for these; the full table is generated
# into BOARD-<status>.md. done/ alone was 190KB of BOARD.md's 260KB — an
# orientation cost every agent paid before it could find anything actionable.
ARCHIVED_STATUSES = ["done"]

# The placeholder `resolve` writes when no sha is given, rewritten by
# tools/sync.sh to the sha the resolve commit LANDED as.
#
# Why a placeholder at all: the documented loop was commit -> resolve <sha> ->
# sync.sh, and sync.sh REBASES. On this fleet the watcher daemon publishes
# tstate every few minutes, so a rebase is the norm — every sha cited before
# the push was rewritten by it and exists only in the author's local reflog
# (bug-t-resolve-cites-a-sha-the-rebase-then-rewrites: four dead citations in
# one session). Deferring the citation to after the push is the only ordering
# that cannot be got wrong by forgetting it.
PENDING_COMMIT = "PENDING-COMMIT"
# THE definition of an unfilled citation, shared with tools/sync.sh via the
# `pending` subcommand. Two spellings are live and both are real citations:
# `resolve` writes the Log form (`commit PENDING-COMMIT`) and workers hand-write
# the frontmatter form (`commit: PENDING-COMMIT`). check used a bare substring
# test and counted both; sync grepped only the Log form and filled neither,
# because every worker-written instance has the colon. The count could therefore
# never go down, and each tool looked correct in isolation
# (bug-t-sync-fills-one-spelling-of-pending-commit-and-check-counts-two).
#
# Anchored rather than a substring so a ticket that DISCUSSES the placeholder in
# prose is not counted as owing one — this file's own ticket does exactly that.
# Anchored to LINE START, which is what distinguishes a citation from prose that
# quotes one. Both live spellings begin their line: the frontmatter field
# (`commit: PENDING-COMMIT`) and the Log entry `resolve` writes
# (`- <date> — resolved, commit PENDING-COMMIT.`). A ticket QUOTING the
# placeholder does so mid-line, inside backticks or a table cell — and this
# bug's own ticket does exactly that, so an unanchored pattern reports the
# ticket about the bug as an instance of the bug.
#
# THIRD SPELLING, 2026-08-29: `resolved: PENDING-COMMIT`. Seven tickets in
# done/ carried it and BOTH tools were blind — check reported nothing and sync
# filled nothing, so the tickets read as fully recorded while citing no commit
# at all. The previous fix taught the two tools to agree with each other; it did
# not stop a third key appearing, because it enumerated key names instead of
# describing the shape.
#
# So match ANY frontmatter key rather than a list of them. The thing that makes
# this a citation is `<key>: PENDING-COMMIT` at line start, not which key it is
# — `normalise-dont-special-case.md`, and the reason a fourth spelling would
# have been invisible too. Still anchored to LINE START, which is what keeps
# prose that QUOTES the placeholder (mid-line, in backticks or a table cell)
# from counting as owing one; this bug's own tickets do exactly that.
# FOURTH SPELLING, same day: a Log line ENDING in the placeholder with no
# `commit` keyword before it — `- 2026-08-29 — resolved with the root-cause
# sibling. PENDING-COMMIT`. Two Track A tickets carried it, invisible to both
# tools. So the Log arm matches a list item whose PENDING-COMMIT is unbackticked
# and at end of line, which is what a citation looks like; a bullet QUOTING the
# placeholder does so inside backticks, mid-sentence, and still does not count.
PENDING_RE = re.compile(
    r"^(?:[A-Za-z_][A-Za-z0-9_-]*:[ \t]+" + PENDING_COMMIT
    + r"|-[ \t][^`\n]*(?<!`)" + PENDING_COMMIT + r"[.\s]*$)", re.M)


def fill_pending(text: str, sha: str) -> str:
    """Replace every unfilled citation in `text` with `sha`.

    THE counterpart of PENDING_RE, and deliberately in the same file. The
    detection side has now grown four spellings; the FILL side lived in
    sync.sh as a pair of sed literals covering two of them. Widening detection
    alone is how `check` reported 17 forever while sync filled nothing
    (bug-t-sync-fills-one-spelling-of-pending-commit-and-check-counts-two) —
    the previous fix gave the two tools one DEFINITION and left them two
    IMPLEMENTATIONS, so the same drift was still available. This is the
    implementation, singular.
    """
    return PENDING_RE.sub(
        lambda m: m.group(0).replace(PENDING_COMMIT, sha), text)
# Buckets where a citation is OWED. A placeholder in backlog/ or working/ is
# normal — the ticket has not landed yet, and there is no commit to cite.
RESOLVED_BUCKETS = ("done", "decided", "done-followup")


def resolve_commit(path: Path) -> str:
    """The sha a resolved ticket should cite: the commit that put it here.

    NOT `git log -S PENDING-COMMIT`, which is what sync.sh used. -S finds
    commits where the occurrence COUNT CHANGED, in either direction, so on any
    file a previous sync already filled it returns the FILL commit — measured
    2026-08-19, it returned `docs(progress): record the shas the resolves landed
    as` for three of four sampled tickets. A citation pointing at the tool that
    wrote the citation is worse than no citation.

    The first commit to touch the ticket AT ITS RESOLVED PATH is the resolve
    itself, and that is a structural fact about the file's history rather than a
    match against its content — which matters, because matching a sha against
    content is the failure already on record as
    bug-t-resolve-cites-a-sha-the-rebase-then-rewrites. Measured on the same
    four: it recovered the actual fix commit every time.
    """
    out = subprocess.run(
        ["git", "log", "--diff-filter=AR", "--format=%h", "--", str(path)],
        cwd=ROOT, capture_output=True, text=True)
    shas = out.stdout.split()
    return shas[-1] if shas else ""
# `resolve` writes "commit <sha>"; hand-written log lines use the same shape.
CITATION_RE = re.compile(r"\bcommits?\s+`?([0-9a-f]{7,40})`?", re.I)
# A citation resolving to a commit with one of these subjects is worth a HUMAN
# look. It is not by itself an error, and the difference matters:
#
#   * a ticket closed as a DUPLICATE, or as already-fixed-elsewhere, has no fix
#     commit — the docs commit IS its resolution, and the citation is correct;
#   * a ticket whose fix and resolve landed as SEPARATE commits, filled by the
#     old `git log -S` path in sync.sh, cites the fill or the resolve instead of
#     the fix. Verified instance: bug-a-virtual-method-int64-in-and-out-32bit
#     cites fd99c8836 (docs) where the fix is 77d32b346, "fix(A): 32-bit virtual
#     calls dropped the high half of a 64-bit argument".
#
# Nothing in the sha distinguishes those two, so this REPORTS and never repairs.
# Matching a citation against `git log` to "correct" it is the operation already
# on record as wrong (~82% of bad citations look fixable that way and are not),
# and a confidently wrong citation is worse than a missing one because it reads
# as authoritative. Strict-only, so it surfaces when someone audits rather than
# on every run.
# Deliberately NARROW: subjects a TOOL wrote, not ones an agent wrote. The first
# draft matched any `tstate(...)` and reported 65, most of them legitimate —
# `tstate(A): close aarch64 large-double formatting` is an agent closing a ticket
# and is a perfectly good citation. The watcher's own publishes follow a rigid
# format (`tstate(<host>): <12-hex> <VERDICT>`, or `opt|slow|bench|pin <sha>`),
# and the sync fill has one exact subject. A ticket citing one of THOSE is
# citing a machine that never fixed anything.
#
# 65 findings, most of them fine, is how a guard gets muted — the failure this
# repo has recorded more than once. Narrow beats complete here.
BOOKKEEPING_SUBJECT = re.compile(
    r"^(?:"
    r"docs\(progress\): record the shas the resolves landed as"
    r"|tstate\([^)]+\):\s+(?:[0-9a-f]{12}\b|(?:opt|slow|bench|pin|full|native)\b)"
    r"|board: regenerate"
    r")", re.I)
SELF_RESOLVE = re.compile(r"^docs\(progress\):\s*resolve\b", re.I)


def ensure_dirs() -> None:
    if not PROG.is_dir():
        raise SystemExit(f"no {PROG}")
    for st in STATUSES:
        (PROG / st).mkdir(parents=True, exist_ok=True)


def slug_from_path(path: Path) -> str:
    return path.stem


def strip_quotes(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        return value[1:-1]
    return value


# An explicit "do not claim me" marker in a ticket body. Deliberately narrow:
# two spellings, both of which an author writes on purpose.
_NODISPATCH_RE = re.compile(r"NOT DISPATCHABLE|do not claim", re.I)

# twatch auto-files a regression stub with a `track:` GUESSED from the test
# source path, and says so -- in the BODY. The ranker, `next`, and the sole-A
# guard all read FRONTMATTER, where a guess is indistinguishable from a
# declaration. That is the exact shape meta-track-w-collision-windows-vs-website
# describes, and it is not theoretical: on 2026-08-29 an ascii-cache regression
# whose defect was in ir_codegen.inc/defs.inc (Track A) carried `track: N`,
# guessed from its `.npy` test. Two agents were dispatched onto it at once and
# the sole-A guard -- which keys off that field -- never fired.
#
# NOT a reason to drop the guess. twatch's own comment records why it exists:
# four stubs needed the same hand edit on 2026-08-16 alone, and "a wrong lane a
# triager can see beats no lane at all". The defect is that the guess is
# invisible to tools, so this makes it visible without changing it.
_GUESSED_TRACK_RE = re.compile(r"Track guessed as \*{0,2}([A-Z+]+)")


def normalize_track(value: str) -> str:
    t = value.upper()
    t = t.replace("TRACK", "")
    # full track names people actually write on Track: lines
    for name, letter in (("PASCAL", "P"), ("RUST", "R"), ("ZIG", "Z"),
                         ("DOCS", "D"), ("TESTING", "T"),
                         ("NILPY", "N"), ("NIL-PYTHON", "N"), ("USER", "U"),
                         ("MSWINDOWS", "M"), ("WINDOWS", "M"),
                         ("WEBSITE", "W")):
        if name in t:
            return letter
    t = re.sub(r"[^ABCDEFMNOPRSTUWZ+/]", "", t)
    t = t.replace("/", "+")
    # strict: only clean single-letter combos survive; anything else (e.g.
    # letter-soup from a prose value) falls through to the Type-line detection
    if not re.fullmatch(r"[ABCDEFMNOPRSTUWZ](\+[ABCDEFMNOPRSTUWZ])*", t):
        return ""
    return t


def _tag_onto(lane: str, tag: str) -> str:
    """Surface a WORK-TAG (O, E, M, S) WITHOUT discarding the FILE-LANE the
    ticket declared.

    These tags are not places code lives. An O ticket edits Track A's shared
    files and obeys A's gate; an E ticket edits Track B's; M is file-owned by
    A/B/T per ticket. CLAUDE.md says so for each of them. Returning the bare
    tag threw the declared lane away, so the ticket vanished from
    `ready --track A` -- the queue the agent that actually owns those files
    reads. Measured 2026-08-29: 14 O tickets invisible to A, 4 E invisible to
    B (whose whole ready queue was 6), 1 M.

    Track F has appended rather than replaced since it was added, and the
    comment on `track` gives the reason in full. This is that same rule for
    the tags that were written earlier and missed it.
    """
    if not lane:
        return tag
    if tag in lane.split("+"):
        return lane
    return f"{lane}+{tag}"


def first_bullet_value(text: str, marker: str) -> str:
    pat = re.compile(
        rf"^\s*-?\s*\*\*{re.escape(marker)}:\*\*\s*(.*)$",
        re.IGNORECASE | re.MULTILINE,
    )
    m = pat.search(text)
    return m.group(1).strip() if m else ""


def parse_frontmatter(text: str) -> tuple[dict[str, str], list[str]]:
    if not text.startswith("---\n"):
        return {}, []
    end = text.find("\n---", 4)
    if end < 0:
        return {}, []
    body = text[4:end].splitlines()
    scalars: dict[str, str] = {}
    blockers: list[str] = []
    in_blockers = False
    for line in body:
        if re.match(r"^blocked-by:\s*\[", line):
            inner = re.sub(r"^blocked-by:\s*\[", "", line)
            inner = re.sub(r"\].*", "", inner)
            blockers.extend(split_slug_list(inner))
            in_blockers = False
            continue
        if re.match(r"^blocked-by:\s*$", line):
            in_blockers = True
            continue
        m = re.match(r"^blocked-by:\s*(.+)$", line)
        if m:
            blockers.extend(split_slug_list(m.group(1)))
            in_blockers = False
            continue
        if in_blockers:
            m = re.match(r"^\s*-\s*(.+)$", line)
            if m:
                blockers.extend(split_slug_list(m.group(1)))
                continue
            in_blockers = False
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if m:
            scalars[m.group(1).lower()] = strip_quotes(m.group(2))
    return scalars, blockers


def split_slug_list(value: str) -> list[str]:
    value = value.replace(",", " ")
    out = []
    for part in value.split():
        part = part.strip("`'\"*[]")
        if part:
            out.append(part)
    return out


@dataclass
class Ticket:
    path: Path
    status: str
    slug: str
    text: str
    fm: dict[str, str]
    fm_blockers: list[str]

    @property
    def type(self) -> str:
        return self.slug.split("-", 1)[0]

    @property
    def summary(self) -> str:
        s = self.fm.get("summary", "")
        if not s:
            m = re.search(r"^#\s+(.+)$", self.text, re.MULTILINE)
            s = m.group(1).strip() if m else ""
        return s.replace("|", r"\|")

    @property
    def not_dispatchable(self) -> bool:
        """True when the ticket says IN ITS OWN TEXT that it must not be claimed.

        Keyed on an explicit human marker, never on `owner:` -- measured
        2026-08-29: 16 of 332 ranked tickets carry an owner and most are RETIRED
        session names (`claude-A`, `agent-AN`, `fable-a-n`) on perfectly
        dispatchable backlog items. Suppressing on `owner` would have hidden ~14
        real tickets to catch one bad dispatch. The marker matches 4 tickets, all
        of which mean it.

        Why it is needed at all: `unfinished/` conflates two states -- "parked,
        re-claim it" and "held right now by another agent's live checkout" --
        and only the second must not be dispatched. `feature-target-wasm` opens
        with "NOT DISPATCHABLE ... Do not claim" and `next` was printing a
        paste-ready claim command for it (found by frankB, 2026-08-29).
        """
        return bool(_NODISPATCH_RE.search(self.text))

    @property
    def is_idea(self) -> bool:
        """A brainstorm PARENT, not a unit of work.

        `next` prints a paste-ready `claim` line, so offering one of these is an
        invitation to scope inflation: `idea-c-realworld-test-targets` [p60] is
        the ranked head of Track C, its own status line says "not scheduled --
        user prefers moving elsewhere next", and its remaining candidates are
        DOOM, micropython and p2c -- each a multi-session campaign. Its concrete
        items already spun out into their own tickets. It presented as the head
        to every agent dispatched onto C (found by frankC, 2026-08-29, which
        skipped it rather than claiming it).

        This is rule 7 in tool form: a ranked queue says a ticket is UNBLOCKED,
        not that it has work left in it, and `ready`/`next` cannot tell those
        apart. Lowering the prio would have been the wrong fix -- the priority
        is honest, it is the TYPE that is wrong for dispatch. So they stay
        ranked and visible in `ready`, annotated, and only `next` declines to
        hand one over. Measured: 5 such tickets across the ranked buckets.
        """
        return (self.slug.startswith("idea-")
                or self.fm.get("type", "").strip().strip('"').lower() == "idea")

    @property
    def guessed_track(self) -> str:
        """The lane letter twatch GUESSED, when that guess is still standing.

        Returns "" when the ticket was not auto-filed, or when a human has
        since corrected it. The discriminator is that the guessed letter is
        written into the note, so it can be compared against frontmatter: if
        they differ, somebody re-laned it on purpose and the note is a stale
        record of how the ticket started, not a live warning. Measured over the
        six live stubs carrying the note -- five still match their guess, and
        the sixth (crtl-reachability-3, retracked C->B by frankC an hour
        earlier) is correctly excluded. Zero false positives.

        Of the five that DO match, at least two are wrong right now:
        regression-fpc-bootstrap-compiler-2 is guessed P and is a Track R
        duplicate forward, and the reactor-exhaustion stub is guessed P from a
        threads test whose subject is the scheduler. So this is not a
        hypothetical annotation -- the guess is wrong roughly as often as it is
        right, which is precisely why it must not read as a declaration.
        """
        m = _GUESSED_TRACK_RE.search(self.text)
        if not m:
            return ""
        guessed = normalize_track(m.group(1))
        return guessed if guessed == self.track else ""

    @property
    def owner(self) -> str:
        o = self.fm.get("owner", "")
        if not o:
            o = first_bullet_value(self.text, "Owner")
        return "" if o == "—" else o

    @property
    def blockers(self) -> list[str]:
        vals: list[str] = []
        bullet = first_bullet_value(self.text, "Blocked-by")
        if bullet:
            vals.extend(split_slug_list(re.sub(r"[`*]", "", bullet)))
        vals.extend(self.fm_blockers)
        return sorted(set(vals))

    @property
    def prio(self) -> int:
        """Human 0-100 priority rating. `prio:` in frontmatter (preferred) or a
        `**Prio:**` bullet as fallback; unset defaults to 50. This is the ONLY
        knob a human sets — dependency propagation derives everything else."""
        v = self.fm.get("prio", "") or first_bullet_value(self.text, "Prio")
        m = re.search(r"\d+", v)
        if m:
            return max(0, min(100, int(m.group())))
        return 50

    @property
    def track(self) -> str:
        """The lane(s) this ticket is surfaced under. File ownership first, then
        the F work-tag if it is parked in float/."""
        base = self._track_base()
        # Track F (floating point) — a work-tag, not a file-lane, so it is
        # APPENDED to the owning lane rather than replacing it: a ticket in
        # float/ declaring `track: B` surfaces as B+F, and --track B and
        # --track F both find it. `track: B+F` written by hand already carries
        # the letter and is left alone.
        #
        # The trigger is MEMBERSHIP OF float/, nothing else. No slug arm and no
        # decl-line arm: F's own charter is "rank the mechanism, never the
        # datatype", and every cheap textual signal for float (a slug with
        # -float-/-ulp-/-round- in it, a "Track F" mention in prose) keys on the
        # datatype. Mis-tagging toward F is how a real bug disappears from the
        # ranked backlog, so where an arm cannot draw that line there is no arm.
        # The folder is a human decision that has already drawn it.
        if self.status == "float" and "F" not in base.split("+"):
            return f"{base}+F" if base else "F"
        return base

    def _track_base(self) -> str:
        # Track R = the Rust frontend. Its tickets declare "Track A (working
        # name: Track R, Rust frontend)" on the Type/Track line so they still
        # obey Track A's file-ownership rules, but the user wants them surfaced
        # as their own track on the board. Detect "Track R" ONLY in the Type /
        # Track declaration lines (never the body) — a real Track A ticket that
        # merely mentions "Track R coordination" in prose must stay A.
        decl = (
            first_bullet_value(self.text, "Type")
            + " "
            + first_bullet_value(self.text, "Track")
        )
        if re.search(r"\bTrack[ -]?R\b", decl, re.I):
            return "R"
        # Track T (testing infra: testmgr/twatch/tstate). feature-track-t-* slugs
        # are real T tickets and always win. But a "Track T" that appears in the
        # decl line as PROSE — "Found by Track T's fuzzer" on a bug the fuzzer
        # filed FOR another track — must NOT override an explicit, contradicting
        # frontmatter `track:` field. That stranded three fuzzer-filed A/P bugs
        # under T on 2026-07-15 (bug-t-progress-track-detection-prose-mention):
        # the decl-line regex can't tell a declaration from a mention, so the
        # authoritative field breaks the tie.
        if self.slug.startswith("feature-track-t-"):
            return "T"
        if re.search(r"\bTrack[ -]?T\b", decl, re.I) and \
                normalize_track(self.fm.get("track", "")) in ("", "T"):
            return "T"
        # Track S (eSpressif / SoC: the ESP32 family — ESP32, S2, S3, C3, and
        # the xtensa/riscv32 backends, ESP PAL, ESP-IDF integration and
        # examples/esp32/**). A cross-cutting work-tag, same decl-line rule as
        # O/E/R/T: each ticket ALSO carries its Track A (compiler internals,
        # e.g. ir_codegen_xtensa.inc) or Track B (lib/rtl/platform/esp, lib/crtl,
        # examples) file-ownership tag for collision rules. This only groups the
        # embedded campaign into one visible lane — ESP work is otherwise spread
        # across A/B/E and reads as unrelated items, which is how it gets
        # neglected. The letter is read as "SoC" as much as "eSpressif", so a
        # future non-Espressif MCU target fits without renaming.
        # NOTE the separator is MANDATORY here, unlike the O/E/R/T rules: with
        # `[ -]?` the pattern also matches the plural "Tracks", which appears in
        # ordinary prose ("Tracks A and B") and mis-tagged two unrelated tickets.
        explicit = normalize_track(self.fm.get("track", ""))
        if not explicit:
            _tl = first_bullet_value(self.text, "Track")
            if _tl:
                explicit = normalize_track(_tl.split()[0])
        if re.search(r"\bTrack[ -]S\b", decl, re.I) or \
                re.match(r"^(feature|bug|regression|idea|compat)-esp-", self.slug) or \
                re.search(r"-(esp|esp32|xtensa)-", self.slug):
            return _tag_onto(explicit, "S")
        # Track M (MSWindows) — the Windows campaign, a work-tag with exactly
        # S's shape: every M ticket ALSO carries its Track A (PE/COFF writer, MS
        # x64 ABI), Track B (lib/pcl win32 widgetset) or Track T (wine harness)
        # file-ownership tag for collision rules, and obeys THAT lane's gate.
        # M and not W: W is the website lane (its own private repo — a genuinely
        # new place code lives, per feature-web-track-w-bootstrap), and Windows
        # is not a place code lives. The two spent months colliding because they
        # declared the letter differently (frontmatter vs prose) and so hid from
        # each other's greps — meta-track-w-collision-windows-vs-website.
        # Separator MANDATORY like S, so the plural "Tracks" in ordinary prose
        # ("Tracks M and A") cannot match.
        # The slug arm needs the same tie-break the T rule needed: an explicit
        # track that CONTRADICTS it wins. Without that,
        # meta-track-w-collision-windows-vs-website — a board-hygiene ticket
        # about the Windows lane, declaring Track A — was auto-tagged M by its
        # own slug. A ticket ABOUT the campaign is not a ticket IN it.
        if re.search(r"\bTrack[ -]M\b", decl, re.I) or \
                (re.search(r"-(windows|win32|wine)-", self.slug)
                 and explicit in ("", "M")):
            return _tag_onto(explicit, "M")
        # Track O (Optimization: register allocation, opt passes, codegen/heap
        # perf) — a cross-cutting lane surfaced on its own, same decl-line rule as
        # R/T. Each ticket ALSO carries a Track A (compiler internals) or Track B
        # (runtime/RTL) file-ownership tag for collision rules; this only groups
        # the optimization work into one visible lane. `feature-opt-` slug prefix
        # is the optimization sub-tickets (NOT `feature-optimization-levels`, the
        # umbrella, whose next char is 'i' not '-').
        if re.search(r"\bTrack[ -]?O\b", decl, re.I) or \
                self.slug.startswith("feature-opt-"):
            return _tag_onto(explicit, "O")
        # Track E (Examples/apps: demos, games, GUIs, IDEs, the portable-userland
        # showcase) — apps BUILT WITH pxx, not pxx itself. Work-tag file-owned by
        # Track B (examples/**, lib/**, app dirs); same decl-line rule as O/R/T,
        # plus feature-demo-/idea-demo- slug convenience.
        if re.search(r"\bTrack[ -]?E\b", decl, re.I) or \
                self.slug.startswith("feature-demo-") or \
                self.slug.startswith("idea-demo-"):
            return _tag_onto(explicit, "E")
        # The whole Rust-frontend effort surfaces as Track R on the board, even
        # though individual sub-tickets carry a Track A (compiler internals) or
        # Track B (rust RTL shims) file-ownership tag for collision-avoidance —
        # that ownership rule still governs WHO edits WHICH files; this only
        # groups the Rust work into one visible lane. `feature-r-frontend-*` is
        # the separate R *language* frontend, not Rust — left to its own track.
        if self.slug.startswith("feature-rust-"):
            return "R"

        t = self.fm.get("track", "")
        if not t:
            line = first_bullet_value(self.text, "Track")
            if line:
                t = line.split()[0]
        t = normalize_track(t)
        if t:
            return t

        line = first_bullet_value(self.text, "Type")
        if re.search(r"\bTrack[ -]?A/B\b|\bTrack[ -]?B/A\b", line, re.I):
            return "A+B"
        if re.search(r"\bTrack[ -]?T\b", line, re.I):
            return "T"
        if re.search(r"\bTrack[ -]?C\b", line, re.I):
            return "C"
        if re.search(r"\bTrack[ -]?D\b", line, re.I):
            return "D"
        if re.search(r"\bTrack[ -]?B\b", line, re.I):
            return "B"
        if re.search(r"\bTrack[ -]?A\b", line, re.I):
            return "A"

        s = self.slug
        if (
            s.startswith("lib-")
            or re.match(r"feature-.*-library$", s)
            or s.startswith("feature-rtl-")
            or s.startswith("feature-terminal-")
            or s.startswith("feature-png-")
            or s.startswith("feature-image-")
            or s.startswith("feature-adventure-")
            or s.startswith("feature-demo-")
            or s.startswith("idea-demo-")
            or s in {
                "feature-platform-abstraction-layer",
                "feature-c-runtime-library",
                "feature-networking",
                "feature-sat-solver-library",
            }
        ):
            return "B"
        if (
            s.startswith("bug-")
            or (s.startswith("feature-") and "compiler" in s)
            or (s.startswith("feature-") and "parser" in s)
            or (s.startswith("feature-") and "syntax" in s)
            or (s.startswith("feature-") and "codegen" in s)
            or (s.startswith("feature-") and "lower" in s)
            or (s.startswith("feature-") and "abi" in s)
            or s.startswith("feature-cross-")
            or s.startswith("feature-target-")
            or "target" in s
            or s.startswith("feature-asm-")
            or re.match(r"feature-.*-asm-", s)
            or s.startswith("feature-elf-")
            or s
            in {
                "feature-empty-class-shorthand",
                "feature-directive",
                "feature-c-source-frontend",
                "feature-array-of-const",
                "feature-explicit-typecasts",
                "feature-class-is-as",
                "feature-int-to-float-assign",
                "feature-managed-exception-cleanup",
                "feature-procedural-types",
                "feature-short-circuit-eval",
                "goal-compile-fpc-compiler",
            }
            or s.startswith("feature-for-")
            or s.startswith("feature-forin-")
            or s.startswith("feature-interface-")
        ):
            return "A"

        if re.search(r"\bTrack[ -]?A/B\b|\bTrack[ -]?B/A\b", self.text, re.I):
            return "A+B"
        if re.search(r"\bTrack[ -]?B\b", self.text, re.I):
            return "B"
        if re.search(r"\bTrack[ -]?A\b", self.text, re.I):
            return "A"

        if s.split("-", 1)[0] in {"lib", "meta", "idea"}:
            return "B"
        return "A"


# --- auto-rating -----------------------------------------------------------
# Deterministic 0-100 suggestion from signals already in the ticket. This only
# SEEDS a static rating; dependency propagation still raises blockers of rated
# goals at query time. Kept transparent (fixed weights, reasons printed) so the
# board stays reproducible — no LLM, no network.

TYPE_BASE = {"bug": 55, "feature": 45, "test": 40, "chore": 30, "docs": 30, "idea": 25}
# prose priority words (in **Priority:** / Type line) pin the base.
PROSE_PRIO = [
    (re.compile(r"\b(critical|highest|urgent|must[- ]fix)\b", re.I), 90),
    (re.compile(r"\b(high|blocker|blocks the entire|major)\b", re.I), 75),
    (re.compile(r"\b(medium|moderate|normal)\b", re.I), 50),
    (re.compile(r"\b(low|minor|nice[- ]to[- ]have|cosmetic|someday)\b", re.I), 28),
]
# correctness/severity keywords → bump (a silent miscompile beats a cosmetic gap).
SEV_STRONG = re.compile(r"\b(miscompile|corrupt|data loss|silently|silent wrong|wrong (value|data|result|answer))\b", re.I)
SEV_MED = re.compile(r"\b(sigsegv|segfault|crash|hang|oom|deadlock|infinite loop|clobber)\b", re.I)


def suggest_prio(t: "Ticket", leverage: int) -> tuple[int, str]:
    reasons: list[str] = []
    decl = first_bullet_value(t.text, "Priority") + " " + first_bullet_value(t.text, "Type")
    score = TYPE_BASE.get(t.type, 45)
    reasons.append(f"type {t.type}={score}")
    for pat, val in PROSE_PRIO:
        if pat.search(decl):
            score = val
            reasons.append(f"prose→{val}")
            break
    body = t.text
    sev = 0
    if SEV_STRONG.search(body):
        sev += 15
        reasons.append("severe(+15)")
    if SEV_MED.search(body):
        sev += 8
        reasons.append("crash/hang(+8)")
    score += min(sev, 20)
    if leverage:
        b = min(leverage * 4, 15)
        score += b
        reasons.append(f"unblocks {leverage}(+{b})")
    score = max(0, min(100, score))
    return score, ", ".join(reasons)


class Board:
    def __init__(self) -> None:
        self.tickets: list[Ticket] = []
        self.by_slug: dict[str, Ticket] = {}
        self.by_status: dict[str, list[Ticket]] = {st: [] for st in STATUSES}
        self.mojibake: list[Path] = []
        self.load()

    def load(self) -> None:
        # errors="replace", NOT strict. One ticket carrying a stray non-UTF-8
        # byte used to raise UnicodeDecodeError out of here and take down
        # `ready`, `next`, `check` and `board-md` for EVERY lane at once -- and
        # the traceback named the codec and a byte offset, never the file, so
        # the blast radius was the whole fleet and the diagnosis was a manual
        # bisect. Measured 2026-08-30: a bug-a-hosted-xtensa ticket pasted the
        # diverging program's RAW OUTPUT into a markdown table, which is exactly
        # the evidence such a ticket should carry.
        #
        # A ticket is prose plus evidence, and evidence arrives as bytes from a
        # failing program -- so this will happen again, and the board must
        # degrade to one damaged cell rather than fail closed. The substitution
        # is not silent: the paths are collected and `check` reports them, so
        # the ticket still gets repaired, it just no longer blocks anyone first.
        for st in STATUSES:
            for path in sorted((PROG / st).glob("*.md")):
                if path.name in {"README.md", "BOARD.md"}:
                    continue
                raw = path.read_bytes()
                try:
                    text = raw.decode("utf-8")
                except UnicodeDecodeError:
                    text = raw.decode("utf-8", errors="replace")
                    self.mojibake.append(path)
                fm, fm_blockers = parse_frontmatter(text)
                t = Ticket(path, st, slug_from_path(path), text, fm, fm_blockers)
                self.tickets.append(t)
                self.by_status[st].append(t)
                self.by_slug[t.slug] = t

    @property
    def done_slugs(self) -> set[str]:
        return {t.slug for t in self.by_status["done"]}

    @property
    def resolved_slugs(self) -> set[str]:
        """Slugs that SATISFY a blocker: work that's done, OR a decision that's
        been made. A `decide-` ticket answered and filed in `decided/` unblocks
        its dependents exactly like a `done/` ticket — a decision is a reference
        later work builds on, not 'work complete', so it lives in decided/ not
        done/, but it counts the same for dependency purposes."""
        return self.done_slugs | {t.slug for t in self.by_status["decided"]}

    def track_matches(self, track: str, filt: str) -> bool:
        return not filt or filt in track

    def effective_prio(self) -> dict[str, int]:
        """Priority propagation: a ticket's effective priority is the max of its
        own `prio` and the effective priority of everything it unblocks (its
        dependents, transitively). So a low-rated blocker inherits the priority
        of the high-value work it gates — you rate the goal, the chain follows.
        Only OPEN dependents pull a blocker up (a done/rejected dependent no
        longer needs it). The graph is a DAG (check() enforces); a stray cycle
        is guarded so this can't recurse forever.

        "float" counts as terminal for PROPAGATION (not as a target): parked
        Track F work must not raise the priority of the active ticket it happens
        to depend on — `idea-cobol-frontend-feasibility-costing` went 20 -> 25 on
        the strength of a parked F bug the moment float/ was loaded. A float
        ticket still INHERITS from its own open dependents, which is the signal
        that something real is waiting on it and it should be un-parked."""
        terminal = {"done", "rejected", "decided", "float"}
        dependents: dict[str, list[str]] = defaultdict(list)
        for t in self.tickets:
            if t.status in terminal:
                continue
            for b in t.blockers:
                if b in self.by_slug:
                    dependents[b].append(t.slug)
        memo: dict[str, int] = {}

        def eff(slug: str, stack: frozenset[str]) -> int:
            if slug in memo:
                return memo[slug]
            best = self.by_slug[slug].prio
            for d in dependents.get(slug, []):
                if d in stack:
                    continue
                best = max(best, eff(d, stack | {slug}))
            memo[slug] = best
            return best

        return {s: eff(s, frozenset()) for s in self.by_slug}

    # Folders the ranked queue pulls from. Everything else in STATUSES is
    # LOADED (board, check, blocker resolution, prio propagation all see it) but
    # never RANKED, and each exclusion is deliberate:
    #   working/       — a LIVE LOCK. An agent is on it right now; ranking it
    #                    would dispatch a second agent onto held files.
    #   blocked/       — has an unmet blocker by definition.
    #   float/         — Track F is low-prio by owner decree and parks there.
    #   experimental/  — X-tagged (R/Z); picked up on request or for fun.
    #   rainy-day/     — ideas, not queued work.
    #   done-followup/, decided/, done/, rejected/ — terminal.
    # unfinished/ IS ranked (added 2026-08-25). Its definition is "parked
    # mid-flight; re-claim, do not duplicate" — that is work in progress, not
    # work abandoned, and BOARD-brief.md already tells agents to re-claim it.
    # Leaving it out hid 23 tickets from every dispatch, including the repo's
    # highest prio (88, an N segfault) and the html5lib ladder at 65.
    RANKED_STATUSES = ("backlog", "backlog_new", "unfinished", "urgent")

    def ready_tickets(self, track_filter: str = "") -> list[Ticket]:
        done = self.resolved_slugs        # done/ OR decided/ satisfies a blocker
        eff = self.effective_prio()
        lev = self.leverage_counts()
        out = []
        for st in self.RANKED_STATUSES:
            for t in self.by_status[st]:
                if self.track_matches(t.track, track_filter) and all(b in done for b in t.blockers):
                    out.append(t)
        # urgent first, then highest effective priority, then most-unblocking,
        # then slug for a stable order. This IS the queue: pull from the top.
        out.sort(key=lambda t: (t.status != "urgent", -eff[t.slug], -lev.get(t.slug, 0), t.slug))
        return out

    def cmd_ready(self, track_filter: str = "") -> str:
        eff = self.effective_prio()
        lev = self.leverage_counts()
        if track_filter:
            lines = [f"== READY (Track {track_filter}; no unmet blocker; ranked — pull from the top) =="]
        else:
            lines = ["== READY (no unmet blocker; ranked — pull from the top) =="]
        for t in self.ready_tickets(track_filter):
            tag = "urgent " if t.status == "urgent" else ""
            unb = lev.get(t.slug, 0)
            extra = f" (unblocks {unb})" if unb else ""
            # unfinished/ ranks, but say so: it is re-claim work, not new work.
            if t.status == "unfinished":
                extra += " [parked — re-claim, do not duplicate]"
            if t.not_dispatchable:
                extra += " [!! DO NOT CLAIM — the ticket says so; read it]"
            if t.is_idea:
                extra += (" [idea — a brainstorm parent, not a unit of work; "
                          "spin out a concrete ticket instead of claiming it]")
            if t.guessed_track:
                extra += (" [track GUESSED from the test path — the defect may "
                          "be in another lane; verify before claiming]")
            lines.append(f"  [{tag}p{eff[t.slug]:>3}] [{t.track}] {t.slug}{extra}")
        return "\n".join(lines) + "\n"

    def cmd_next(self, track_filter: str = "") -> str:
        """The single top-of-queue ticket to grab — the 'do tickets at will'
        entry point. Prints the winner plus why it's on top."""
        rt = self.ready_tickets(track_filter)
        # Drop tickets that declare themselves unclaimable. `next` prints a
        # paste-ready `claim` line, so offering one of these is an invitation;
        # `ready` still lists them (flagged) because seeing them is useful.
        skipped = [t for t in rt if t.not_dispatchable or t.is_idea]
        rt = [t for t in rt if not (t.not_dispatchable or t.is_idea)]
        if not rt:
            scope = f" for Track {track_filter}" if track_filter else ""
            return f"no ready ticket{scope} (all blocked or none in urgent/backlog/unfinished)\n"
        eff = self.effective_prio()
        lev = self.leverage_counts()
        t = rt[0]
        unb = lev.get(t.slug, 0)
        why = f"effective prio {eff[t.slug]}"
        if t.prio != eff[t.slug]:
            why += f" (own {t.prio}, inherited from work it unblocks)"
        if unb:
            why += f"; unblocks {unb} ticket(s)"
        if t.status == "urgent":
            why = "URGENT; " + why
        if t.status == "unfinished":
            why += "; PARKED mid-flight in unfinished/ — re-claim it, do not restart from scratch"
        lines = [
            f"== NEXT{(' (Track ' + track_filter + ')') if track_filter else ''} ==",
            f"  {t.slug}   [{t.track}]",
            f"  {why}",
            f"  {t.path.relative_to(ROOT)}",
            f"  claim: tools/progress.sh claim {t.slug} <your-agent-id>",
        ]
        if skipped:
            lines.append(
                f"  (skipped {len(skipped)} higher-ranked ticket(s) — "
                f"do-not-claim or brainstorm-parent: "
                f"{', '.join(t.slug for t in skipped)})")
        if t.guessed_track:
            lines.append(
                f"  NOTE: this ticket's track was GUESSED from its test source "
                f"path, not declared. The defect may be in another lane — a "
                f"regression's test and its cause are routinely in different "
                f"ones. Verify the lane before you claim it, and re-lane it if "
                f"the guess is wrong.")
        return "\n".join(lines) + "\n"

    def cmd_autorate(self, write: bool = False, track_filter: str = "") -> str:
        """Suggest (or write) a 0-100 prio for open tickets from ticket signals.
        Never touches a ticket a human already rated: writes carry a `# auto`
        tag and only tickets with no prio, or an existing `# auto` prio, are
        (re)written. Dry-run by default — inspect, then pass --write."""
        lev = self.leverage_counts()
        head = "WRITE" if write else "DRY-RUN (pass --write to apply)"
        lines = [f"== AUTORATE ({head}; * = human-set, skipped) =="]
        n_write = 0
        for st in ("urgent", "working", "unfinished", "backlog", "backlog_new"):
            for t in self.by_status[st]:
                if not self.track_matches(t.track, track_filter):
                    continue
                m = re.search(r"(?m)^prio:\s*(\d+)(.*)$", t.text)
                human = bool(m and "auto" not in m.group(2).lower())
                sug, why = suggest_prio(t, lev.get(t.slug, 0))
                if human:
                    lines.append(f"  * [{t.track}] {t.slug}  (human {int(m.group(1))}, keep)")
                    continue
                cur = f"{int(m.group(1))}→" if m else ""
                lines.append(f"    [{t.track}] {t.slug}  {cur}{sug}   ({why})")
                if write:
                    set_prio_auto(t.path, sug)
                    n_write += 1
        if write:
            lines.append(f"-- wrote prio to {n_write} ticket(s). Regenerate: tools/progress.sh board-md")
        return "\n".join(lines) + "\n"

    def leverage_counts(self) -> Counter[str]:
        done = self.done_slugs
        c: Counter[str] = Counter()
        for t in self.tickets:
            # "float" belongs here for the same reason as done/rejected: a
            # parked F ticket is not work anyone is waiting on, so it must not
            # push its blocker up the autorate ranking. Nothing in float/ ranks,
            # and nothing in float/ ranks anything ELSE either.
            if t.status in {"done", "rejected", "decided", "float"}:
                continue
            for b in t.blockers:
                if b not in done:
                    c[b] += 1
        return c

    def cmd_leverage(self) -> str:
        lines = ["== LEVERAGE (how many not-yet-done tickets each slug unblocks) =="]
        for slug, n in sorted(self.leverage_counts().items(), key=lambda kv: (-kv[1], kv[0])):
            lines.append(f"  {n} {slug}")
        return "\n".join(lines) + "\n"

    def cmd_board(self) -> str:
        lines = ["== BOARD (tickets per status) =="]
        for st in STATUSES:
            lines.append(f"  {st:<9} {len(self.by_status[st])}")
        return "\n".join(lines) + "\n"

    def render_board_md(self) -> str:
        lines = [
            "# Progress board",
            "",
            "_Generated by `tools/progress.sh board-md` — regenerate after any board",
            "change; `tools/progress.sh check` fails if this file is stale. History",
            "lives in git, not in a timestamp._",
            "",
        ]
        eff = self.effective_prio()
        for st in STATUSES:
            tickets = self.by_status[st]
            lines.append(f"## {st} ({len(tickets)})")
            lines.append("")
            if st in ARCHIVED_STATUSES:
                # The finished-work archive is not project STATE — it is a
                # record. Enumerating it here made 73% of this file (190KB of
                # 260KB) a list of things nobody can act on, which every agent
                # that reads the board for orientation pays for before touching
                # a byte. Count and pointer only; the full table is generated
                # into BOARD-<status>.md, still in git, still greppable.
                lines.extend([
                    f"{len(tickets)} ticket(s) — full table in "
                    f"[`BOARD-{st}.md`](./BOARD-{st}.md), generated alongside this file.",
                    "",
                ])
                continue
            if not tickets:
                lines.extend(["_none_", ""])
                continue
            lines.extend(
                [
                    "| Ticket | Track | Prio | Type | Summary | Blocked-by |",
                    "| --- | --- | --- | --- | --- | --- |",
                ]
            )
            for t in tickets:
                blockers = ", ".join(t.blockers) if t.blockers else "—"
                pr = f"{t.prio}" if eff[t.slug] == t.prio else f"{t.prio}→{eff[t.slug]}"
                lines.append(f"| {t.slug} | {t.track} | {pr} | {t.type} | {t.summary} | {blockers} |")
            lines.append("")
        lines.extend(["## Ready (no unmet blocker)", ""])
        for line in self.cmd_ready().splitlines():
            if line.startswith("  "):
                lines.append("- " + line[2:])
        lines.extend(["", "## Leverage (tickets each one unblocks)", ""])
        for slug, n in sorted(self.leverage_counts().items(), key=lambda kv: (-kv[1], kv[0])):
            lines.append(f"- **{n}** — {slug}")
        lines.append("")
        return "\n".join(lines)

    def render_brief_md(self, ready_cap: int = 30) -> str:
        """The AGENT-facing board: what to pick, and what not to touch.

        BOARD.md is the full grid and reads as a human kanban. An agent needs
        far less — the ranked head of the queue, the live locks it must not
        collide with, and the parked/blocked work it should not claim — and
        pays for everything else in context before it can start. One line per
        ticket, no summaries: the ticket file is one Read away when it matters.
        """
        eff = self.effective_prio()
        lev = self.leverage_counts()
        counts = " ".join(f"{st}:{len(self.by_status[st])}" for st in STATUSES
                          if self.by_status[st])
        lines = [
            "# Board brief",
            "",
            "_Generated by `tools/progress.sh board-md`. The agent-facing board:_",
            "_ranked queue head, live locks, and what not to claim. Full grid with_",
            "_summaries: [`BOARD.md`](./BOARD.md). Per-track queue:_",
            "_`tools/progress.sh ready --track X`; single pick: `next --track X`._",
            "",
            f"`{counts}`",
            "",
        ]

        # Live locks first: this is the collision-avoidance data, and it is the
        # one thing an agent cannot reconstruct from its own reasoning.
        lines.append("## Held now (working/ — do not touch these files)")
        lines.append("")
        held = self.by_status["working"]
        if not held:
            lines.append("_none — no lane is locked._")
        else:
            for t in held:
                owner = t.owner or "unrecorded"
                lines.append(f"- `{t.slug}` [{t.track}] — owner: {owner}")
        lines.append("")

        for st, why in (("urgent", "jump the queue"),
                        ("unfinished", "parked mid-flight; re-claim, do not duplicate"),
                        ("blocked", "has an unmet blocker; do not claim")):
            ts = self.by_status[st]
            if not ts:
                continue
            lines.extend([f"## {st} ({len(ts)}) — {why}", ""])
            for t in ts:
                bl = f" — blocked-by: {', '.join(t.blockers)}" if t.blockers else ""
                lines.append(f"- `{t.slug}` [{t.track}]{bl}")
            lines.append("")

        rt = self.ready_tickets("")
        shown = rt[:ready_cap]
        lines.extend([f"## Ready — top {len(shown)} of {len(rt)}, ranked", ""])
        for t in shown:
            unb = lev.get(t.slug, 0)
            extra = f" (unblocks {unb})" if unb else ""
            lines.append(f"- `[p{eff[t.slug]:>3}] [{t.track}]` {t.slug}{extra}")
        if len(rt) > len(shown):
            lines.append("")
            lines.append(
                f"_{len(rt) - len(shown)} more ready — `tools/progress.sh ready "
                f"--track X` for a lane's full queue._"
            )
        lines.append("")
        return "\n".join(lines)

    def render_archive_md(self, st: str) -> str:
        """The full table for an archived status, split out of BOARD.md."""
        eff = self.effective_prio()
        lines = [
            f"# Progress board — {st}",
            "",
            "_Generated by `tools/progress.sh board-md` alongside `BOARD.md`, which",
            f"carries a pointer here instead of this table. Split out because {st}/ is a",
            "record of finished work, not project state: an agent orienting on the board",
            "should not read it to find out what to do. Grep it freely._",
            "",
            "| Ticket | Track | Prio | Type | Summary | Blocked-by |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
        for t in self.by_status[st]:
            blockers = ", ".join(t.blockers) if t.blockers else "\u2014"
            pr = f"{t.prio}" if eff[t.slug] == t.prio else f"{t.prio}\u2192{eff[t.slug]}"
            lines.append(f"| {t.slug} | {t.track} | {pr} | {t.type} | {t.summary} | {blockers} |")
        lines.append("")
        return "\n".join(lines)

    @staticmethod
    def _atomic_write(dest: Path, out: str) -> None:
        fd, tmp_name = tempfile.mkstemp(prefix=dest.name + ".", dir=str(dest.parent))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(out)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_name, dest)
        finally:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)

    def write_board_md(self) -> None:
        for st in ARCHIVED_STATUSES:
            self._atomic_write(PROG / f"BOARD-{st}.md", self.render_archive_md(st))
        self._atomic_write(PROG / "BOARD-brief.md", self.render_brief_md())
        self._atomic_write(PROG / "BOARD.md", self.render_board_md())

    def render_board_html(self) -> str:
        """One self-contained BOARD.html: the board tables with each slug
        linking to the full ticket rendered further down the same page.
        Works from file:// — no server, no external assets."""
        slugs = set(self.by_slug)
        eff = self.effective_prio()

        def esc(x: str) -> str:
            return x.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

        def inline(x: str) -> str:
            x = esc(x)
            # [[wiki-link]] -> in-page anchor when the ticket exists
            def wiki(m: re.Match) -> str:
                sl = m.group(1)
                if sl in slugs:
                    return f'<a href="#t-{sl}">{sl}</a>'
                return f"<em>{sl}</em>"
            # Patterns are module-level constants (_RX_*), NOT literals passed to
            # re.sub on every call. They are identical either way -- re.sub caches
            # compiled patterns -- but the cache is a dict keyed on the pattern
            # STRING, so a literal here pays a hash of the pattern text per call
            # per line. Measured over a full BOARD.html render: ~1.9M lookups,
            # 18.66s -> 12.99s, output byte-identical. The render is on the path
            # of every ticket move in every lane, so this is the hottest cheap
            # win in the tool. (pxx-a5, chore-t-board-html-render-is-13s-...)
            x = _RX_WIKI.sub(wiki, x)
            x = _RX_CODE.sub(r"<code>\1</code>", x)
            x = _RX_STRONG.sub(r"<strong>\1</strong>", x)
            x = _RX_EM.sub(r"<em>\1</em>", x)
            x = _RX_DEL.sub(r"<del>\1</del>", x)
            x = _RX_LINK.sub(r'<a href="\2">\1</a>', x)
            # bare ticket slugs in prose become links too (cheap nicety)
            return x

        def md_html(text: str) -> str:
            out: list[str] = []
            in_code = False
            in_list = False
            in_table = False
            for line in text.splitlines():
                if line.strip().startswith("```"):
                    if in_list:
                        out.append("</ul>"); in_list = False
                    if in_table:
                        out.append("</table>"); in_table = False
                    if in_code:
                        out.append("</pre>")
                    else:
                        out.append("<pre>")
                    in_code = not in_code
                    continue
                if in_code:
                    out.append(esc(line))
                    continue
                stripped = line.strip()
                if stripped.startswith("|") and stripped.endswith("|"):
                    cells = [c.strip() for c in stripped.strip("|").split("|")]
                    if all(re.fullmatch(r":?-{3,}:?", c) for c in cells):
                        continue  # separator row
                    if in_list:
                        out.append("</ul>"); in_list = False
                    if not in_table:
                        out.append("<table>")
                        in_table = True
                    out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in cells) + "</tr>")
                    continue
                if in_table:
                    out.append("</table>"); in_table = False
                m = re.match(r"^(#{1,6})\s+(.*)$", line)
                if m:
                    if in_list:
                        out.append("</ul>"); in_list = False
                    lvl = min(len(m.group(1)) + 2, 6)  # demote: ticket h1 -> h3
                    out.append(f"<h{lvl}>{inline(m.group(2))}</h{lvl}>")
                    continue
                m = re.match(r"^\s*[-*]\s+(.*)$", line)
                if m:
                    if not in_list:
                        out.append("<ul>")
                        in_list = True
                    out.append(f"<li>{inline(m.group(1))}</li>")
                    continue
                if in_list and line[:1] == " " and stripped:
                    # hanging-indent continuation of the previous bullet
                    out[-1] = out[-1][:-5] + " " + inline(stripped) + "</li>"
                    continue
                if in_list:
                    out.append("</ul>"); in_list = False
                if not stripped:
                    out.append("")
                    continue
                out.append(f"<p>{inline(line)}</p>")
            if in_code:
                out.append("</pre>")
            if in_list:
                out.append("</ul>")
            if in_table:
                out.append("</table>")
            return "\n".join(out)

        css = """
body{font:15px/1.5 system-ui,sans-serif;margin:0 auto;max-width:70rem;padding:1rem 2rem 4rem;
     background:#111418;color:#d6dbe1}
a{color:#6cb6ff;text-decoration:none} a:hover{text-decoration:underline}
h1,h2{border-bottom:1px solid #2a2f36;padding-bottom:.25rem}
h1{font-size:1.5rem} h2{font-size:1.2rem;margin-top:2.2rem}
h3{font-size:1.08rem;margin-top:2rem;color:#e8ecf1}
table{border-collapse:collapse;margin:.6rem 0;width:100%} 
td,th{border:1px solid #2a2f36;padding:.28rem .55rem;text-align:left;vertical-align:top}
th{background:#1a1f26}
code{background:#1d232b;padding:.08rem .3rem;border-radius:3px;font-size:.92em}
pre{background:#1d232b;padding:.7rem .9rem;border-radius:5px;overflow-x:auto;font-size:.9em}
pre code{background:none;padding:0}
.badge{display:inline-block;font-size:.75em;padding:.1rem .5rem;border-radius:8px;
       background:#1a2634;color:#9fc6ee;margin-left:.5rem;vertical-align:middle}
.ticket{border:1px solid #2a2f36;border-radius:8px;padding:.2rem 1.2rem 1rem;margin:1.2rem 0;
        background:#151a20}
.top{font-size:.8em;float:right;margin-top:1.4rem}
.gen{color:#7d8590;font-size:.85em}
"""
        h: list[str] = []
        h.append("<!DOCTYPE html><html><head><meta charset='utf-8'>")
        h.append("<meta name='viewport' content='width=device-width,initial-scale=1'>")
        h.append("<title>frankonpiler board</title>")
        h.append(f"<style>{css}</style></head><body>")
        h.append("<h1>frankonpiler — progress board</h1>")
        h.append("<p class='gen'>Generated by <code>tools/progress.sh board-md</code> "
                 "alongside BOARD.md. Click a ticket to jump to its full text below; "
                 "everything is in this one file, works offline.</p>")
        counts = " · ".join(f"<a href='#s-{st}'>{st} {len(self.by_status[st])}</a>" for st in STATUSES)
        h.append(f"<p>{counts}</p>")
        for st in STATUSES:
            tickets = self.by_status[st]
            h.append(f"<h2 id='s-{st}'>{st} <span class='badge'>{len(tickets)}</span></h2>")
            if not tickets:
                h.append("<p class='gen'>none</p>")
                continue
            h.append("<table><tr><th>Ticket</th><th>Track</th><th>Prio</th><th>Type</th>"
                     "<th>Summary</th><th>Blocked-by</th></tr>")
            for t in tickets:
                blockers = ", ".join(
                    (f"<a href='#t-{b}'>{b}</a>" if b in slugs else esc(b)) for b in t.blockers
                ) or "&mdash;"
                pr = f"{t.prio}" if eff[t.slug] == t.prio else f"{t.prio}&rarr;{eff[t.slug]}"
                h.append(
                    f"<tr><td><a href='#t-{t.slug}'>{esc(t.slug)}</a></td>"
                    f"<td>{esc(t.track)}</td><td>{pr}</td><td>{esc(t.type)}</td>"
                    f"<td>{inline(t.summary)}</td><td>{blockers}</td></tr>"
                )
            h.append("</table>")
        h.append("<h2>Tickets</h2>")
        for st in STATUSES:
            for t in self.by_status[st]:
                h.append(f"<div class='ticket' id='t-{t.slug}'>")
                h.append("<a class='top' href='#'>&uarr; top</a>")
                h.append(f"<h3>{esc(t.slug)} <span class='badge'>{st}</span>"
                         f"<span class='badge'>Track {esc(t.track)}</span></h3>")
                h.append(f"<p class='gen'><code>{esc(str(t.path.relative_to(ROOT)))}</code></p>")
                h.append(md_html(t.text))
                h.append("</div>")
        h.append("</body></html>")
        return "\n".join(h)

    def write_board_html(self) -> None:
        out = self.render_board_html()
        dest = PROG / "BOARD.html"
        fd, tmp_name = tempfile.mkstemp(prefix="BOARD.", suffix=".html", dir=str(PROG))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(out)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_name, dest)
        finally:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)

    def _audit_citations(self) -> tuple[list[str], list[tuple[str, str]]]:
        """Resolved tickets whose commit citation nobody else can look up.

        Returns (slugs still holding the placeholder, [(slug, dead sha)]).

        `origin/master` is the oracle on purpose, not the local object DB: a
        rebased-away commit is still reachable from the author's reflog, which
        is precisely the place the OTHER box cannot look. One rev-list over
        ~9k commits costs ~0.2s, so the whole audit is a single subprocess.
        """
        try:
            # subjects come from the SAME pass: the bookkeeping-citation arms
            # below need one per cited sha, and doing that as 1400 `git log -1`
            # calls cost 17s where this costs the same ~0.2s as before.
            out = subprocess.run(
                ["git", "log", "--format=%H%x00%s", "origin/master"], cwd=ROOT,
                text=True, capture_output=True, check=True, timeout=60).stdout
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError):
            return [], [], []      # no origin (fresh clone, scratch repo) — skip
        by_prefix: dict[str, list[str]] = defaultdict(list)
        subjects: dict[str, str] = {}
        for line in out.splitlines():
            sha, _, subj = line.partition("\0")
            if not sha:
                continue
            by_prefix[sha[:7]].append(sha)
            subjects[sha] = subj

        pending: list[str] = []
        dead: list[tuple[str, str]] = []
        bookkeeping: list[tuple[str, str, str]] = []
        # A placeholder is wrong in ANY bucket — a ticket can be resolved and
        # filed onward (done-followup/) in one commit. Dead-sha auditing stays
        # on the resolved buckets: an open ticket citing an old commit in prose
        # is discussion, not a claim about where the fix landed.
        # Count exactly what sync.sh can FILL — same pattern, same buckets.
        # This used to be a bare substring over every bucket while sync grepped
        # one spelling over the resolved ones, so the number check printed and
        # the work sync could do were different quantities that nobody had put
        # side by side. A placeholder in backlog/ or working/ is not owed a sha:
        # the ticket has not landed, and there is no commit to cite yet.
        for st in RESOLVED_BUCKETS:
            for t in self.by_status[st]:
                if PENDING_RE.search(t.text):
                    pending.append(t.slug)
        for st in RESOLVED_BUCKETS:
            for t in self.by_status[st]:
                for sha in CITATION_RE.findall(t.text):
                    if not any(full.startswith(sha)
                               for full in by_prefix.get(sha[:7], ())):
                        dead.append((t.slug, sha))
                        continue
                    full = next((f for f in by_prefix.get(sha[:7], ())
                                 if f.startswith(sha)), None)
                    subj = subjects.get(full, "") if full else ""
                    if not subj:
                        continue
                    # Arm 1: a WATCHER publish. That process never fixed
                    # anything, so a ticket citing one is citing an observation.
                    if BOOKKEEPING_SUBJECT.match(subj):
                        bookkeeping.append((t.slug, sha, subj))
                    # Arm 2: SELF-REFERENTIAL — the ticket cites the commit
                    # whose whole content is resolving that same ticket. Perfect
                    # precision on the one instance anybody has verified
                    # (bug-a-virtual-method-int64-in-and-out-32bit cites
                    # fd99c8836 where the fix is 77d32b346), and it finds
                    # exactly that one across all 1424 cited shas.
                    elif SELF_RESOLVE.match(subj) and t.slug in subj:
                        bookkeeping.append((t.slug, sha, subj))
        return pending, dead, bookkeeping

    def check(self, strict: bool = False) -> tuple[int, str]:
        problems = 0
        warning_count = 0
        lines: list[str] = []
        exists = self.by_slug
        indeg = {s: 0 for s in exists}
        dependents: dict[str, list[str]] = defaultdict(list)

        # Load() no longer dies on a non-UTF-8 ticket, so the damage has to be
        # reported somewhere or the replacement really would be silent. WARNING,
        # not a problem: the board is usable and the ticket is readable; what is
        # lost is the exact bytes of some pasted evidence, which is worth
        # repairing at leisure and never worth blocking a dispatch over.
        for path in self.mojibake:
            lines.append(
                f"ENCODING: {path.name} is not valid UTF-8 — undecodable bytes "
                f"shown as U+FFFD. Re-paste any raw program output as \\xNN "
                f"escapes so the evidence survives.")
            warning_count += 1

        for t in self.tickets:
            for b in t.blockers:
                if b not in exists:
                    lines.append(f"DANGLING: {t.slug} blocked-by '{b}' — no such ticket")
                    problems = 1
                else:
                    dependents[b].append(t.slug)
                    indeg[t.slug] += 1

        q = deque([s for s, n in indeg.items() if n == 0])
        gone = 0
        while q:
            s = q.popleft()
            gone += 1
            for dep in dependents.get(s, []):
                indeg[dep] -= 1
                if indeg[dep] == 0:
                    q.append(dep)
        if gone != len(exists):
            lines.append(f"CYCLE: dependency graph is not a DAG ({len(exists) - gone} tickets in a cycle)")
            problems = 1

        for t in self.by_status["working"]:
            if not t.owner:
                lines.append(f"NO-OWNER: {t.slug} is in working/ but has no Owner")
                problems = 1

        # --- the ticket SET, not ticket content ---------------------------
        # Everything above validates tickets we managed to PARSE. These two
        # check the set of files itself, and both were invisible until
        # 2026-08-29, when they happened together on
        # bug-a-per-cpu-ifdef-chains-in-builtinheap-fail-open.
        #
        # Two appends were addressed to backlog/<slug>.md while the ticket sat
        # in backlog_new/. A shell append to a missing path CREATES it, so the
        # appends reported success and the analysis landed in a file with no
        # frontmatter and no body, while the real ticket got none of it. The
        # ranker then offered the slug TWICE, both entries reading as coherent
        # when opened alone, and neither able to announce the other. It
        # survived a day of ranked queues and a board regeneration.
        #
        # Neither condition has a legitimate case, and both are one line to
        # test — which is the whole argument for testing them.
        seen_slug: dict[str, str] = {}
        slug_toks: list[tuple[str, str, set[str]]] = []
        for st in self.RANKED_STATUSES:
            d = PROG / st
            if not d.is_dir():
                continue
            for path in sorted(d.glob("*.md")):
                # README.md documents a folder's charter (backlog_new/, float/,
                # experimental/ each have one); BOARD*.md are generated.
                if path.name == "README.md" or path.name.startswith("BOARD"):
                    continue
                head = ""
                try:
                    with path.open(encoding="utf-8", errors="replace") as fh:
                        head = fh.readline()
                except OSError as exc:
                    lines.append(f"UNREADABLE: {st}/{path.name} — {exc}")
                    problems = 1
                    continue
                if head.strip() != "---":
                    lines.append(
                        f"NO-FRONTMATTER: {st}/{path.name} does not start with '---' — "
                        f"an orphan fragment or a truncated ticket, not a ticket the ranker can read")
                    problems = 1
                slug_toks.append((st, path.name, {
                    t for t in re.split(r"[-_.]", path.stem.lower())
                    if len(t) > 2 and t not in _DUP_STOP}))
                prev = seen_slug.get(path.name)
                if prev is not None:
                    lines.append(
                        f"DUP-SLUG: {path.name} is in BOTH {prev}/ and {st}/ — "
                        f"unresolvable by construction: claiming one leaves the other ranked, "
                        f"and the two bodies can differ. Merge by hand; do not auto-pick.")
                    problems = 1
                else:
                    seen_slug[path.name] = st

        # --- near-duplicate slugs -----------------------------------------
        # Two lanes filing the same ticket minutes apart is real and measured
        # (2026-08-29, twice in one evening: the EmitLoadVarA64 pair and the
        # LowerCase pair, the second of which this coordinator caused by
        # re-filing a ticket a previous session of its own had verified a day
        # earlier). DUP-SLUG above catches only IDENTICAL filenames, which is
        # the case that never happens -- two people describing one bug choose
        # different words.
        #
        # Threshold 4 is calibrated, not guessed. Measured over the 341 ranked
        # tickets on master that day: 3 pairs flagged, 3 genuine duplicates,
        # ZERO false positives; threshold 5 caught 1 and missed two real ones.
        # A check that cries wolf earns the habit of being scrolled past, so
        # recalibrate if the board ever grows a legitimate family of
        # same-topic tickets rather than loosening it by reflex.
        #
        # WHAT THIS CANNOT DECIDE, and the wording above is careful about it:
        # slug similarity is evidence of a shared SUBJECT, never of a shared
        # CAUSE. twatch files per JOB, so one commit reding a family of related
        # tests legitimately produces N tickets with near-identical slugs --
        # those are TRUE positives that must NOT be merged (pxx-a5, 2026-08-29,
        # the two nilpy fallback-import regressions: two different .npy files,
        # one cause, both correctly filed and both correctly separate).
        # The scan surfaces the pair; a human decides identity.
        for _i in range(len(slug_toks)):
            _st1, _n1, _t1 = slug_toks[_i]
            for _j in range(_i + 1, len(slug_toks)):
                _st2, _n2, _t2 = slug_toks[_j]
                _shared = _t1 & _t2
                if len(_shared) >= 4:
                    lines.append(
                        f"NEAR-DUP: {_st1}/{_n1} and {_st2}/{_n2} share "
                        f"{len(_shared)} slug words ({', '.join(sorted(_shared))}) "
                        f"— same ticket filed twice, or one CAUSE with N "
                        f"legitimately separate tickets? Do not merge on the "
                        f"score alone")
                    problems = 1

        for t in self.by_status["unfinished"]:
            tr = t.track
            if tr == "A" or "A+" in tr or "+A" in tr:
                warning_count += 1
                if strict:
                    lines.append(
                        f"WARN-UNFINISHED-A: {t.slug} is Track A in unfinished/ — compiler work is parked; resolve before treating Track A as clean"
                    )
                    problems = 1
            if tr == "C" or "C+" in tr or "+C" in tr:
                warning_count += 1
                if strict:
                    lines.append(
                        f"WARN-UNFINISHED-C: {t.slug} is Track C (C frontend) in unfinished/ — compiler work is parked; resolve before treating Track C as clean"
                    )
                    problems = 1

        # --- decide-* lifecycle -------------------------------------------
        # A `decide-` ticket is answered in PROSE, so nothing mechanical
        # notices when the answer lands: it keeps its prio and stays in the
        # ready queue as if still open. 2026-07-20:
        # decide-variant-tag-mismatch-policy sat in backlog at prio 60 with
        # both halves settled inside it, ranking above real work.
        # Heading forms actually in use across the board — the first cut only
        # knew DECISION/RESOLVED and so missed three decided tickets still
        # sitting in backlog ("## USER DECISION 2026-07-12", "## DECIDED
        # 2026-07-20"). Anchored right after the '##' on purpose: it must NOT
        # match "## Also decided-needed", which means the opposite.
        decision_re = re.compile(
            r"^##\s+(USER\s+)?(DECISION|DECIDED|RESOLVED)\b", re.I | re.M)
        for st in ("backlog", "backlog_new", "urgent"):
            for t in self.by_status[st]:
                if not (t.slug.startswith("decide-") and decision_re.search(t.text)):
                    continue
                # "recorded a decision" does not always mean "should move": a
                # decision can BE "defer this, and keep gating what depends on
                # it". decide-1-0-scope-promise is exactly that — it answers
                # "first release is 0.1 beta" while deliberately holding
                # feature-promo-launch-plan's loud launch shut. Closing it
                # would release the very work the decision parks. Such a
                # ticket declares itself with `keep-open:` in frontmatter and
                # is not nagged about; everything else is drift.
                if t.fm.get("keep-open"):
                    continue
                lines.append(
                    f"DECIDED-NOT-MOVED: {t.slug} records a decision but is still in {st}/ — "
                    f"move it to decided/ (it unblocks dependents like done/, but stays a "
                    f"reference, not 'work complete'), or set `keep-open: <why>` if it "
                    f"deliberately gates something"
                )
                problems = 1

        # --- a blocked-by edge is a claim about the world at FILING time ----
        #
        # Nothing re-checks it. Resolving a blocker is an event on the BLOCKER,
        # and the edge lives on the DEPENDENT, so at the moment the claim goes
        # stale nobody is standing where it is written.
        #
        # Measured repo-wide 2026-08-28: 14 live tickets named a closed blocker;
        # FIVE were fully unblocked and all five sat in blocked/, which
        # ready/next never scan. One of them was p85. A stale edge in that
        # direction is SILENT — the ticket is not surfaced, so it never ages
        # into anyone's view and no one notices the absence of something they
        # were not expecting.
        #
        # The two polarities are reported apart because they cost different
        # things. Fully-clear is actionable now (move it and it ranks).
        # Partially-stale is only a nudge to re-read: some blockers closing is
        # the normal life of a ticket, not a defect, and failing on it would
        # make `check` cry wolf on ordinary progress.
        #
        # This is a FRONTMATTER scan and it covers half the family; see the
        # aperture note printed with the findings.
        closed_st = {"done", "rejected", "decided"}
        for t in self.tickets:
            if t.status in closed_st or not t.blockers:
                continue
            closed = [b for b in t.blockers
                      if b in exists and self.by_slug[b].status in closed_st]
            if not closed:
                continue
            if len(closed) == len(t.blockers):
                # SEVERITY, measured rather than assumed. `ready_tickets` keeps
                # a ticket whose blockers are all in `resolved_slugs`, so a
                # cleared edge in a RANKED folder suppresses nothing — the
                # ticket ranks normally and the stale edge is untidy, not
                # harmful. Failing on those would report 17 findings of which
                # 12 cost nobody anything, which is how a check earns the habit
                # of being scrolled past.
                #
                # `blocked/` is different in kind: the folder MEANS "has an
                # unmet blocker" and ready/next never scan it, so a
                # fully-cleared ticket there is a contradiction that also hides
                # it. That is the case worth failing on, and it is the one the
                # ticket measured — a p85 invisible to the ranker.
                #
                # rainy-day/ float/ experimental/ are also unranked but
                # DELIBERATELY so; a cleared ticket parked there is parked on
                # purpose, not hidden by accident, so it stays a warning.
                if t.status == "blocked":
                    lines.append(
                        f"STALE-EDGE-HIDDEN: {t.slug} [{t.track} p{t.prio}] is "
                        f"in blocked/ but every blocker it names is closed "
                        f"({', '.join(sorted(closed))}) — ready/next never scan "
                        f"blocked/, so it is invisible to the ranker; move it"
                    )
                    problems = 1
                else:
                    warning_count += 1
                    if strict:
                        lines.append(
                            f"STALE-EDGE-CLEAR: {t.slug} [{t.track} p{t.prio}] "
                            f"in {t.status}/ names only closed blockers "
                            f"({', '.join(sorted(closed))}) — it ranks "
                            f"normally; the edge is stale, not harmful"
                        )
            else:
                warning_count += 1
                if strict:
                    rest = sorted(set(t.blockers) - set(closed))
                    lines.append(
                        f"STALE-EDGE-PARTIAL: {t.slug} [{t.track} p{t.prio}] — "
                        f"{len(closed)} of {len(t.blockers)} blockers closed "
                        f"({', '.join(sorted(closed))}); still waiting on "
                        f"{', '.join(rest)}"
                    )

        # THE PROSE HALF, for the PARKED population only.
        #
        # The aperture note below used to say the prose half "cannot be"
        # checked, reasoning that a body-grep for slug mentions would be
        # "mostly noise". That prediction is correct for the scan it imagined
        # and wrong for this one, and the difference is the SCOPE, not the
        # cleverness. Measured 2026-08-30, after frankwasm found a ticket
        # parked twelve days on four blockers that had all resolved the day
        # the park was written:
        #
        #   all 376 live tickets, slug-mention only ......... ~50, mostly noise
        #   all 376 live, mention near a condition word ..... ~35, still noise
        #   the 35 PARKED tickets, mention near a condition ... 10  <- signal
        #
        # A live ticket citing a done ticket is NORMAL -- that is how the
        # record works, and it is what floods the wide scan. A PARKED ticket
        # citing a done ticket is a candidate stale resume condition, because
        # parking is the only state where "X must land first" is load-bearing.
        # The signal was never "names a resolved slug"; it is "names a
        # resolved slug AND is not moving".
        #
        # Frontmatter edges are excluded: the scan above owns those, and
        # reporting both would double-count the tickets that do it correctly.
        PARK_COND = re.compile(
            r"blocked on|blocked by|waiting on|wait for|resume|depends on|"
            r"prerequisite|gated on|once .{0,40}land|after .{0,40}land|park",
            re.I)
        SLUGISH = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+){3,}")
        for t in self.tickets:
            # working/ IS SCANNED -- added 2026-08-30, and it is the gap that
            # mattered. frankwasm: "My ticket was in working/, outside both
            # apertures, which is precisely why nothing caught it for two
            # days." An active lock is the LONGEST-lived place a stale prose
            # dependency can sit, because the holder wrote the park and has
            # stopped re-reading it. Reported as HELD, never dispatched.
            if t.status not in ("unfinished", "blocked", "working"):
                continue
            # EXCLUDE TICKETS THAT ARE ACTUALLY BEING WORKED. Measured by
            # frankwasm 2026-08-30, triaging the scan's first eleven: the two
            # loudest hits -- naming SIX and FOUR resolved slugs -- were both
            # `status: working` with an `owner:`, sitting in unfinished/ while
            # a lane actively edited them. The slugs they cite are that lane's
            # OWN landed fixes, cited by the notes recording them.
            #
            # So the scan's signal strength was inverted: citation density
            # tracks how much work a lane has LANDED, which means the loudest
            # findings systematically point at the busiest lane and at files
            # nobody else may open. Two of eleven, and they were the two I told
            # an agent to take first -- which nearly put two agents in one file.
            # HELD tickets are REPORTED, not skipped -- corrected 2026-08-30.
            #
            # The exclusion below was added because the scan's two loudest hits
            # were tickets a lane was actively editing, and dispatching a second
            # agent at them nearly put two agents in one file. That reason is
            # about DISPATCH. Applied to REPORTING it was wrong, and frankwasm
            # produced the counter-example from inside its own lane: its ticket
            # sat in working/ for two days accumulating exactly this defect --
            # a dependency stated in prose, in a plan file, on a side branch --
            # and nothing caught it, because working/ is outside both apertures.
            #
            # A long-lived lock is not evidence a ticket is healthy. It is the
            # place a stale prose dependency hides LONGEST, because the holder
            # has stopped re-reading the park they wrote.
            #
            # So: still surfaced, under a different verb. Tell the holder; do
            # not send anyone else.
            held = (t.status == "working"
                    or t.fm.get("status", "").strip() == "working"
                    or bool(t.fm.get("owner", "").strip()))
            rows = t.text.splitlines()
            hits: set[str] = set()
            dangling: set[str] = set()
            # THE PARK'S CONDITION CAN BE REWRITTEN WHILE IT IS PARKED, and
            # then counting resolved blockers answers a question the ticket
            # stopped asking. Found by frankD 2026-08-30 on
            # feature-pascal-corpus-expansion [P p75]: seven resolved slugs in
            # the prose, all real, all closed -- and a `Status:` line dated
            # LATER naming a different, still-open blocker. The seven and the
            # live block were DISJOINT SETS.
            #
            # frankD's rule, and it is what makes this mechanical: a park's
            # condition needs a date as much as a park does, and the Status
            # line is the only line that carries one -- which is exactly why it
            # was the only line in that file still right. So when a dated
            # Status line names a slug that is STILL OPEN, that is the live
            # condition and every prose hit is history. Report it as such
            # rather than as "the resume condition may already be met", which
            # is what this check said for weeks about a ticket whose condition
            # had been replaced.
            #
            # This also bounds the permanent-false-positive frankD flagged: on
            # a file whose convention is append-never-edit, prose naming
            # resolved tickets inside dated snapshots is the COMMON case, not
            # the rare one, and a check that fires forever trains people to
            # skim past the one time it is right.
            # A WIKILINK MAY LEGITIMATELY POINT AT A DOC, NOT A TICKET.
            # Calibration 2026-08-30 turned up 8 hits, of which one --
            # [[ir-as-substrate]] in feature-port-freebsd-native -- resolves to
            # devdocs/dev/ir-as-substrate.md, a real page and a correct
            # reference. Flagging it would be the check crying wolf on the
            # repo's own cross-referencing convention, and a check that fires
            # on correct usage is the one people learn to scroll past. So a
            # name is dangling only when it is NEITHER a ticket NOR a file
            # anywhere under devdocs/. The remaining 7 resolve to nothing at
            # all -- there are ZERO project_* files in the tree, measured.
            if not hasattr(self, "_doc_basenames"):
                names = set()
                try:
                    for dp, _dn, fns in os.walk(ROOT / "devdocs"):
                        for fn in fns:
                            if fn.endswith(".md"):
                                names.add(fn[:-3])
                            names.add(fn)
                except Exception:
                    pass
                self._doc_basenames = names
            live_block = ""
            for line in rows:
                if not re.match(r"\s*[-*]?\s*\**Status\**:?", line, re.I):
                    continue
                if not PARK_COND.search(line):
                    continue
                for m in SLUGISH.finditer(line):
                    cand = m.group(0)
                    if cand == t.slug:
                        continue
                    o = self.by_slug.get(cand)
                    if o is not None and o.status not in closed_st:
                        live_block = cand
                        break
                if live_block:
                    break
            # SCANNED OVER THE WHOLE BODY, not just near a blocking phrase.
            # A resolved-slug mention is only signal next to a condition word
            # -- that bound is what took the wide scan from ~50 noisy hits to
            # 10 real ones. A DANGLING link needs no such bound: it is wrong
            # wherever it sits, because it resolves to nothing anywhere, and
            # the counters that misread it do not check for a condition word
            # either. Different signal, different aperture.
            # THE VOCABULARY IS DERIVED FROM THE BOARD, NOT HAND-LISTED.
            # A hand-written prefix list misses whatever was added since it was
            # written -- frankD, 2026-08-30: a list drafted that day would have
            # omitted `refactor-` (37 tickets), which owns one of the eleven
            # real findings. So the set of legitimate ticket prefixes is read
            # off the live slugs each run and cannot go stale.
            #
            # WHY A PREFIX AT ALL, AND NOT JUST "not a known slug": because
            # `[[...]]` is used for MORE than tickets. `project_*` and
            # `feedback_*` are the AGENT-MEMORY namespaces -- 270 references,
            # 129 distinct names, and no such file has ever existed in this
            # repo, because they were never meant to. feature-dynamic-compiler-
            # tables:149 says it in words: "see [[project_dynamic_compiler_
            # arrays_pattern.md]] IN AGENT MEMORY". Snake_case, where every
            # ticket slug on this board is kebab-case.
            #
            # This exclusion was SPECIFIED before the check was written, in the
            # ticket the check implements -- chore-t-a-wikilink-to-a-ticket-
            # that-does-not-exist-is-never-detected [T p30], whose fix sketch
            # says "ignoring the project_* / feedback_* memory namespaces AND
            # devdocs filenames", and which records that its own first count
            # was 252 for exactly this reason. The first shipped version
            # implemented the devdocs half and shipped past the other, having
            # calibrated only against the namespace its author thought of.
            # Grep for the incumbent applies to a SPEC as much as to a tool.
            if not hasattr(self, "_ticket_prefixes"):
                pfx = set()
                for known in self.by_slug:
                    head = known.split("-", 1)[0]
                    if head and head.isalpha():
                        pfx.add(head)
                self._ticket_prefixes = pfx
            for j in range(len(rows)):
                for m in re.finditer(r"\[\[([a-z0-9][a-z0-9_-]{6,})\]\]", rows[j]):
                    cand = m.group(1)
                    if (cand != t.slug
                            and self.by_slug.get(cand) is None
                            and cand not in self._doc_basenames
                            and cand.split("-", 1)[0] in self._ticket_prefixes):
                        dangling.add(cand)
            for i, line in enumerate(rows):
                if not PARK_COND.search(line):
                    continue
                for j in range(max(0, i - 2), min(len(rows), i + 3)):
                    # A DANGLING WIKILINK READS AS AN OPEN DEPENDENCY TO
                    # ANYTHING THAT COUNTS THEM AND AS A TYPO TO A HUMAN --
                    # which is why nobody fixes it and every counter is wrong.
                    # frankD, 2026-08-30: feature-pascal-corpus-fpc-testsuite
                    # [P p65] showed four not-done links, of which TWO resolved
                    # to no file at all and one was the umbrella itself. Its
                    # "four resolved" understated -- it is behind ONE item.
                    # Only explicit [[...]] links are flagged: the bare-slug
                    # regex matches too much prose to carry this without noise,
                    # and a wikilink is unambiguous intent to point at a ticket.
                    for m in SLUGISH.finditer(rows[j]):
                        s = m.group(0)
                        if s == t.slug or s in t.blockers:
                            continue
                        o = self.by_slug.get(s)
                        if o is not None and o.status in closed_st:
                            hits.add(s)
            if dangling:
                warning_count += 1
                dshown = sorted(dangling)[:3]
                dmore = f" (+{len(dangling) - 3} more)" if len(dangling) > 3 else ""
                lines.append(
                    f"DANGLING-LINK: {t.slug} [{t.track} p{t.prio}] names "
                    f"{len(dangling)} wiki-link(s) ANYWHERE IN ITS BODY whose "
                    f"prefix is a live ticket prefix but which resolve to no "
                    f"ticket ({', '.join(dshown)}{dmore}). A dangling link "
                    f"reads as an OPEN dependency to anything counting them "
                    f"and as a typo to a human, so a park can look blocked on "
                    f"four things and be blocked on one. READ IT BEFORE "
                    f"CHANGING IT: it may be a RENAME (point it at the new "
                    f"slug), a ticket that was PLANNED AND NEVER FILED (file "
                    f"it, or de-link and say so), work ALREADY DELIVERED under "
                    f"another name (say so -- the link is advertising finished "
                    f"work as pending), or prose that was never a ticket at "
                    f"all (de-link, keep the sentence). Deleting is one of four "
                    f"outcomes and is rarely the right one"
                )
            if hits and live_block:
                warning_count += 1
                shown = sorted(hits)[:4]
                more = f" (+{len(hits) - 4} more)" if len(hits) > 4 else ""
                lines.append(
                    f"PARK-CONDITION-REWRITTEN: {t.slug} [{t.track} p{t.prio}] "
                    f"names {len(hits)} now-resolved ticket(s) in its prose "
                    f"({', '.join(shown)}{more}) BUT its Status line names "
                    f"`{live_block}`, which is still open. The park's condition "
                    f"was REPLACED while it was parked, so the resolved set and "
                    f"the live block are disjoint -- counting the resolved ones "
                    f"answers a question this ticket stopped asking. The Status "
                    f"line is the only line carrying a date, which is why it is "
                    f"the one still right. Resume is gated on `{live_block}` alone"
                )
                continue
            if hits:
                warning_count += 1
                shown = sorted(hits)[:4]
                more = f" (+{len(hits) - 4} more)" if len(hits) > 4 else ""
                if held:
                    who = t.fm.get("owner", "").strip() or "a lane"
                    lines.append(
                        f"STALE-PARK-HELD: {t.slug} [{t.track} p{t.prio}] is "
                        f"HELD by {who} and its PROSE names {len(hits)} "
                        f"now-resolved ticket(s) near a blocking phrase "
                        f"({', '.join(shown)}{more}). DO NOT CLAIM IT — tell "
                        f"the holder. A long-lived lock is where a stale prose "
                        f"dependency hides longest, because the holder has "
                        f"stopped re-reading the park they wrote"
                    )
                else:
                    lines.append(
                        f"STALE-PARK: {t.slug} [{t.track} p{t.prio}] is parked in "
                        f"{t.status}/ and its PROSE names {len(hits)} now-resolved "
                        f"ticket(s) near a blocking phrase ({', '.join(shown)}"
                        f"{more}) — the resume condition may already be met. "
                        f"Read the park; a prose condition has no owner and "
                        f"nothing else re-checks it"
                    )

        # The mirror: filed as a decision without writing DOWN the answer.
        # Dependents reach the decision by following their blocked-by slug into
        # decided/ (or legacy done/), so a decide- ticket parked there without
        # recording the call leaves them pointing at nothing.
        for st in ("decided", "done"):
            for t in self.by_status[st]:
                if t.slug.startswith("decide-") and not decision_re.search(t.text):
                    warning_count += 1
                    if strict:
                        lines.append(
                            f"WARN-NO-DECISION: {t.slug} is a decide- ticket in {st}/ with no "
                            f"'## DECISION' section — dependents cannot learn what was decided"
                        )
                        problems = 1

        # A REJECTED blocker never unblocks anything: ready_tickets() gates on
        # done_slugs (done only), while effective_prio() treats {done,rejected}
        # as terminal. So a dependent of a rejected ticket is invisible in
        # every queue, forever, with nothing reporting it. Deliberately NOT
        # auto-unblocked: rejecting a decision often moots the dependent too,
        # and silently promoting it to ready would resurrect dead work. Flag it
        # and let a human choose.
        rejected = {t.slug for t in self.by_status["rejected"]}
        for t in self.tickets:
            if t.status in ("done", "rejected"):
                continue
            for b in t.blockers:
                if b in rejected:
                    lines.append(
                        f"BLOCKED-BY-REJECTED: {t.slug} is blocked by '{b}' which was rejected — "
                        f"it can never become ready; re-file it or drop the blocker"
                    )
                    problems = 1

        commit_re = re.compile(r"commit|[0-9a-f]{7,40}", re.I)
        for t in self.by_status["done"]:
            if not commit_re.search(t.text):
                warning_count += 1
                if strict:
                    lines.append(f"WARN-NO-COMMIT: {t.slug} is in done/ but logs no commit")
                    problems = 1

        # A citation is only worth having if the other box can look it up, so
        # audit the ones we make. Two failure modes, one rule:
        #
        #   PENDING-COMMIT survives -> sync.sh never ran (or ran before the
        #       resolve was committed). Actionable NOW, and cheap to fix.
        #   the sha is on no branch  -> it was rewritten by a rebase, reverted,
        #       or dropped. Mostly historical mass; a NEW one means the
        #       placeholder flow was bypassed.
        #
        # Both are warnings, not failures: 324 of the 933 citations already on
        # the board predate the placeholder flow and cannot be repaired.
        # Non-strict still prints a count line, because the hand audit that
        # first caught this (bug-t-resolve-cites-a-sha-the-rebase-then-rewrites)
        # is exactly what should not need doing by hand again.
        # --- a body Status line that contradicts the folder holding the file --
        #
        # The FOLDER is the lock: working/ means an agent is on it right now. The
        # `- **Status:** X` body line duplicates that, so it drifts the moment
        # someone moves a ticket and does not edit the prose — and a stale
        # `Status: working` on a backlog ticket makes a scanning agent skip real
        # work, the exact opposite of what the ranked queue is for. Measured
        # 2026-08-07: twenty tickets claimed `working` while working/ was empty,
        # nine of them in live folders, and `check --strict` said nothing.
        #
        # ONLY flagged when the first word is itself a folder name. The line
        # very often carries prose — "Status: documented, not fixed",
        # "Status: harness" — and a naive equality check reports every one of
        # those as a mismatch (measured: 179 hits, of which only 7 were real).
        #
        # ARCHIVES ARE EXEMPT. done/, rejected/ and decided/ are historical
        # records; CLAUDE.md's rule is that rewriting one falsifies what a past
        # session actually did, so a contradiction there is not a finding.
        #
        # Reported, never repaired: `check` is a read-only command, and `claim`
        # / `resolve` are what move tickets. Auto-editing prose here would make
        # it mutating, which it is not today.
        archive = {"done", "rejected", "decided"}
        # Only LOCK-ish claims. `working` means an agent is on it right now and
        # `urgent` means act first; those are the two a reader acts on, so those
        # are the two worth failing over. A ticket in experimental/ whose body
        # says "Status: backlog" is accurate prose about parked work, not a
        # contradiction — flagging it added 14 findings nobody would act on, and
        # burying the 3 real ones under 170 cosmetic ones is precisely how this
        # drifted in the first place (555 strict findings, none of them this).
        LOCKISH = {"working", "urgent"}
        for t in self.tickets:
            if t.status in archive:
                continue
            m = re.search(r"^- \*\*Status:\*\*\s*(\S+)", t.text, re.MULTILINE)
            if not m:
                continue
            claimed = m.group(1).strip().lower().rstrip(".,:*")
            if claimed == t.status or claimed not in STATUSES:
                continue
            if claimed not in LOCKISH and t.status not in LOCKISH:
                continue
            problems = 1
            lines.append(
                f"STATUS-DRIFT: {t.slug} is in {t.status}/ but its body says "
                f"'Status: {claimed}' — the folder is the lock; fix the line "
                f"(check does not rewrite prose)"
            )

        # The SAME contradiction one aperture over. The scan above reads a
        # PROSE `- **Status:**` bullet; this one reads the FRONTMATTER
        # `status:` field. They are different text in different places and the
        # prose scan cannot see the field, so a ticket can pass it while
        # announcing a lock in its own header.
        #
        # Measured 2026-08-30 over 3277 tickets: 1443 carry a frontmatter
        # `status:`, 85 disagree with their folder, and 82 of those are the
        # vocabulary rather than a defect — `open` in backlog/ and `new` in
        # backlog_new/ are what people write and mean no harm. Flagging all 85
        # would bury the 3 that matter, which is the exact mistake the prose
        # scan above already learned. So LOCKISH only, and the equivalences are
        # named rather than inferred.
        #
        # Why the 3 are worth failing over: the whole fleet is told to OPEN THE
        # TICKET AT HEAD before dispatching, so a header reading
        # `status: working` is read by a careful agent as "someone holds this"
        # and skipped. `feature-a-typeref-migrate-consumers` sat that way for
        # five days at p62 while ranking THIRD of 111 in `ready --track A` --
        # not hidden by the ranker, which listed it correctly every time, but
        # declined by every reader who obeyed the rule and opened it. A ticket
        # that looks taken is more durable than one that is missing, because
        # nothing ever re-checks a lock someone else appears to hold.
        VOCAB = {"backlog": {"open"}, "backlog_new": {"new"}}
        for t in self.tickets:
            if t.status in archive:
                continue
            claimed = str(t.fm.get("status", "")).strip().strip('"').lower()
            if not claimed or claimed == t.status:
                continue
            if claimed in VOCAB.get(t.status, set()):
                continue
            if claimed not in LOCKISH and t.status not in LOCKISH:
                continue
            problems = 1
            lines.append(
                f"FM-STATUS-DRIFT: {t.slug} [{t.track} p{t.prio}] is in "
                f"{t.status}/ but its FRONTMATTER says 'status: {claimed}' — "
                f"the folder is the lock, and a header claiming a lock makes "
                f"the ticket look taken to everyone who opens it"
            )

        # DUPLICATE-SLUG: one slug present in two status folders. The folder IS
        # the lock, so a stray copy in working/ is a phantom lock on a ticket that
        # may already be finished -- and it is indistinguishable from a real lock,
        # because every ownership scan reads the folder and there is nothing else
        # to read. Found 2026-08-30 only because a `git mv` refused to overwrite;
        # it had held a Track A lock for four hours after the fix landed, and the
        # stray copy carried no frontmatter, so it answered no question about who
        # held it either.
        #
        # The remedy is CONCATENATE, never delete: that pair was complementary,
        # not identical -- done/ held the ticket, working/ held a 28-line
        # resolution write-up that existed nowhere else. Deleting "the duplicate"
        # would have destroyed the only record of how it was fixed.
        by_slug: dict = {}
        for t in self.tickets:
            by_slug.setdefault(t.slug, []).append(t)
        for slug, ts in sorted(by_slug.items()):
            if len(ts) < 2:
                continue
            problems = 1
            where = ", ".join(sorted(x.status + "/" for x in ts))
            lines.append(
                f"DUPLICATE-SLUG: {slug} exists in {len(ts)} status folders "
                f"({where}) — the folder is the lock, so the copy in the "
                f"earlier folder reads as a live claim on finished work. "
                f"CONCATENATE the copies and keep one; they are usually "
                f"complementary, not identical, so never delete before diffing."
            )

        pending, dead, bookkeeping = self._audit_citations()
        for slug in pending:
            warning_count += 1
            if strict:
                lines.append(
                    f"WARN-PENDING-COMMIT: {slug} still says {PENDING_COMMIT} — "
                    f"run tools/sync.sh to record the sha it landed as"
                )
        for slug, sha in dead:
            warning_count += 1
            if strict:
                lines.append(
                    f"WARN-DEAD-COMMIT: {slug} cites {sha}, which is on no branch of origin/master"
                )
        # Reported one per line WITH the cited subject, because the subject is
        # what a reader judges on — "close the duplicate ..." is a correct
        # citation, "record the shas the resolves landed as" is not. Deliberately
        # not counted as a problem and never repaired; see BOOKKEEPING_SUBJECT.
        for slug, sha, subj in bookkeeping:
            warning_count += 1
            if strict:
                lines.append(
                    f"WARN-BOOKKEEPING-CITATION: {slug} cites {sha} "
                    f"\u2014 {subj!r}. If that commit IS the resolution (a duplicate "
                    f"close, or already fixed elsewhere) this is correct; if the fix "
                    f"landed separately, the citation names the wrong commit. Fix by "
                    f"hand with the ticket open \u2014 do not bulk-match against git log."
                )
        if not strict and (pending or dead):
            if pending:
                lines.append(
                    f"PENDING-COMMIT: {len(pending)} resolved ticket(s) await their landed sha — run: tools/sync.sh"
                )
            if dead:
                lines.append(
                    f"DEAD-COMMIT: {len(dead)} citation(s) name a sha absent from origin/master "
                    f"(historical; --strict lists them)"
                )

        board = PROG / "BOARD.md"
        if not board.exists():
            lines.append("NO-BOARD: devdocs/progress/BOARD.md missing — run: tools/progress.sh board-md")
            problems = 1
        elif board.read_text(encoding="utf-8") != self.render_board_md():
            lines.append("STALE-BOARD: devdocs/progress/BOARD.md out of date — run: tools/progress.sh board-md")
            problems = 1
        # The split-out archives are generated from the same tree, so they go
        # stale the same way and need the same guard — otherwise BOARD.md's
        # pointer silently leads to a table from an older board.
        brief = PROG / "BOARD-brief.md"
        if not brief.exists():
            lines.append("NO-BOARD: devdocs/progress/BOARD-brief.md missing — run: tools/progress.sh board-md")
            problems = 1
        elif brief.read_text(encoding="utf-8") != self.render_brief_md():
            lines.append("STALE-BOARD: devdocs/progress/BOARD-brief.md out of date — run: tools/progress.sh board-md")
            problems = 1
        for st in ARCHIVED_STATUSES:
            arch = PROG / f"BOARD-{st}.md"
            if not arch.exists():
                lines.append(f"NO-BOARD: devdocs/progress/BOARD-{st}.md missing — run: tools/progress.sh board-md")
                problems = 1
            elif arch.read_text(encoding="utf-8") != self.render_archive_md(st):
                lines.append(f"STALE-BOARD: devdocs/progress/BOARD-{st}.md out of date — run: tools/progress.sh board-md")
                problems = 1

        # A PLACEHOLDER IN A TICKET THAT WAS NEVER RESOLVED.
        #
        # frankC, 2026-08-30: `sync.sh` fills PENDING-COMMIT only for tickets a
        # push RESOLVES. Park a ticket to unfinished/ after writing a Log line
        # and the literal placeholder stays, with no warning from anything --
        # a different aperture from the wrapped-citation case, same outcome,
        # every tool reporting clean.
        #
        # Deliberately a warning and not a failure: a placeholder in a LIVE
        # ticket is often correct in-flight state (resolve written, push
        # pending). What is wrong is nobody being able to tell those apart, so
        # this names them rather than judging them.
        for t in self.tickets:
            if t.status in ("done", "rejected", "decided"):
                continue
            # MENTION VERSUS USE. A bare substring search returns 2 of 2 FALSE
            # POSITIVES here: the family index DISCUSSES the placeholder, and
            # `bug-t-concurrent-sync-runs-can-squash-two-commits-into-one` is
            # ABOUT it. Fourth instance of that shape in one night -- and I hit
            # it while building the guard, having banked the other three.
            # Keyed on the Log-line form `commit PENDING-COMMIT` that
            # `progress.sh resolve` actually writes, not on the token.
            if not re.search(r"commit\s+\**PENDING-COMMIT", t.text):
                continue
            warning_count += 1
            lines.append(
                f"UNFILLED-PLACEHOLDER: {t.slug} [{t.track} p{t.prio}] is in "
                f"{t.status}/ and still carries a literal PENDING-COMMIT. "
                f"sync.sh fills these only for tickets a push RESOLVES, so a "
                f"ticket parked mid-flight keeps it silently. Fill it by hand "
                f"with the sha the work landed as, or delete the Log line if "
                f"the work did not land"
            )

        # A CITED SHA THAT DOES NOT EXIST.
        #
        # `bug-t-resolve-cites-a-sha-the-rebase-then-rewrites` is why `resolve`
        # takes no sha: it writes PENDING-COMMIT and sync.sh fills in what the
        # commit LANDED as. That guard covers the Log: line, because that is
        # where the TOOL writes. Prose in the body is where PEOPLE write, and
        # it is unguarded -- two lanes did it within one hour on 2026-08-30
        # (`ce3560ecd` for `9b01b1b9b`, `90b4d2b51` for `89ab3d9d4`), each
        # having verified the push by artefact and then typed the pre-rebase
        # sha from their own reflog. `git show` works locally and fails
        # everywhere else, which is the worst possible signature.
        #
        # MEASURED before landing, over every ticket:
        #   4294 hex tokens -> 1306 unresolvable -> 474 "look like shas".
        # That check would have been useless: 12-hex tokens here are mostly
        # BINARY sha256 prefixes from byte-identity comparisons, not commits.
        # Narrowed to git's short-sha width (9-11) AND a commit-ish context
        # word on the same line: 82 live candidates, 7 dangling. Four of those
        # are one ticket that QUOTES squashed-away shas on purpose -- mention
        # versus use again, fifth instance -- so that ticket opts out by
        # marker and the check reports 3.
        #
        # done/ and rejected/ are NOT scanned, and that is the design: 130
        # dangling citations sit there, and rewriting a finished record to
        # tidy a sha falsifies history. The number is worth knowing; the sweep
        # is not worth doing.
        SHORT_SHA = re.compile(r"(?<![0-9a-fA-F])[0-9a-f]{9,11}(?![0-9a-fA-F])")
        SHA_CTX = re.compile(r"land|commit|push|\bsha\b|resolve|bisect|revert", re.I)
        sha_hits: "dict[tuple, int]" = {}  # (ticket, tok) -> first line
        for t in self.tickets:
            if t.status in ("done", "rejected", "decided"):
                continue
            if "DANGLING SHAS BY DESIGN" in t.text:
                continue
            for lineno, line in enumerate(t.text.splitlines(), 1):
                if not SHA_CTX.search(line):
                    continue
                for m in SHORT_SHA.finditer(line):
                    tok = m.group(0)
                    if not (any(c.isdigit() for c in tok) and any(c.isalpha() for c in tok)):
                        continue
                    sha_hits.setdefault((t.slug, tok), (t, lineno))
        if sha_hits:
            # `git cat-file -e` IS NOT THE TEST, and it is the test a careful
            # person reaches for. b4, 2026-08-30: it answered LIVE for both of
            # its dangling citations, because the pre-rebase objects were still
            # in its own object store. The question is not "does this object
            # exist" but "is it reachable from origin/master" -- so build the
            # reachable set once and match short prefixes against it.
            ref = None
            for cand in ("origin/master", "origin/HEAD", "master", "HEAD"):
                r = subprocess.run(["git", "rev-parse", "--verify", "--quiet", cand],
                                   capture_output=True, text=True, cwd=str(ROOT))
                if r.returncode == 0:
                    ref = cand
                    break
            reach = None
            if ref:
                try:
                    r = subprocess.run(["git", "rev-list", ref], capture_output=True,
                                       text=True, cwd=str(ROOT), timeout=120)
                    if r.returncode == 0:
                        reach = {9: set(), 10: set(), 11: set()}
                        for full in r.stdout.split():
                            reach[9].add(full[:9])
                            reach[10].add(full[:10])
                            reach[11].add(full[:11])
                except Exception:
                    reach = None
            if reach is not None:
                for (_slug, tok), (t, lineno) in sha_hits.items():
                    if tok in reach[len(tok)]:
                        continue
                    # NOT on master is not the same as NOWHERE. This repo has
                    # long-lived side branches (origin/wasm), and a ticket that
                    # says "measured at branch `wasm` sha 954b56b53" in the very
                    # line being scanned was reported as a pre-rebase reflog
                    # artefact -- a message that was confidently wrong about a
                    # case the ticket itself explained. The deciding half
                    # (reachable from master?) and the reporting half (what that
                    # means) had drifted apart, which is the defect this file's
                    # own check family exists to catch. So ask git which ref
                    # carries it before saying it is dead. One subprocess per
                    # MISS only -- misses are a handful, and the answer is the
                    # branch name, which is the part a reader actually needs.
                    on_branch = ""
                    try:
                        b = subprocess.run(
                            ["git", "branch", "-r", "--contains", tok],
                            capture_output=True, text=True, cwd=ROOT, timeout=20)
                        if b.returncode == 0 and b.stdout.strip():
                            names = [x.strip() for x in b.stdout.splitlines() if x.strip()]
                            names = [x for x in names if "->" not in x]
                            if names:
                                on_branch = ", ".join(names[:3])
                    except Exception:
                        on_branch = ""
                    if on_branch:
                        warning_count += 1
                        lines.append(
                            f"SIDE-BRANCH-SHA: {t.slug} [{t.track} p{t.prio}] cites "
                            f"`{tok}` at line {lineno}, which is NOT on {ref} but IS "
                            f"on {on_branch}. Usually fine and often deliberate — a "
                            f"measurement taken on a side branch. It is flagged, not "
                            f"failed, because the reader of a ticket cannot tell a "
                            f"side-branch sha from a dead one, and BRANCH PERMISSION "
                            f"IS NOT MERGE PERMISSION: nothing on a side branch is "
                            f"pre-approved for master. Say which branch in the ticket "
                            f"line, or add 'DANGLING SHAS BY DESIGN' to its body"
                        )
                        continue
                    warning_count += 1
                    lines.append(
                        f"DANGLING-SHA: {t.slug} [{t.track} p{t.prio}] cites "
                        f"`{tok}` at line {lineno}, which is on NO remote ref at all, so not "
                        f"reachable from {ref} either. Almost always a PRE-REBASE sha copied from a "
                        f"local reflog after a verified push. Do NOT check it "
                        f"with `git cat-file -e` — that answers LIVE in the "
                        f"author's own tree, because the pre-rebase object is "
                        f"still in the local store, so it is exactly the check "
                        f"that cannot tell these apart. Use `git merge-base "
                        f"--is-ancestor {tok} {ref}`. Re-read the sha from "
                        f"{ref} and correct it in place; a binary sha256 "
                        f"prefix is not a commit and should be written "
                        f"'sha256 `…`' so it reads as one. If the ticket "
                        f"quotes a dead sha ON PURPOSE, add the line "
                        f"'DANGLING SHAS BY DESIGN' to its body"
                    )

        # THE APERTURE, printed with every verdict including a clean one.
        #
        # The stale-edge scan above reads frontmatter. Three instances found on
        # 2026-08-28 alone were in PROSE and no frontmatter query can see them:
        # a stall note heading a queue at p75 whose three clauses had each been
        # false for a week; a body asserting a blocked-by edge that had never
        # existed; and a limit sitting sixty lines above its own withdrawal in
        # the same file. Six instances in one day across four sessions is a
        # rate, not a run of bad luck.
        #
        # WAS "deliberately NOT a second query", on the reasoning that a
        # body-grep for slug mentions "would be mostly noise". Half right, and
        # the wrong half was load-bearing: it is noise over all 376 live
        # tickets (~50 hits, nearly all ordinary citations) and signal over the
        # 35 PARKED ones (10 hits). STALE-PARK above is that second query. The
        # general case remains unscannable — there is still no reliable test
        # for "a paragraph that is no longer true" — so the reach of both is
        # stated in the note: an instrument that does not report its own
        # aperture is how "no findings" and "did not look" come to print the
        # same thing, and a note that says CANNOT is how nobody tries.
        #
        # The prose half is the expensive half: a stale edge is SILENT and
        # merely hides a ticket, while stale prose is BELIEVED — it reads as
        # prior investigation and pre-empts the check that would have caught
        # it.
        lines.append(
            "NOTE stale-edge reads FRONTMATTER; STALE-PARK reads PROSE in "
            "unfinished/, blocked/ and working/ (the last as STALE-PARK-HELD: "
            "tell the holder, never claim it), where a resume condition is "
            "load-bearing. Prose in a RANKED folder is still unchecked — a "
            "clean run means those two apertures are clean, not the family. "
            "Convention that keeps them in sync: prose stating a blocking "
            "relationship must also carry the frontmatter edge, and the commit "
            "that closes a blocker marks its dependents' prose."
        )
        if problems == 0:
            if warning_count == 0:
                lines.append("board OK")
            else:
                lines.append(
                    f"WARNINGS: {warning_count} historical hygiene findings; run tools/progress.sh check --strict for details"
                )
                lines.append("board OK with warnings")
        return problems, "\n".join(lines) + "\n"


def find_ticket(slug: str) -> Path:
    matches = [p for p in PROG.glob(f"*/{slug}.md") if p.name != "BOARD.md"]
    if not matches:
        raise SystemExit(f"no ticket with slug: {slug}")
    if len(matches) > 1:
        msg = "\n".join(str(p) for p in matches)
        raise SystemExit(f"ambiguous slug {slug} — matches:\n{msg}")
    return matches[0]


def git_tracked(path: Path) -> bool:
    return subprocess.run(
        ["git", "ls-files", "--error-unmatch", str(path)],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0


# Folder-name synonyms nobody should be nagged about. `open` in backlog/ and
# `new` in backlog_new/ are what people write and mean exactly the destination,
# so rewriting them would be churn in every move diff for no reader benefit.
_STATUS_SYNONYMS = {"backlog": {"open"}, "backlog_new": {"new"}}


def sync_status_to_folder(path: Path, status: str) -> None:
    """Bring a ticket's SELF-DESCRIBED status into line with the folder it now
    sits in. Updates only fields that already exist -- it never invents a claim
    a ticket was not making.

    Why this belongs in the move rather than in `check`: on 2026-08-30 a park
    commit moved feature-a-typeref-migrate-consumers from working/ to backlog/
    and cleared its owner, correctly and deliberately, while leaving
    `status: working` in its own frontmatter. The act of RELEASING the ticket is
    what made it look held. Every reader is told to open a ticket at HEAD before
    claiming it, so the header saying `working` is read as "someone has this"
    and the ticket is skipped -- by careful readers especially, since the
    careless ones never opened it.

    Both spellings are handled because they drift independently: a prose
    `- **Status:**` bullet and a frontmatter `status:` field are different text
    in different places, and a ticket can carry either, both, or neither.
    """
    text = path.read_text(encoding="utf-8")
    orig = text

    fm = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if fm:
        cur = re.search(r"(?mi)^status:\s*(.*)$", fm.group(1))
        if cur:
            val = cur.group(1).strip().strip('"').lower()
            if val != status and val not in _STATUS_SYNONYMS.get(status, set()):
                block = re.sub(r"(?mi)^status:\s*.*$", f"status: {status}",
                               fm.group(1), count=1)
                text = text.replace(fm.group(0), f"---\n{block}\n---\n", 1)

    def _prose(m: "re.Match[str]") -> str:
        val = m.group(2).strip().lower().rstrip(".,:*")
        if val == status or val in _STATUS_SYNONYMS.get(status, set()):
            return m.group(0)
        return f"{m.group(1)}{status}"

    # Only the bare `- **Status:** word` form. A bullet that continues into a
    # sentence ("unfinished -- agent half done, parked awaiting X") is prose
    # carrying a reason, and silently truncating someone's explanation to one
    # word is a worse outcome than a stale word.
    text = re.sub(r"(?mi)^(\s*-\s*\*\*Status:\*\*\s*)(\w+)\s*$", _prose,
                  text, count=1)

    if text != orig:
        path.write_text(text, encoding="utf-8")


def move_ticket(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if git_tracked(src):
        subprocess.check_call(["git", "mv", str(src), str(dst)], cwd=ROOT)
    else:
        shutil.move(str(src), str(dst))
        subprocess.run(["git", "add", str(dst)], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    sync_status_to_folder(dst, dst.parent.name)


def set_prio_auto(path: Path, value: int) -> None:
    """Write `prio: <value>  # auto` into the ticket's YAML frontmatter: replace
    an existing prio line, else insert into the frontmatter block, else create a
    frontmatter block. The `# auto` tag marks it machine-set so a later run may
    refresh it but a human `prio:` (no tag) is never overwritten."""
    text = path.read_text(encoding="utf-8")
    line = f"prio: {value}  # auto"
    if re.search(r"(?m)^prio:.*$", text):
        text = re.sub(r"(?m)^prio:.*$", line, text, count=1)
    elif text.startswith("---\n"):
        text = "---\n" + line + "\n" + text[4:]
    else:
        text = f"---\n{line}\n---\n\n" + text
    path.write_text(text, encoding="utf-8")


def set_field(path: Path, marker: str, value: str) -> None:
    """Write `<marker>: <value>` in whichever form the ticket already uses.

    Prefers an existing `- **Marker:** ...` bullet; otherwise writes the YAML
    frontmatter key, replacing it, inserting it into the block, or creating a
    block — the same ladder `set_prio_auto` uses.

    The fallback is the bug fix: this used to be a bare `pat.sub()`, so a ticket
    with only YAML frontmatter (no bullet to replace) was written back BYTE FOR
    BYTE UNCHANGED while `claim`/`resolve` still printed success. Owner was
    silently dropped on every modern ticket — `check` then reported NO-OWNER for
    tickets that had been claimed correctly, and on a two-box fleet the claim IS
    the distributed mutex, so a claim that does not stick is two agents doing
    the same work (which happened on 2026-07-31).

    The key is matched only INSIDE the frontmatter block: a `status:` line in
    prose must not be mistaken for the field.
    """
    text = path.read_text(encoding="utf-8")
    pat = re.compile(rf"^(\s*-?\s*\*\*{re.escape(marker)}:\*\*\s*).*$", re.I | re.M)
    text, hits = pat.subn(rf"\g<1>{value}", text, count=1)
    if not hits:
        key = marker.lower()
        line = f"{key}: {value}"
        fm = re.match(r"---\n(.*?)\n---\n", text, re.S)
        if fm and re.search(rf"(?mi)^{re.escape(key)}:.*$", fm.group(1)):
            block = re.sub(rf"(?mi)^{re.escape(key)}:.*$", line, fm.group(1), count=1)
            text = text.replace(fm.group(0), f"---\n{block}\n---\n", 1)
        elif fm:
            text = text.replace(fm.group(0), f"---\n{fm.group(1)}\n{line}\n---\n", 1)
        else:
            text = f"---\n{line}\n---\n\n" + text
    path.write_text(text, encoding="utf-8")


# ---------------------------------------------------------------------------
# Near-neighbour search.
#
# The queue could rank but not SEARCH, so filing a duplicate was the cheapest
# action available to a filer holding a fresh incident: `next` and `ready` hand
# you work, neither tells you the problem is already on the board in someone
# else's words. Two agents filed the same defect four days apart, both at
# prio 65, and nobody noticed for four days — which is the ranking damage, not
# the tidiness one: a problem rediscovered twice is evidence a seam matters, and
# split across two tickets it reads as two ordinary 65s.
#
# Deliberately a REPORT, never a merge. The filer is the only party holding
# enough context to judge a match, so the cost of this is one prompt to them.
# bug-the-queue-makes-filing-a-duplicate-the-path-of-least-resistance

# Buckets that still describe project state. A duplicate can sit in any of them
# — float/ and experimental/ are unranked, not closed, and a ticket parked there
# is exactly the one a filer will not have seen.
OPEN_STATUSES = tuple(st for st in STATUSES
                      if st not in ("done", "decided", "rejected", "done-followup"))

# Words that appear in nearly every ticket and carry no signal about WHICH
# ticket this is. Left short on purpose: IDF already discounts common words, and
# a long hand-maintained list is a second mechanism that drifts from the first.
_STOP = frozenset("""
a an and are as at be been but by can do does for from had has have how i if in
into is it its make makes not of on one only or over so than that the their then
there these they this to under up was were what when where which while who why
will with would you your
bug feature decide fix fixed issue ticket track prio status owner summary
""".split())

_TOK_RE = re.compile(r"[a-z0-9_]+")


def _tokens(text: str) -> set[str]:
    """Content words of a ticket, as a SET.

    A set, not a bag: a ticket that says "variant" thirty times is not thirty
    times more about variants than one that says it twice, and term frequency
    would rank long tickets against each other on verbosity. Slug-shaped words
    are split on their hyphens by the tokenizer, so a filer who types a title
    matches the slug of an existing ticket that spells the same words.
    """
    out = set()
    for w in _TOK_RE.findall(text.lower()):
        if len(w) < 3 or w in _STOP or w.isdigit():
            continue
        out.add(w)
    return out


class Similarity:
    """IDF-weighted Jaccard over ticket token sets.

    IDF is what stops the boilerplate every ticket shares — "measured", "repro",
    "acceptance", "self-host", "gate" — from making every pair look alike. The
    weight of a shared word is how RARE it is on this board, so two tickets that
    both say "PXXVarBinOp" score far above two that both say "compiler".

    IDF-weighted COSINE, and the two callers compare like with like.

    Three metrics were measured against the known duplicate pair that prompted
    this ticket before picking one, because the obvious choices both fail in a
    way that is invisible until you look:

      * Jaccard scored the known pair 0.179 against a median open pair of
        0.039 — fine for ticket-vs-ticket — but a six-word TITLE typed by a
        filer scored under 0.03 against EVERY ticket, since the union is then
        just "the whole ticket" and the query rounds away.
      * Containment (over the smaller side) fixed that and broke worse: a long
        ticket trivially contains a short query, so a title about a Variant
        shift scored 0.86 against `feature-dwarf-debug-info`, which merely
        happened to use the words "static", "arithmetic" and "logical"
        somewhere in its prose.

    Cosine's sqrt(w(a)·w(b)) denominator penalises exactly that length
    asymmetry. And the remaining half of the fix is not in the metric at all:
    `near` compares a filer's title against ticket HEADS (slug + title +
    summary), which are the same KIND of object, while `dupes` compares full
    ticket bodies against each other. Comparing a title to a whole ticket was
    the real mistake; no coefficient rescues it.
    """

    def __init__(self, docs: dict[str, set[str]]) -> None:
        n = max(1, len(docs))
        df: dict[str, int] = {}
        for toks in docs.values():
            for w in toks:
                df[w] = df.get(w, 0) + 1
        # +1 smoothing: a word in every ticket gets a small positive weight
        # rather than zero, so an all-boilerplate pair scores low instead of
        # dividing by nothing.
        self.idf = {w: math.log((n + 1) / (c + 1)) + 0.05 for w, c in df.items()}

    def weight(self, toks: set[str]) -> float:
        return sum(self.idf.get(w, 1.0) for w in toks)

    def score(self, a: set[str], b: set[str]) -> float:
        if not a or not b:
            return 0.0
        inter = self.weight(a & b)
        denom = math.sqrt(self.weight(a) * self.weight(b))
        return inter / denom if denom else 0.0


def _ticket_head(t: "Ticket") -> str:
    """A ticket's own one-line description of itself: slug, title, summary.

    What `near` matches a filer's intended TITLE against, because that is the
    same kind of object — a sentence about what the ticket is. The slug counts
    twice over: it is the most deliberate description anyone wrote, and it is
    hyphen-separated, so the tokenizer turns it back into the words a filer
    would type."""
    return " ".join((t.slug.replace("-", " "), t.fm.get("title", ""), t.summary))


def _ticket_doc(t: "Ticket") -> str:
    """The whole ticket — head plus prose. What `dupes` compares, because two
    tickets can describe one defect in different words and only agree in the
    body (the pair that prompted this names two different runtime hooks in
    their titles and the same seam in their evidence)."""
    return " ".join((_ticket_head(t), t.text))


def _near_rows(board: "Board", toks: set[str], exclude: str, track: str,
               limit: int, floor: float, head_only: bool = True) -> list[tuple[float, "Ticket"]]:
    field = _ticket_head if head_only else _ticket_doc
    docs = {t.slug: _tokens(field(t))
            for t in board.tickets if t.status in OPEN_STATUSES}
    sim = Similarity(docs)
    rows = []
    for t in board.tickets:
        if t.status not in OPEN_STATUSES or t.slug == exclude:
            continue
        if track and not board.track_matches(t.track, track):
            continue
        sc = sim.score(toks, docs[t.slug])
        if sc >= floor:
            rows.append((sc, t))
    rows.sort(key=lambda r: (-r[0], r[1].slug))
    return rows[:limit]


def _fmt_near(rows: list[tuple[float, "Ticket"]]) -> str:
    out = []
    for sc, t in rows:
        out.append("  %4.0f%%  [p %2d] [%s] %s  (%s)\n"
                   % (sc * 100, t.prio, t.track or "?", t.slug, t.status))
        summ = t.summary
        if summ:
            out.append("         %s\n" % (summ[:150] + ("…" if len(summ) > 150 else "")))
    return "".join(out)


def cmd_near(args: argparse.Namespace) -> int:
    """Run this BEFORE writing a new ticket file, with the title you mean to use.

    Takes free text or an existing slug. There is no `file` subcommand to hang
    this off — tickets are created by writing the markdown — so it is a
    deliberate step, and it is cheap enough to be one.
    """
    board = Board()
    query = " ".join(args.text).strip()
    if not query:
        print("near: give the title you are about to file, or an existing slug",
              file=sys.stderr)
        return 2
    exclude = ""
    if query in board.by_slug:
        exclude = query
        toks = _tokens(_ticket_head(board.by_slug[query]))
    else:
        toks = _tokens(query)
    rows = _near_rows(board, toks, exclude, getattr(args, "track", "") or "",
                      args.limit, args.floor)
    if not rows:
        print("near: nothing on the open board resembles that. File it.")
        return 0
    print("near: OPEN tickets that resemble this — read them before filing.")
    print("      A match is not a duplicate; you are the one who can tell.")
    sys.stdout.write(_fmt_near(rows))
    return 0


def cmd_dupes(args: argparse.Namespace) -> int:
    """Every close pair already on the open board.

    The pair that prompted this ticket was found by LUCK — `next` happened to
    hand one agent the second ticket right after it closed the first. Luck does
    not scale to 300 open tickets, so this asks the question over all of them at
    once.
    """
    board = Board()
    track = getattr(args, "track", "") or ""
    open_ts = [t for t in board.tickets
               if t.status in OPEN_STATUSES
               and (not track or board.track_matches(t.track, track))]
    docs = {t.slug: _tokens(_ticket_doc(t)) for t in open_ts}
    # IDF over the WHOLE open board, not just the --track slice: how rare a word
    # is, is a property of the board, and computing it per-slice would make the
    # same pair score differently depending on how you asked.
    sim = Similarity({t.slug: _tokens(_ticket_doc(t))
                      for t in board.tickets if t.status in OPEN_STATUSES})
    pairs = []
    for i in range(len(open_ts)):
        for j in range(i + 1, len(open_ts)):
            a, b = open_ts[i], open_ts[j]
            sc = sim.score(docs[a.slug], docs[b.slug])
            if sc >= args.floor:
                pairs.append((sc, a, b))
    pairs.sort(key=lambda r: (-r[0], r[1].slug, r[2].slug))
    if not pairs:
        print("dupes: no open pair scores at or above %.2f." % args.floor)
        return 0
    print("dupes: %d open pair(s) at or above %.2f, closest first."
          % (len(pairs), args.floor))
    print("       A pair is a QUESTION, not a verdict — read both.")
    for sc, a, b in pairs[:args.limit]:
        print("  %4.0f%%" % (sc * 100))
        print("      [p %2d] [%s] %s  (%s)" % (a.prio, a.track or "?", a.slug, a.status))
        print("      [p %2d] [%s] %s  (%s)" % (b.prio, b.track or "?", b.slug, b.status))
    if len(pairs) > args.limit:
        print("  ... %d more not shown (--limit)" % (len(pairs) - args.limit))
    return 0


def cmd_claim(args: argparse.Namespace) -> int:
    src = find_ticket(args.slug)
    dst = PROG / "working" / f"{args.slug}.md"
    if src == dst:
        print(f"{args.slug} already in working/", file=sys.stderr)
        return 1
    move_ticket(src, dst)
    set_field(dst, "Status", "working")
    set_field(dst, "Owner", args.owner)
    subprocess.run(["git", "add", str(dst)], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"claimed {args.slug} -> working/ (owner: {args.owner}).", file=sys.stderr)
    print(f"staged, not committed. regenerate the board ({Path(sys.argv[0]).name} board-md) and commit the move + edits together.", file=sys.stderr)
    return 0


def cmd_pending(args: argparse.Namespace) -> int:
    """`<path>\t<sha>` per ticket owing a citation — sync.sh's input.

    Exists so "what counts as an unfilled citation" has ONE implementation. It
    was duplicated as a Python substring test and a shell grep literal, the two
    drifted, and neither tool could see that the other disagreed. That
    duplication is the actual defect the ticket names.

    A ticket whose sha cannot be determined prints an empty second field rather
    than being dropped: sync must be able to report it, not silently skip it.
    """
    for bucket in RESOLVED_BUCKETS:
        for path in sorted((PROG / bucket).glob("*.md")):
            try:
                text = path.read_text(encoding="utf-8")
            except OSError:
                continue
            if not PENDING_RE.search(text):
                continue
            print("%s\t%s" % (path.relative_to(ROOT), resolve_commit(path)))
    return 0


def cmd_fill(args: argparse.Namespace) -> int:
    """Fill one ticket's unfilled citations with a landed sha.

    Called by tools/sync.sh in place of the sed pair it used to carry, so that
    "what an unfilled citation looks like" has exactly one implementation as
    well as one definition. Rewrites nothing when there is nothing to fill, so
    it is safe to call on any path.
    """
    path = Path(args.path)
    if not path.is_file():
        print("fill: no such file: %s" % path, file=sys.stderr)
        return 1
    text = path.read_text(encoding="utf-8")
    filled = fill_pending(text, args.sha)
    if filled == text:
        return 0
    path.write_text(filled, encoding="utf-8")
    return 0


def cmd_resolve(args: argparse.Namespace) -> int:
    src = find_ticket(args.slug)
    # A decide- ticket resolves into decided/, not done/: a decision is a
    # reference later work builds on, not "work complete". It unblocks
    # dependents identically (see resolved_slugs), but it stays findable as a
    # decision rather than being buried in the done pile.
    bucket = "decided" if args.slug.startswith("decide-") else "done"
    status = "decided" if bucket == "decided" else "done"
    dst = PROG / bucket / f"{args.slug}.md"
    if src == dst:
        print(f"{args.slug} already in {bucket}/", file=sys.stderr)
        return 1
    move_ticket(src, dst)
    set_field(dst, "Status", status)
    text = dst.read_text(encoding="utf-8")
    if not re.search(r"^## Log", text, re.M):
        text += "\n## Log\n"
    verb = "decided" if bucket == "decided" else "resolved"
    commit = args.commit or PENDING_COMMIT
    text += f"- {_dt.date.today().isoformat()} — {verb}, commit {commit}.\n"
    dst.write_text(text, encoding="utf-8")
    subprocess.run(["git", "add", str(dst)], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"{verb} {args.slug} -> {bucket}/ (commit {commit}).", file=sys.stderr)
    print(f"staged, not committed. regenerate the board ({Path(sys.argv[0]).name} board-md) and commit.", file=sys.stderr)
    if commit == PENDING_COMMIT:
        print(f"{PENDING_COMMIT} will be filled in by tools/sync.sh once the commit lands on origin.", file=sys.stderr)
    # The same question in reverse: this change closed one ticket, does it also
    # close any of these? The pair that prompted this feature was TWO tickets
    # closed by ONE change, and the second was found only because the queue
    # happened to hand it over next. Asking here costs the resolver one glance
    # at the moment they still hold the change in their head.
    try:
        board = Board()
        toks = _tokens(_ticket_head(board.by_slug[args.slug])) if args.slug in board.by_slug else set()
        rows = _near_rows(board, toks, args.slug, "", 5, 0.30) if toks else []
        if rows:
            print("", file=sys.stderr)
            print("near: still-open tickets that resemble the one just closed —", file=sys.stderr)
            print("      does this change also close any of them?", file=sys.stderr)
            sys.stderr.write(_fmt_near(rows))
    except Exception:
        # Advisory only. A resolve must never fail because the adviser did.
        pass
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="progress.sh",
        usage="%(prog)s [next|ready|leverage|autorate|board|board-md|check|all] [--track A|B|C|D|E|F|M|N|O|P|R|S|T|U|W|Z]\n"
        "       %(prog)s autorate [--write] | claim <slug> <owner> | resolve <slug> [<commit>]\n"
        "       %(prog)s near <title or slug> [--track T] [--limit N] [--floor F]\n"
        "       %(prog)s dupes [--track T] [--limit N] [--floor F]",
    )
    sub = p.add_subparsers(dest="cmd")
    for name in ["next", "ready", "leverage", "autorate", "board", "board-md", "check", "all"]:
        sp = sub.add_parser(name)
        sp.add_argument("--track", choices=["A", "B", "C", "D", "E", "F", "M", "N", "O", "P", "R", "S", "T", "U", "W", "Z"], default="")
        sp.add_argument("--strict", action="store_true")
        sp.add_argument("--write", action="store_true")
        # board-md only (the loop gives it to every subcommand the way --strict
        # and --write already are). BOARD.html is gitignored and costs ~87% of
        # board-md's runtime, so a caller that only needs the committed
        # BOARD*.md — tools/sync.sh, which runs this INSIDE its fetch->push
        # race window and stages nothing else — can say so.
        sp.add_argument("--no-html", action="store_true")
    sp = sub.add_parser("claim")
    sp.add_argument("slug")
    sp.add_argument("owner")
    sub.add_parser("pending")
    sp = sub.add_parser("fill")
    sp.add_argument("path")
    sp.add_argument("sha")
    sp = sub.add_parser("near")
    sp.add_argument("text", nargs="+")
    sp.add_argument("--track", default="")
    sp.add_argument("--limit", type=int, default=8)
    sp.add_argument("--floor", type=float, default=0.22)
    sp = sub.add_parser("dupes")
    sp.add_argument("--track", default="")
    sp.add_argument("--limit", type=int, default=20)
    sp.add_argument("--floor", type=float, default=0.30)
    sp = sub.add_parser("resolve")
    sp.add_argument("slug")
    # Optional on purpose: the sha you can name here is the PRE-push one, and a
    # rebase rewrites it. Omit it and sync.sh cites the landed one.
    sp.add_argument("commit", nargs="?", default="")
    if not argv:
        argv = ["all"]
    return p.parse_args(argv)


def main(argv: list[str]) -> int:
    ensure_dirs()
    args = parse_args(argv)
    if args.cmd == "claim":
        return cmd_claim(args)
    if args.cmd == "pending":
        return cmd_pending(args)
    if args.cmd == "fill":
        return cmd_fill(args)
    if args.cmd == "resolve":
        return cmd_resolve(args)
    if args.cmd == "near":
        return cmd_near(args)
    if args.cmd == "dupes":
        return cmd_dupes(args)

    board = Board()
    cmd = args.cmd or "all"
    track = getattr(args, "track", "") or ""
    if cmd == "next":
        sys.stdout.write(board.cmd_next(track))
    elif cmd == "ready":
        sys.stdout.write(board.cmd_ready(track))
    elif cmd == "leverage":
        sys.stdout.write(board.cmd_leverage())
    elif cmd == "autorate":
        sys.stdout.write(board.cmd_autorate(getattr(args, "write", False), track))
    elif cmd == "board":
        sys.stdout.write(board.cmd_board())
    elif cmd == "board-md":
        board.write_board_md()
        print(f"wrote {PROG / 'BOARD.md'}")
        # Measured 2026-08-30 on plexus: board-md is 18-21s, of which ~2.5s is
        # the markdown and the rest is BOARD.html (md_html -> inline ->
        # ~1.9M uncompiled re.sub calls). BOARD.html is gitignored, so a
        # git-facing caller pays 87% for a file it will never stage.
        if not getattr(args, "no_html", False):
            board.write_board_html()
            print(f"wrote {PROG / 'BOARD.html'}")
    elif cmd == "check":
        rc, out = board.check(getattr(args, "strict", False))
        sys.stdout.write(out)
        return rc
    elif cmd == "all":
        sys.stdout.write(board.cmd_board())
        sys.stdout.write("\n")
        sys.stdout.write(board.cmd_next(track))
        sys.stdout.write("\n")
        sys.stdout.write(board.cmd_ready(track))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
