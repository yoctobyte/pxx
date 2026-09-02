#!/usr/bin/env python3
"""Fence one call-site pattern: a frozen-string operand kind fed to a
width-aware normaliser must be resolved with IRStrTkOf / IRFrozenKindOfAddr,
never with IntToTypeKind(IRTk[...]).

WHY THIS EXISTS
---------------
A frozen string is tagged tyString generically in the IR, and tyString means an
8-byte prefix. Under -dPXX_SHORTSTRING the prefix is one byte. So a backend
that asks the NODE for its kind reads 8 for a shortstring, then reads eight
bytes of [len][chars] as a length. IRStrTkOf (ir.inc) exists precisely to
answer the other question, and its own docstring prescribes the remedy:

    "every IntToTypeKind(IRTk[n]) that feeds a prefix width or a char offset
     becomes IRStrTkOf(n) and is correct on all seven backends."

Three normalisers already carry a COMMENT telling the next author this --
aarch64 :2022, riscv32 :503, arm32 :1299 ("or every frozen string looks 8 wide
here"). On 2026-09-02 arm32 violated its own comment at four call sites, and
the result was that comparing two frozen strings answered FALSE on arm32 and
x86-64 under the flag while printing, measuring and indexing correctly. Fixed
in 764dc3a30 / 64f230d12.

That is the shape this fences: prose telling a reader what not to do is not a
mechanism preventing it. The rule is a call-site PATTERN, not a semantic
judgement, so it can simply be checked.

WHY IT FAILS QUIETLY WITHOUT A FENCE
------------------------------------
A wrong prefix width yields a length in the billions; the length mismatch
short-circuits before any character is compared. It never crashes and never
prints garbage -- it answers no. Nothing waiting for a visible symptom sees it.

NOT COVERED, AND DELIBERATELY
-----------------------------
  * wasm32's WasmStrParts takes a NODE and resolves the kind internally, so
    this violation is impossible there by construction. That is the better
    design and the reason it needs no fence: an API that cannot be passed the
    wrong kind beats one that documents which kind to pass.
  * xtensa, i386 and x86-64 have no named normaliser; they inline the
    marshalling. x86-64's EmitStrCmpReg (symtab.inc) takes no type kind at all
    and hardcodes the width, which is a DIFFERENT defect and not a call-site
    pattern -- it cannot be fenced from here.

This checks today's convention. It is deliberately silent on whether asking a
frozen prefix its width should be a per-site decision at all; it stays correct
under either answer.
"""
import re
import sys
import os

# (function name, 1-based position of the type-kind argument)
NORMALISERS = {
    "EmitArm32StringParts": 4,   # (valueReg, srcReg, lenReg, tk, charStackOff)
    "EmitA64StringParts": 4,     # (valueReg, srcReg, lenReg, tk, charStackOff)
    "EmitStrOperandRISCV32": 1,  # (operandTk, slotOff, lenReg, srcReg)
}

# Resolvers that answer the width question correctly.
GOOD = re.compile(r"\b(IRStrTkOf|IRFrozenKindOfAddr)\b")
# The forbidden spelling: the node's generic tag.
BAD = re.compile(r"\bIntToTypeKind\s*\(\s*IRTk\s*\[")

# How far back to look for the assignment that produced a kind variable.
LOOKBACK = 40


def split_args(argstr):
    """Split a Pascal argument list on top-level commas."""
    out, depth, cur = [], 0, ""
    for ch in argstr:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def call_args(line, fname):
    """Extract the argument list text of fname(...) in line, or None."""
    i = line.find(fname + "(")
    if i < 0:
        return None
    j = i + len(fname)
    depth = 0
    for k in range(j, len(line)):
        if line[k] == "(":
            depth += 1
        elif line[k] == ")":
            depth -= 1
            if depth == 0:
                return line[j + 1:k]
    return None


def strip_comments(line):
    """Blank out { ... } comments so a mention inside prose is not a call."""
    return re.sub(r"\{[^}]*\}", " ", line)


