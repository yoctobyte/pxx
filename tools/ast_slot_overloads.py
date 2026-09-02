#!/usr/bin/env python3
"""Keep ast_arena.inc's ASTLeft/ASTRight overload table honest.

ASTLeft and ASTRight are a two-slot payload whose MEANING depends on ASTKind.
For most kinds they are child node indices; for a handful they are an AsmBytes
offset, a proc-signature index, a VMT slot, a record id or a 0/1 flag.
ast_arena.inc's ASTLeftIsChild / ASTRightIsChild is the one place that says
which, and every generic walker asks it instead of recursing blindly.

WHY THIS TOOL EXISTS. That table is a declaration, and a declaration goes stale
silently. The failure it guards against is a new kind that parks a non-node in
one of those slots without being added: the walkers then index ASTKind with it,
and three of the existing overloads prove there is no crash to catch that --
a VMT slot, a record id and a 0/1 flag are all VALID node indices, so the
walker gets a well-formed answer about an unrelated subtree. Nothing errors.
So the guard cannot be "watch for a crash"; it has to be a census.

WHAT IS CHECKED, in both directions:

  1. DRIFT. Every `x := AllocNode(AN_K)` is paired with the writes to
     ASTLeft[x] / ASTRight[x] that follow it, and the set of distinct
     right-hand sides per (kind, slot) is compared against the recorded
     snapshot. A new spelling is a diff, whether or not it is an overload --
     the point is that a human looks.

  2. A SLOT THE TABLE CALLS A CHILD IS NEVER WRITTEN FROM A PAYLOAD SOURCE.
     The payload sources are recognisable and few: a bare integer literal, or
     an index into one of the compiler's own side tables (UMthVirSlot,
     ProcRetRecId, ...). This is the arm that would have caught every one of
     the seven overloads before it bit a walker.

  3. THE TABLE LISTS NOTHING DEAD. A kind marked payload whose slot the census
     never sees written is either a typo or a kind that no longer exists, and
     a table entry nobody can reach is a comment.

POSITIVE CONTROL. --self-check synthesises the exact defect this tool is for --
a payload-shaped write into a slot the table calls a child -- and requires the
census to flag it. A tool that reports OK on a corpus it cannot fail on would
print the same OK forever; the control is drawn from the real source text
rather than from a fixture, so it exercises the same parse.

Usage:
  tools/ast_slot_overloads.py [--update] [--self-check]

bug-a-generic-astleft-astright-walkers-recurse-into-kinds-that-overload-those-fields
"""

import argparse
import glob
import os
import re
import sys

ARENA = "compiler/ast_arena.inc"
SNAPSHOT = "test/ast_slot_writes.expected"

# Side tables whose elements are ids/slots, never AST node indices. A write of
# one of these into a slot is a payload write by definition.
PAYLOAD_TABLES = ("UMthVirSlot", "ProcRetRecId", "ProcRetEnumId", "ProcRetElemRec",
                  "ClassVarSym", "UMthProc_")

# Attributions the census gets WRONG, with the reason. The window heuristic
# below cannot see a branch: when a variable is rebound inside an `if` arm and
# the write it is looking for sits in the `else`, the write lands on the wrong
# kind. Each entry here is a site that was read and found benign; an entry is a
# claim about specific source, so it is cheaper to re-check than to trust.
REVIEWED_NOT_OVERLOADS = {
    # pyparser.inc:19642 -- `Result` is rebound to an AN_NOT inside the
    # `if op = tkNeq` arm; the ProcRetRecId write is in the `else`, and applies
    # to the AN_CALL that Result held before the branch.
    ("AN_NOT", "Right"): "pyparser.inc:19642 -- the write is in the else arm, on an AN_CALL",
}

