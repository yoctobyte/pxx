#!/usr/bin/env python3
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
    t = re.sub(r"[^ABCD+/]", "", t)
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
    def track(self) -> str:
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

    def ready_tickets(self, track_filter: str = "") -> list[Ticket]:
        done = self.done_slugs
        out = []
        for st in ("backlog", "urgent"):
            for t in self.by_status[st]:
                if self.track_matches(t.track, track_filter) and all(b in done for b in t.blockers):
                    out.append(t)
        return out

    def cmd_ready(self, track_filter: str = "") -> str:
        if track_filter:
            lines = [f"== READY (Track {track_filter}; no unmet blocker; pull from here) =="]
        else:
            lines = ["== READY (no unmet blocker; pull from here) =="]
        for t in self.ready_tickets(track_filter):
            if t.status == "urgent":
                lines.append(f"  [urgent] [{t.track}] {t.slug}")
            else:
                lines.append(f"  [{t.track}] {t.slug}")
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
        for st in STATUSES:
            tickets = self.by_status[st]
            lines.append(f"## {st} ({len(tickets)})")
            lines.append("")
            if not tickets:
                lines.extend(["_none_", ""])
                continue
            lines.extend(
                [
                    "| Ticket | Track | Type | Summary | Blocked-by |",
                    "| --- | --- | --- | --- | --- |",
                ]
            )
            for t in tickets:
                blockers = ", ".join(t.blockers) if t.blockers else "—"
                lines.append(f"| {t.slug} | {t.track} | {t.type} | {t.summary} | {blockers} |")
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
        usage="%(prog)s [ready|leverage|board|board-md|check|all] [--track A|B]\n"
        "       %(prog)s claim <slug> <owner> | resolve <slug> <commit>",
    )
    sub = p.add_subparsers(dest="cmd")
    for name in ["ready", "leverage", "board", "board-md", "check", "all"]:
        sp = sub.add_parser(name)
        sp.add_argument("--track", choices=["A", "B", "C", "D"], default="")
        sp.add_argument("--strict", action="store_true")
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
    if cmd == "ready":
        sys.stdout.write(board.cmd_ready(track))
    elif cmd == "leverage":
        sys.stdout.write(board.cmd_leverage())
    elif cmd == "board":
        sys.stdout.write(board.cmd_board())
    elif cmd == "board-md":
        board.write_board_md()
        print(f"wrote {PROG / 'BOARD.md'}")
    elif cmd == "check":
        rc, out = board.check(getattr(args, "strict", False))
        sys.stdout.write(out)
        return rc
    elif cmd == "all":
        sys.stdout.write(board.cmd_board())
        sys.stdout.write("\n")
        sys.stdout.write(board.cmd_leverage())
        sys.stdout.write("\n")
        sys.stdout.write(board.cmd_ready(track))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