def check_file(path):
    """Return a list of (lineno, fname, kindexpr, why) violations."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        raw = fh.readlines()
    lines = [strip_comments(l) for l in raw]
    bad = []
    for n, line in enumerate(lines):
        for fname, pos in NORMALISERS.items():
            args = call_args(line, fname)
            if args is None:
                continue
            parts = split_args(args)
            if len(parts) < pos:
                continue
            kind = parts[pos - 1]
            # An inline expression: judge it directly.
            if "(" in kind or "[" in kind:
                if BAD.search(kind) and not GOOD.search(kind):
                    bad.append((n + 1, fname, kind, "inline expression"))
                continue
            # A bare variable: find the nearest preceding assignment to it.
            var = kind.strip()
            if not re.fullmatch(r"[A-Za-z_]\w*", var):
                continue
            asg = re.compile(r"\b" + re.escape(var) + r"\s*:=\s*(.+?);")
            found = None
            for back in range(n, max(-1, n - LOOKBACK), -1):
                m = asg.search(lines[back])
                if m:
                    found = (back + 1, m.group(1).strip())
                    break
            if not found:
                continue
            src_line, rhs = found
            # A tyPointer fixup (`if tk = tyPointer then tk := tyString;`) is a
            # legitimate reassignment; keep walking past it to the real source.
            hops = 0
            while "tyString" in rhs and "tyPointer" not in rhs and hops < 4:
                nxt = None
                for back in range(src_line - 2, max(-1, src_line - 2 - LOOKBACK), -1):
                    m = asg.search(lines[back])
                    if m:
                        nxt = (back + 1, m.group(1).strip())
                        break
                if not nxt:
                    break
                src_line, rhs = nxt
                hops += 1
            if BAD.search(rhs) and not GOOD.search(rhs):
                bad.append((n + 1, fname, "%s (assigned at :%d as `%s`)"
                            % (var, src_line, rhs), "kind variable"))
    return bad


SELF_TEST = """\
procedure Fake;
begin
  lhsTk := IntToTypeKind(IRTk[left]);
  EmitA64StringParts(0, 1, 2, lhsTk, 48);
end;
"""


def self_test():
    """POSITIVE CONTROL, drawn from the population this guard is about.

    This is the exact shape arm32 shipped and that 764dc3a30 repaired. If the
    checker cannot flag it, the checker is broken and a clean run over the
    real tree means nothing -- a guard that cannot fail prints PASS. So this
    runs on EVERY invocation, not in a separate test nobody executes.
    """
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".inc", delete=False) as fh:
        fh.write(SELF_TEST)
        tmp = fh.name
    try:
        hits = check_file(tmp)
    finally:
        os.unlink(tmp)
    if not hits:
        print("FAIL self-test: the checker did NOT flag a known violation.")
        print("  The shape it missed is the one arm32 shipped (see 764dc3a30).")
        print("  A clean run over the tree therefore proves nothing.")
        return False
    # And a negative control: the corrected spelling must NOT be flagged, or
    # the guard is one that always fires, which is equally useless.
    with tempfile.NamedTemporaryFile("w", suffix=".inc", delete=False) as fh:
        fh.write(SELF_TEST.replace("IntToTypeKind(IRTk[left])", "IRStrTkOf(left)"))
        tmp = fh.name
    try:
        clean = check_file(tmp)
    finally:
        os.unlink(tmp)
    if clean:
        print("FAIL self-test: the checker flagged the CORRECT spelling.")
        print("  It fires unconditionally, so a red run would mean nothing either.")
        return False
    return True


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if not self_test():
        return 2
    targets = []
    cdir = os.path.join(root, "compiler")
    for fn in sorted(os.listdir(cdir)):
        if fn.endswith(".inc"):
            targets.append(os.path.join(cdir, fn))
    if not targets:
        print("FAIL: no compiler/*.inc found -- checked nothing, which is not a pass.")
        return 2

    # Assert the guard is AIMED: the normalisers it fences must actually exist.
    # If one is renamed away, every call site silently disappears and this
    # prints PASS about a file it no longer understands.
    blob = "".join(open(t, encoding="utf-8", errors="replace").read() for t in targets)
    missing = [f for f in NORMALISERS if ("procedure " + f) not in blob
               and ("function " + f) not in blob]
    if missing:
        print("FAIL: normaliser(s) not found in compiler/*.inc: %s" % ", ".join(missing))
        print("  Renamed or removed? Update NORMALISERS -- until then this guard")
        print("  is checking call sites that no longer exist and cannot fail.")
        return 2

    violations = []
    for t in targets:
        for (ln, fname, expr, why) in check_file(t):
            violations.append((os.path.relpath(t, root), ln, fname, expr, why))

    if violations:
        print("FAIL: frozen-string kind resolved with IntToTypeKind(IRTk[...])")
        print("      where IRStrTkOf/IRFrozenKindOfAddr is required.\n")
        for (f, ln, fname, expr, why) in violations:
            print("  %s:%d  %s  <- %s" % (f, ln, fname, expr))
            print("      (%s)" % why)
        print("\n  A frozen string is tagged tyString generically; tyString means an")
        print("  8-byte prefix. Under -dPXX_SHORTSTRING it is one byte, so this")
        print("  site reads eight bytes of [len][chars] as a length. It does not")
        print("  crash -- the length mismatch short-circuits and the compare just")
        print("  answers no. Substitute IRStrTkOf(<node>).")
        return 1

    n = sum(1 for t in targets
            for _ in re.finditer("|".join(NORMALISERS),
                                 open(t, encoding="utf-8", errors="replace").read()))
    print("PASS check_frozen_kind_resolution "
          "(%d normaliser mentions across %d files; self-test and negative "
          "control both passed)" % (n, len(targets)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
