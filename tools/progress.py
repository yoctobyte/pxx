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
    "rainy-day",
    "done-followup",
    "done",
    "rejected",
]


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
    t = re.sub(r"[^ABCDR+/]", "", t)
    t = t.replace("A/B", "A+B").replace("B/A", "A+B")
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

    def track_matches(self, track: str, filt: str) -> bool:
        return not filt or filt in track

    def effective_prio(self) -> dict[str, int]:
        """Priority propagation: a ticket's effective priority is the max of its
        own `prio` and the effective priority of everything it unblocks (its
        dependents, transitively). So a low-rated blocker inherits the priority
        of the high-value work it gates — you rate the goal, the chain follows.
        Only OPEN dependents pull a blocker up (a done/rejected dependent no
        longer needs it). The graph is a DAG (check() enforces); a stray cycle
        is guarded so this can't recurse forever."""
        terminal = {"done", "rejected"}
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
        done = self.done_slugs
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
            if t.status in {"done", "rejected"}:
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

    def write_board_md(self) -> None:
        out = self.render_board_md()
        dest = PROG / "BOARD.md"
        fd, tmp_name = tempfile.mkstemp(prefix="BOARD.", suffix=".md", dir=str(PROG))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(out)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_name, dest)
        finally:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)

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

        commit_re = re.compile(r"commit|[0-9a-f]{7,40}", re.I)
        for t in self.by_status["done"]:
            if not commit_re.search(t.text):
                warning_count += 1
                if strict:
                    lines.append(f"WARN-NO-COMMIT: {t.slug} is in done/ but logs no commit")
                    problems = 1

        board = PROG / "BOARD.md"
        if not board.exists():
            lines.append("NO-BOARD: devdocs/progress/BOARD.md missing — run: tools/progress.sh board-md")
            problems = 1
        elif board.read_text(encoding="utf-8") != self.render_board_md():
            lines.append("STALE-BOARD: devdocs/progress/BOARD.md out of date — run: tools/progress.sh board-md")
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
    text = path.read_text(encoding="utf-8")
    pat = re.compile(rf"^(\s*-?\s*\*\*{re.escape(marker)}:\*\*\s*).*$", re.I | re.M)
    text = pat.sub(rf"\g<1>{value}", text, count=1)
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


def cmd_resolve(args: argparse.Namespace) -> int:
    src = find_ticket(args.slug)
    dst = PROG / "done" / f"{args.slug}.md"
    if src == dst:
        print(f"{args.slug} already in done/", file=sys.stderr)
        return 1
    move_ticket(src, dst)
    set_field(dst, "Status", "done")
    text = dst.read_text(encoding="utf-8")
    if not re.search(r"^## Log", text, re.M):
        text += "\n## Log\n"
    text += f"- {_dt.date.today().isoformat()} — resolved, commit {args.commit}.\n"
    dst.write_text(text, encoding="utf-8")
    subprocess.run(["git", "add", str(dst)], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"resolved {args.slug} -> done/ (commit {args.commit}).", file=sys.stderr)
    print(f"staged, not committed. regenerate the board ({Path(sys.argv[0]).name} board-md) and commit.", file=sys.stderr)
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="progress.sh",
        usage="%(prog)s [next|ready|leverage|autorate|board|board-md|check|all] [--track A|B|C|D|R]\n"
        "       %(prog)s autorate [--write] | claim <slug> <owner> | resolve <slug> <commit>",
    )
    sub = p.add_subparsers(dest="cmd")
    for name in ["next", "ready", "leverage", "autorate", "board", "board-md", "check", "all"]:
        sp = sub.add_parser(name)
        sp.add_argument("--track", choices=["A", "B", "C", "D", "R"], default="")
        sp.add_argument("--strict", action="store_true")
        sp.add_argument("--write", action="store_true")
    sp = sub.add_parser("claim")
    sp.add_argument("slug")
    sp.add_argument("owner")
    sp = sub.add_parser("resolve")
    sp.add_argument("slug")
    sp.add_argument("commit")
    if not argv:
        argv = ["all"]
    return p.parse_args(argv)


def main(argv: list[str]) -> int:
    ensure_dirs()
    args = parse_args(argv)
    if args.cmd == "claim":
        return cmd_claim(args)
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
