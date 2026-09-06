#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Every AST-indexed slot AllocNode initialises must be one CloneAST carries.

`AllocNode` initialises the per-node arrays; `CloneAST` copies them, one
hand-written assignment per field. Nothing related the two lists, and on
2026-09-06 CloneAST was missing TWO of them at once -- `ASTSemId` (the semantic
identity, so a cloned subtree lost its enum-or-sized-boolean meaning) and
`ASTCLongRank` (so a cloned C expression lost its `long` rank).

WHAT KEPT IT INVISIBLE IS THE PART WORTH ENGINEERING AGAINST. CloneAST's own
header said the list was "the full per-node field set AllocNode initialises".
That sentence described an INTENTION and read as a census, so no reader
re-derived it -- for however long both slots were missing. A header claiming
completeness is not a check, and the second omission was found only by taking
the sentence literally and diffing the two functions by hand.

So this derives BOTH SIDES FROM THE SOURCE. A hand-written list of expected
fields would be a third copy of the thing that was already wrong twice, and it
would have passed on 2026-09-06 while both slots were missing.

The price of a missing slot is NOT a stable quantity, which is why this is a
gate check and not a note. While ASTSemId held only an enum index, a dropped
copy cost a missed diagnostic and nobody could build a repro (~20 call sites
tried). Once the same slot carried "integer kind, boolean semantics", the
identical omission became a silent control-flow inversion in cloned subtrees
only. A dormant omission is repriced by every widening of what the field MEANS,
and nothing re-audits the copiers when that happens. This does.

Run: tools/clone_ast_field_sets.py [--verbose]   (exit 0 = pass)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARENA = os.path.join(ROOT, "compiler", "ast_arena.inc")

# Slots deliberately NOT copied by an `ASTx[Result] := ASTx[node]` assignment.
# A named set with a reason each, so the next reader sees a DECISION and not an
# absence -- which is exactly what the missing two looked like.
CARRIED_OTHERWISE = {
    "ASTKind":
        "CloneAST passes ASTKind[node] into AllocNode, so the kind is carried "
        "by the allocation itself rather than by an assignment after it.",
}
# ASTLeft and ASTRight are deliberately NOT in that set even though they are
# special -- they are payload slots, cloned or copied per ASTLeftIsChild /
# ASTRightIsChild rather than assigned plainly. They do not need an exception
# because CloneAST assigns them either way, so the check already passes on
# them; and listing them anyway would EXCUSE a future CloneAST that dropped
# the payload handling entirely. An exception that is not needed is a hole,
# not tidiness.


def _body(src, header_re):
    """The text of one routine: from its header to the `end;` at column 0."""
    m = re.search(header_re, src, re.M)
    if not m:
        return None
    tail = src[m.end():]
    e = re.search(r"\nend;", tail)
    return tail[:e.start()] if e else tail


def alloc_fields(src):
    b = _body(src, r"^function AllocNode\(kind: Integer\): Integer;")
    if b is None:
        return None
    return set(re.findall(r"\b(AST\w+)\[ASTNodeCount\]\s*:=", b))


def clone_fields(src):
    b = _body(src, r"^function CloneAST\(node: Integer\): Integer;")
    if b is None:
        return None
    return set(re.findall(r"\b(AST\w+)\[Result\]\s*:=", b))


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    verbose = "--verbose" in argv
    # --file lets the devtest point this at a scratch arena, so every branch is
    # PROVEN to fire against a tree built to make it fire, rather than inferred
    # from live source that happens to have no instance. A guard whose failure
    # path has never run is a guard that prints OK.
    path = ARENA
    if "--file" in argv:
        path = argv[argv.index("--file") + 1]
    src = open(path).read()

    alloc, clone = alloc_fields(src), clone_fields(src)
    # The third state. A routine this could not find is not a routine with no
    # fields, and reporting 0 missing over an empty set is the failure mode the
    # whole check exists to remove.
    if alloc is None or clone is None:
        which = "AllocNode" if alloc is None else "CloneAST"
        print("clone-ast-field-sets: CANNOT SCOPE — %s not found in %s "
              "(renamed or re-signatured?). Nothing was checked; this is not a "
              "pass." % (which, path))
        return 2
    if not alloc:
        print("clone-ast-field-sets: CANNOT SCOPE — AllocNode's body yielded "
              "no field assignments. Nothing was checked; this is not a pass.")
        return 2

    missing = sorted(alloc - clone - set(CARRIED_OTHERWISE))
    # An exception that no longer names a real AllocNode field is stale, and a
    # stale exemption hides the next gap rather than the one it was written for.
    stale = sorted(set(CARRIED_OTHERWISE) - alloc)

    if verbose:
        print("AllocNode initialises %d slot(s); CloneAST assigns %d; "
              "%d carried otherwise." % (len(alloc), len(clone),
                                         len(CARRIED_OTHERWISE)))
        for f in sorted(alloc):
            if f in clone:
                where = "assigned by CloneAST"
            elif f in CARRIED_OTHERWISE:
                where = "carried otherwise: " + CARRIED_OTHERWISE[f]
            else:
                where = "MISSING"
            print("  %-22s %s" % (f, where))

    rc = 0
    if missing:
        rc = 1
        print("clone-ast-field-sets: %d SLOT(S) AllocNode initialises that "
              "CloneAST does not carry:" % len(missing))
        for f in missing:
            print("  %s" % f)
        print("  A cloned node gets AllocNode's fresh default for these while "
              "the original holds a real value, so the clone is silently a "
              "different node. Add `%s[Result] := %s[node];` to CloneAST — or, "
              "if it genuinely must not be copied, add it to CARRIED_OTHERWISE "
              "in this tool WITH THE REASON, so the next reader sees a decision "
              "and not an absence." % (missing[0], missing[0]))
        print("  bug-t-clonast-and-allocnode-field-sets-are-hand-kept-in-sync")
    if stale:
        rc = 1
        print("clone-ast-field-sets: %d EXCEPTION(S) naming a slot AllocNode "
              "no longer initialises:" % len(stale))
        for f in stale:
            print("  %s" % f)
        print("  Drop it. An exception kept past its subject stops covering "
              "what it was written for and starts hiding whatever takes the "
              "name next.")
    if rc == 0:
        # Counted by MEMBERSHIP, not by subtracting the exception list: an
        # exception for a field CloneAST assigns anyway would otherwise be
        # subtracted from a number it never contributed to, and the total
        # would still add up.
        assigned = sorted(alloc & clone)
        excused = sorted((alloc - clone) & set(CARRIED_OTHERWISE))
        print("clone-ast-field-sets: OK — %d slot(s) AllocNode initialises: "
              "%d assigned by CloneAST, %d carried otherwise (%s), none missing."
              % (len(alloc), len(assigned), len(excused),
                 ", ".join(excused) or "none"))
    return rc


if __name__ == "__main__":
    sys.exit(main())
