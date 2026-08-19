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
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict, deque
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROG = ROOT / "devdocs" / "progress"
STATUSES = [
    "urgent",
    "working",
    "unfinished",
    "blocked",
    "backlog",
    "experimental",
    "rainy-day",
    # Track F parks here. Listed so the folder is LOADED (board, check, blocker
    # resolution see it) — NOT so it is ranked: ready/next read only
    # urgent/working/unfinished/backlog, which is the whole point of the lane.
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
PENDING_RE = re.compile(
    r"^(?:commit:[ \t]+" + PENDING_COMMIT
    + r"|-[ \t].*\bcommit[ \t]+" + PENDING_COMMIT + r")", re.M)
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
        if re.search(r"\bTrack[ -]S\b", decl, re.I) or \
                re.match(r"^(feature|bug|regression|idea|compat)-esp-", self.slug) or \
                re.search(r"-(esp|esp32|xtensa)-", self.slug):
            return "S"
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
        explicit = normalize_track(self.fm.get("track", ""))
        if not explicit:
            _tl = first_bullet_value(self.text, "Track")
            if _tl:
                explicit = normalize_track(_tl.split()[0])
        if re.search(r"\bTrack[ -]M\b", decl, re.I) or \
                (re.search(r"-(windows|win32|wine)-", self.slug)
                 and explicit in ("", "M")):
            return "M"
        # Track O (Optimization: register allocation, opt passes, codegen/heap
        # perf) — a cross-cutting lane surfaced on its own, same decl-line rule as
        # R/T. Each ticket ALSO carries a Track A (compiler internals) or Track B
        # (runtime/RTL) file-ownership tag for collision rules; this only groups
        # the optimization work into one visible lane. `feature-opt-` slug prefix
        # is the optimization sub-tickets (NOT `feature-optimization-levels`, the
        # umbrella, whose next char is 'i' not '-').
        if re.search(r"\bTrack[ -]?O\b", decl, re.I) or \
                self.slug.startswith("feature-opt-"):
            return "O"
        # Track E (Examples/apps: demos, games, GUIs, IDEs, the portable-userland
        # showcase) — apps BUILT WITH pxx, not pxx itself. Work-tag file-owned by
        # Track B (examples/**, lib/**, app dirs); same decl-line rule as O/R/T,
        # plus feature-demo-/idea-demo- slug convenience.
        if re.search(r"\bTrack[ -]?E\b", decl, re.I) or \
                self.slug.startswith("feature-demo-") or \
                self.slug.startswith("idea-demo-"):
            return "E"
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
        self.load()

    def load(self) -> None:
        for st in STATUSES:
            for path in sorted((PROG / st).glob("*.md")):
                if path.name in {"README.md", "BOARD.md"}:
                    continue
                text = path.read_text(encoding="utf-8")
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

    def ready_tickets(self, track_filter: str = "") -> list[Ticket]:
        done = self.resolved_slugs        # done/ OR decided/ satisfies a blocker
        eff = self.effective_prio()
        lev = self.leverage_counts()
        out = []
        for st in ("backlog", "urgent"):
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
            lines.append(f"  [{tag}p{eff[t.slug]:>3}] [{t.track}] {t.slug}{extra}")
        return "\n".join(lines) + "\n"

    def cmd_next(self, track_filter: str = "") -> str:
        """The single top-of-queue ticket to grab — the 'do tickets at will'
        entry point. Prints the winner plus why it's on top."""
        rt = self.ready_tickets(track_filter)
        if not rt:
            scope = f" for Track {track_filter}" if track_filter else ""
            return f"no ready ticket{scope} (all blocked or none in backlog/urgent)\n"
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
        lines = [
            f"== NEXT{(' (Track ' + track_filter + ')') if track_filter else ''} ==",
            f"  {t.slug}   [{t.track}]",
            f"  {why}",
            f"  {t.path.relative_to(ROOT)}",
            f"  claim: tools/progress.sh claim {t.slug} <your-agent-id>",
        ]
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
        for st in ("urgent", "working", "unfinished", "backlog"):
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
            x = re.sub(r"\[\[([A-Za-z0-9_-]+)\]\]", wiki, x)
            x = re.sub(r"`([^`]+)`", r"<code>\1</code>", x)
            x = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", x)
            x = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])", r"<em>\1</em>", x)
            x = re.sub(r"~~([^~]+)~~", r"<del>\1</del>", x)
            x = re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", r'<a href="\2">\1</a>', x)
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
        for st in ("backlog", "urgent"):
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


def move_ticket(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if git_tracked(src):
        subprocess.check_call(["git", "mv", str(src), str(dst)], cwd=ROOT)
    else:
        shutil.move(str(src), str(dst))
        subprocess.run(["git", "add", str(dst)], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


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
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="progress.sh",
        usage="%(prog)s [next|ready|leverage|autorate|board|board-md|check|all] [--track A|B|C|D|E|F|M|N|O|P|R|S|T|U|W|Z]\n"
        "       %(prog)s autorate [--write] | claim <slug> <owner> | resolve <slug> [<commit>]",
    )
    sub = p.add_subparsers(dest="cmd")
    for name in ["next", "ready", "leverage", "autorate", "board", "board-md", "check", "all"]:
        sp = sub.add_parser(name)
        sp.add_argument("--track", choices=["A", "B", "C", "D", "E", "F", "M", "N", "O", "P", "R", "S", "T", "U", "W", "Z"], default="")
        sp.add_argument("--strict", action="store_true")
        sp.add_argument("--write", action="store_true")
    sp = sub.add_parser("claim")
    sp.add_argument("slug")
    sp.add_argument("owner")
    sub.add_parser("pending")
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
    if args.cmd == "resolve":
        return cmd_resolve(args)

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
        board.write_board_html()
        print(f"wrote {PROG / 'BOARD.md'}")
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