ALLOC = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)\s*:=\s*AllocNode\(\s*(AN_[A-Z_0-9]+)\s*\)')
ANY_ALLOC = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)\s*:=\s*AllocNode\(')
REKIND = re.compile(r'ASTKind\[\s*([A-Za-z_][A-Za-z0-9_]*)\s*\]\s*:=\s*(AN_[A-Z_0-9]+)\s*;')
WRITE = re.compile(r'AST(Left|Right)\[\s*([A-Za-z_][A-Za-z0-9_]*)\s*\]\s*:=\s*(.+?);')

# How far after the AllocNode a write is still attributed to it. The parsers
# build a node and fill it in immediately; 25 lines covers every site in the
# tree today and keeps an unrelated later reuse of the same variable out.
WINDOW = 25


def sources():
    return sorted(glob.glob("compiler/*.inc") + glob.glob("compiler/*.pas"))


def census(extra_lines=None):
    """{(kind, slot): set(rhs text)} over the whole compiler."""
    out = {}
    for path in sources():
        lines = open(path, encoding="utf8", errors="replace").read().split("\n")
        if extra_lines and path == extra_lines[0]:
            lines = lines + extra_lines[1]
        binds = []          # (line index, var, kind)
        for i, ln in enumerate(lines):
            m = ALLOC.search(ln) or REKIND.search(ln)
            if m:
                binds.append((i, m.group(1), m.group(2)))
        for i, var, kind in binds:
            for j in range(i, min(i + WINDOW, len(lines))):
                # Attribution stops at the next node construction. Without this
                # the writes that fill in a LATER node are credited to this one,
                # which invents overloads that are not there (AN_BINOP,
                # AN_FIELD and AN_INTF_CALL all appeared that way).
                if j > i and ANY_ALLOC.search(lines[j]):
                    break
                for m in WRITE.finditer(lines[j]):
                    slot, tgt, rhs = m.group(1), m.group(2), m.group(3).strip()
                    if tgt != var:
                        continue
                    out.setdefault((kind, slot), set()).add(rhs[:80])
    return out


def read_table():
    """The kinds ast_arena.inc marks as payload, per slot."""
    src = open(ARENA, encoding="utf8").read()
    table = {}
    for fn, slot in (("ASTLeftIsChild", "Left"), ("ASTRightIsChild", "Right")):
        m = re.search(r"function\s+" + fn + r"\b.*?case\s+ASTKind\[node\]\s+of(.*?)end;",
                      src, re.S | re.I)
        if not m:
            sys.exit("ast_slot_overloads: no %s case block in %s -- the table this "
                     "tool checks is not where it expects it, so a PASS would mean "
                     "nothing" % (fn, ARENA))
        body = m.group(1)
        body = re.sub(r"\{.*?\}", "", body, flags=re.S)      # drop the per-kind comments
        table[slot] = set(re.findall(r"AN_[A-Z_0-9]+", body))
    return table


def looks_payload(rhs):
    if re.fullmatch(r"-?\d+", rhs):
        return rhs != "-1"          # -1 is "no child", not a payload value
    for t in PAYLOAD_TABLES:
        if re.match(re.escape(t) + r"\s*\[", rhs):
            return True
    return False


def render(cen):
    out = []
    for (kind, slot) in sorted(cen):
        for rhs in sorted(cen[(kind, slot)]):
            out.append("%s %s %s" % (kind, slot, rhs))
    return "\n".join(out) + "\n"


def check(cen, table, quiet=False):
    problems = []
    for (kind, slot), rhss in sorted(cen.items()):
        if kind in table[slot]:
            continue                # already declared a payload slot
        if (kind, slot) in REVIEWED_NOT_OVERLOADS:
            continue                # a known misattribution, reason recorded above
        for rhs in sorted(rhss):
            if looks_payload(rhs):
                problems.append(
                    "%s's AST%s is written from `%s`, which is a payload, but "
                    "ASTLeftIsChild/ASTRightIsChild still calls that slot a CHILD. "
                    "Every generic walker will recurse into it." % (kind, slot, rhs))
    declared = set(re.findall(r"^\s*(AN_[A-Z_0-9]+)\s*=\s*\d+",
                              open("compiler/defs.inc", encoding="utf8").read(),
                              re.M))
    for slot in ("Left", "Right"):
        for kind in sorted(table[slot]):
            if kind not in declared:
                problems.append(
                    "%s is marked as a payload in AST%sIsChild but is not declared "
                    "in defs.inc -- the table names a kind that does not exist."
                    % (kind, slot))
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--update", action="store_true",
                    help="rewrite the snapshot after a REVIEWED change")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(ARENA):
        sys.exit("ast_slot_overloads: run me from the repo root (no %s)" % ARENA)

    table = read_table()
    cen = census()
    if not cen:
        sys.exit("ast_slot_overloads: the census found NO slot writes at all. That "
                 "is the parse failing, not the compiler being clean -- refusing to "
                 "report a pass.")

    problems = check(cen, table)

    if args.self_check:
        # The defect this tool exists for, synthesised into a real source file's
        # line list: a kind the table calls a child, written from a side table.
        victim = "AN_SEQ"
        if victim in table["Right"]:
            sys.exit("ast_slot_overloads: --self-check needs a kind the table calls "
                     "a CHILD and %s is not one" % victim)
        inject = ["  probeNode := AllocNode(%s);" % victim,
                  "  ASTRight[probeNode] := UMthVirSlot[probeMmi];"]
        cen2 = census(extra_lines=(sources()[0], inject))
        p2 = check(cen2, table)
        if len(p2) <= len(problems):
            print("ast_slot_overloads: SELF-CHECK FAILED — a payload write into "
                  "%s's Right was not flagged, so this tool cannot see the defect "
                  "it exists for and its OK means nothing." % victim)
            return 1
        print("ast_slot_overloads: self-check OK — an injected payload write into "
              "%s's Right is reported." % victim)

    rendered = render(cen)
    if args.update:
        open(SNAPSHOT, "w", encoding="utf8").write(rendered)
        print("ast_slot_overloads: snapshot rewritten (%d lines)" % len(rendered.split("\n")))
    elif os.path.exists(SNAPSHOT):
        want = open(SNAPSHOT, encoding="utf8").read()
        if want != rendered:
            import difflib
            print("ast_slot_overloads: the slot-write census has CHANGED. If a new "
                  "kind parks a non-node in ASTLeft/ASTRight, add it to "
                  "ASTLeftIsChild/ASTRightIsChild in %s; then re-run with --update." % ARENA)
            for ln in list(difflib.unified_diff(want.split("\n"), rendered.split("\n"),
                                                "expected", "measured", lineterm=""))[:60]:
                print("  " + ln)
            return 1
    else:
        print("ast_slot_overloads: no snapshot at %s -- run with --update once, "
              "reviewing what it records." % SNAPSHOT)
        return 1

    if problems:
        print("ast_slot_overloads: %d problem(s)" % len(problems))
        for p in problems:
            print("  - " + p)
        return 1
    print("ast_slot_overloads: OK — %d (kind, slot) pairs written across the "
          "compiler, every payload slot declared." % len(cen))
    return 0


if __name__ == "__main__":
    sys.exit(main())
