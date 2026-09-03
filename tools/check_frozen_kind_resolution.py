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

THE SECOND RULE: THE RIGHT RESOLVER ON THE WRONG NODE
-----------------------------------------------------
Added 2026-09-03 after the first rule watched two backends ship the defect it
exists to prevent. i386 and riscv32 both wrote `IRStrTkOf(argNode)` -- the
CORRECT resolver, applied to the IR_ARG node instead of to the value node. Rule
one calls that clean, because the spelling it forbids is not there.

It cannot ever be right. IRFrozenKindOfAddr's own header says a frozen string's
ARG node is tagged tyString generically, so a resolver handed one returns the
8-byte default unconditionally -- the same wrong answer as the fenced spelling,
reached by a route the fence could not see. The value node is `IRA[argNode]`,
which is what every backend passes to IREmitNode* one line earlier.

It also could not fail in the DEFAULT mode, where a frozen operand IS tyString:
right answer and failure value collide, so no default-mode test could catch it
either. i386 segfaulted on `Copy`/`Pos` under the flag; riscv32 handed a C
callee a char pointer seven bytes into the buffer.
(bug-a-i386-copy-and-pos-segfault-under-the-byte-prefix-mode, fixed 21544412b.)

This half is a pure name-and-shape check over the backends, so it carries its
own aim assertion: `IRA[argNode]` must still appear in compiler/*.inc, or the
identifier no longer means what the rule assumes and it exits 2 rather than
printing PASS about a convention that has moved.

Verified the way a test written after a fix has to be: run over compiler/*.inc
as of 482b714d0 it names ir_codegen386.inc:4124, :4125 and
ir_codegen_riscv32.inc:3307 -- the three real sites -- and it is silent on the
tree today.

WHAT NEITHER RULE COVERS, AND IT IS THE THIRD FORM OF THE SAME BUG
------------------------------------------------------------------
A guard that is too NARROW rather than wrong: `IntToTypeKind(IRTk[argNode]) =
tyString` deciding WHETHER to convert at all. x86-64 carried that at five sites
and skipped the conversion outright for a tyShortString operand, sending a raw
[len][chars] buffer to a callee as a managed handle (fixed 2026-09-03; `Pos` on
a record field answered 0 for 3). Run over the pre-fix tree this checker calls
ir_codegen.inc CLEAN, because the resolver is not involved -- nothing is.

Deliberately not fenced: `= tyString` is a legitimate test in plenty of places
and telling the two apart is a semantic judgement, not a call-site pattern. The
honest statement is that this guard sees two of the three forms. Widening it to
the third needs a way to recognise the ladder, not a broader regex.
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


def strip_comments_text(text):
    """Blank out Pascal comments across the WHOLE file, keeping line numbers.

    Per-LINE stripping is not enough and the difference is not theoretical: the
    commit that fixed the arg-node defect left a `{ ... }` comment spanning six
    lines whose text says `IRStrTkOf(argNode)` in order to warn the next author
    off it. A line-at-a-time regex cannot see that the line is inside a comment,
    so it would report the warning as the violation. Newlines are preserved so
    reported line numbers stay true.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "{":
            j = text.find("}", i)
            j = n if j < 0 else j + 1
            out.append("".join(ch if ch == "\n" else " " for ch in text[i:j]))
            i = j
        elif text.startswith("(*", i):
            j = text.find("*)", i)
            j = n if j < 0 else j + 2
            out.append("".join(ch if ch == "\n" else " " for ch in text[i:j]))
            i = j
        elif text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif c == "'":
            j = text.find("'", i + 1)
            j = n if j < 0 else j + 1
            out.append(text[i:j])
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


# RULE TWO: the correct resolver applied to the node that cannot answer.
# `argNode` / `argNodeArr[k]` name the IR_ARG node in every backend; the value
# node is IRA[...] of it. Both spellings are matched, and IRA[...] is what makes
# a site clean.
ARG_NODE_MISUSE = re.compile(
    r"\b(IRStrTkOf|IRFrozenKindOfAddr)\s*\(\s*"
    r"(argNode|argNodeArr\s*\[[^\]]*\])\s*\)")


def check_file(path):
    """Return a list of (lineno, fname, kindexpr, why) violations."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    lines = strip_comments_text(text).split("\n")
    bad = []
    for n, line in enumerate(lines):
        m = ARG_NODE_MISUSE.search(line)
        if m:
            bad.append((n + 1, m.group(1), m.group(2),
                        "an IR_ARG node cannot answer; pass IRA[%s]"
                        % m.group(2)))
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

# The line i386 shipped, and riscv32's twin. Rule one calls it clean.
ARG_SELF_TEST = """\
procedure FakeArg;
begin
  EmitLoadStrLen386(1, 0, IRStrTkOf(argNode));
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

    # RULE TWO's own pair, drawn from ITS population -- rule one's controls say
    # nothing about it, and a control from the wrong population certifies a
    # broken instrument. The positive is the exact line i386 shipped; the
    # negative is the line that replaced it.
    for src, want_hit, label in (
            (ARG_SELF_TEST, True, "did NOT flag the arg-node misuse"),
            (ARG_SELF_TEST.replace("IRStrTkOf(argNode)",
                                   "IRStrTkOf(IRA[argNode])"),
             False, "flagged the CORRECT arg-node spelling"),
            # ...and the comment that the fix left behind, which NAMES the bad
            # spelling in prose. If this one is flagged, the comment stripper
            # regressed to per-line and the guard reports its own documentation.
            ("{ never write\n  IRStrTkOf(argNode)\n  here }\n", False,
             "flagged a mention inside a multi-line comment"),
    ):
        with tempfile.NamedTemporaryFile("w", suffix=".inc", delete=False) as fh:
            fh.write(src)
            tmp = fh.name
        try:
            hits = [h for h in check_file(tmp) if "IR_ARG" in h[3]]
        finally:
            os.unlink(tmp)
        if bool(hits) != want_hit:
            print("FAIL self-test (rule two): the checker %s." % label)
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

    # RULE TWO is a NAME check, so assert the name still means what it assumes.
    # If no backend spells `IRA[argNode]` any more, either the convention moved
    # or the arg loops were rewritten, and this rule would then be checking a
    # spelling nobody writes -- a guard that cannot fire, printing PASS.
    if "IRA[argNode]" not in blob:
        print("FAIL: no `IRA[argNode]` anywhere in compiler/*.inc.")
        print("  The arg-node rule assumes `argNode` names the IR_ARG node and")
        print("  `IRA[argNode]` its value. That convention is gone, so the rule")
        print("  can no longer fire. Re-derive it before trusting a PASS.")
        return 2

    violations = []
    for t in targets:
        for (ln, fname, expr, why) in check_file(t):
            violations.append((os.path.relpath(t, root), ln, fname, expr, why))

    if violations:
        print("FAIL: a frozen-string prefix kind read from something that cannot")
        print("      answer -- IntToTypeKind(IRTk[...]), or a resolver handed an")
        print("      IR_ARG node instead of IRA[] of it.\n")
        for (f, ln, fname, expr, why) in violations:
            print("  %s:%d  %s  <- %s" % (f, ln, fname, expr))
            print("      (%s)" % why)
        print("\n  A frozen string is tagged tyString generically; tyString means an")
        print("  8-byte prefix. Under -dPXX_SHORTSTRING it is one byte, so this")
        print("  site reads eight bytes of [len][chars] as a length. It does not")
        print("  crash -- the length mismatch short-circuits and the compare just")
        print("  answers no. Substitute IRStrTkOf(<node>).")
        print("\n  For an IR_ARG line: the arg node is tagged tyString generically,")
        print("  so the resolver returns the 8-byte default every time. Pass the")
        print("  VALUE node -- IRA[argNode] -- the one IREmitNode* was just given.")
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
