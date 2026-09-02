#!/usr/bin/env python3
"""Differential check: pxx's AT&T inline-asm template reader against GNU as.

pxx reads a GNU inline-asm template (AT&T syntax) in compiler/asmatt.inc and
hands each instruction to asmenc.inc's Intel encoder. Two conversions happen on
the way -- operand order reverses, and the b/w/l/q suffix becomes an operand
size -- and both are the kind of mistake that produces a plausible wrong
instruction rather than a failure, so the only credible oracle for "what does
this AT&T text assemble to" is the assembler everyone else uses.

WHAT IS COMPARED, AND WHY NOT THE BYTES. objdump's rendering of each
instruction, not its encoding. Measured 2026-09-02: pxx and gas agree on every
instruction in test/casm_att_template.att and DISAGREE on the bytes of five of
them, because gas picks the `83 /ext ib` sign-extended-imm8 form for a small
immediate where asmenc.inc always emits `81 /ext id` -- `48 83 d6 01` against
`48 81 d6 01 00 00 00`, both `adc $0x1,%rsi`. That is a size opportunity in
asmenc, filed separately; it is not a difference in what the machine does.
Asserting byte-identity would mean replicating every encoding choice gas makes,
which is chasing an implementation rather than the language, and would turn a
correct encoder red. Asserting the disassembly keeps the claim to the one that
matters: pxx encoded THE INSTRUCTION THE TEMPLATE NAMED. A wrong operand order,
a wrong size, a wrong register or a wrong opcode all change that text.

WHY A FENCE. pxx emits the template inside a real function, so the bytes come
wrapped in a prologue and epilogue whose shape is not this test's business and
would make the comparison break whenever codegen changed. The body is therefore
bracketed by a distinctive instruction, assembled by both sides, and located as
a byte substring. The comparison never has to know what a pxx prologue looks
like.

POSITIVE CONTROL. --self-check takes a two-operand instruction from the file
under test, swaps its operands, and requires pxx to encode the swapped form
DIFFERENTLY from the original. A comparison that cannot tell those two apart
would pass every row for the wrong reason, and operand order is precisely what
this reader converts. The control is drawn from the population the question is
about -- the same file, through the same path -- rather than from a synthetic
case that might exercise a different arm.

The run also asserts, before comparing anything, that both bodies are non-empty
and that gas produced one instruction per input line. An empty body compares
equal to an empty body, and a misaligned extraction compares the wrong pairs;
neither would report an error on its own, so both are checked rather than
assumed.

Usage:
  tools/casm_att_diff.py [--pxx PATH] [--cc gcc] [--self-check] FILE.att
where FILE.att is one AT&T instruction per line; blank lines and # comments
are ignored.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

FENCE = "xorq %r15, %r15"


def run(cmd, **kw):
    p = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if p.returncode != 0:
        raise SystemExit(
            "casm_att_diff: command failed (rc=%d): %s\n%s%s"
            % (p.returncode, " ".join(cmd), p.stdout, p.stderr)
        )
    return p.stdout


def read_instructions(path):
    out = []
    with open(path) as fh:
        for line in fh:
            line = line.split("#", 1)[0].strip()
            if line:
                out.append(line)
    if not out:
        raise SystemExit("casm_att_diff: %s holds no instructions" % path)
    return out


def objdump_insns(objdump, path, symbol=None):
    """[(bytes, disassembly text)] for a symbol, or for the whole .text.

    objdump wraps a long instruction onto a continuation line carrying bytes
    and no text; those are folded back into the instruction they belong to, so
    one record really is one instruction.
    """
    text = run([objdump, "-d", path])
    lines = text.splitlines()
    if symbol is not None:
        start = None
        for i, ln in enumerate(lines):
            if ln.endswith("<%s>:" % symbol):
                start = i + 1
                break
        if start is None:
            raise SystemExit(
                "casm_att_diff: %s has no symbol <%s> -- nothing was disassembled,"
                " so any comparison below would have compared nothing" % (path, symbol)
            )
        end = start
        while end < len(lines) and lines[end].strip():
            end += 1
        lines = lines[start:end]
    insns = []
    for ln in lines:
        m = re.match(r"^\s*[0-9a-f]+:\s+((?:[0-9a-f]{2} )+)\s*(.*)$", ln)
        if not m:
            continue
        byts = m.group(1).split()
        t = re.sub(r"\s+", " ", m.group(2).strip())
        if not t and insns:
            insns[-1][0].extend(byts)
        else:
            insns.append([byts, t])
    return [(tuple(b), t) for b, t in insns]


def between_fences(insns, fence_text, what):
    """The instructions strictly between the first and last fence."""
    idx = [i for i, (_, t) in enumerate(insns) if t == fence_text]
    if len(idx) < 2:
        raise SystemExit(
            "casm_att_diff: found %d of 2 fences in the %s disassembly."
            " The extraction is broken, not the encoding -- refusing to compare."
            % (len(idx), what)
        )
    return insns[idx[0] + 1 : idx[-1]]


def assemble_with_gas(cc, objdump, tmp, instructions):
    src = os.path.join(tmp, "oracle.s")
    obj = os.path.join(tmp, "oracle.o")
    with open(src, "w") as fh:
        fh.write("\t.text\n")
        for ins in [FENCE] + instructions + [FENCE]:
            fh.write("\t%s\n" % ins)
    run([cc, "-c", "-x", "assembler", src, "-o", obj])
    return objdump_insns(objdump, obj)


def assemble_with_pxx(pxx, objdump, tmp, instructions, tag="probe"):
    src = os.path.join(tmp, "probe.c")
    obj = os.path.join(tmp, "probe.o")
    with open(src, "w") as fh:
        fh.write("void %s(void) {\n" % tag)
        for ins in [FENCE] + instructions + [FENCE]:
            fh.write('\tasm("%s");\n' % ins.replace("\\", "\\\\").replace('"', '\\"'))
        fh.write("}\n")
        fh.write("int main(void) { %s(); return 0; }\n" % tag)
    run([pxx, "--emit-obj", src, obj])
    return objdump_insns(objdump, obj, symbol=tag)


def fence_text(cc, objdump, tmp):
    """How objdump renders the fence, so both sides can be split on it."""
    src = os.path.join(tmp, "fence.s")
    obj = os.path.join(tmp, "fence.o")
    with open(src, "w") as fh:
        fh.write("\t.text\n\t%s\n" % FENCE)
    run([cc, "-c", "-x", "assembler", src, "-o", obj])
    insns = objdump_insns(objdump, obj)
    if len(insns) != 1:
        raise SystemExit(
            "casm_att_diff: the fence assembled to %d instructions, not 1"
            % len(insns)
        )
    return insns[0][1]


def compare(pxx, cc, objdump, instructions, tmp):
    fence = fence_text(cc, objdump, tmp)
    gas_body = between_fences(
        assemble_with_gas(cc, objdump, tmp, instructions), fence, "gas"
    )
    pxx_body = between_fences(
        assemble_with_pxx(pxx, objdump, tmp, instructions), fence, "pxx"
    )
    # Aim the instrument before reading it: an empty body compares equal to an
    # empty body and would report success for a run that encoded nothing.
    if not gas_body:
        raise SystemExit("casm_att_diff: gas emitted no body between the fences")
    if not pxx_body:
        raise SystemExit("casm_att_diff: pxx emitted no body between the fences")
    if len(gas_body) != len(instructions):
        raise SystemExit(
            "casm_att_diff: gas produced %d instructions for %d input lines --"
            " the extraction is misaligned, so a comparison would be meaningless"
            % (len(gas_body), len(instructions))
        )
    return gas_body, pxx_body


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--pxx", default="./compiler/pascal26")
    ap.add_argument("--cc", default="gcc")
    ap.add_argument("--objdump", default="objdump")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args()

    for tool in (args.cc, args.objdump):
        if shutil.which(tool) is None:
            raise SystemExit(
                "casm_att_diff: %s is not on PATH. This check needs a real"
                " assembler as its oracle; skipping it silently would leave a"
                " guard that cannot fail." % tool
            )
    if not os.path.exists(args.pxx):
        raise SystemExit("casm_att_diff: no compiler at %s" % args.pxx)

    instructions = read_instructions(args.file)

    with tempfile.TemporaryDirectory() as tmp:
        gas_body, pxx_body = compare(
            args.pxx, args.cc, args.objdump, instructions, tmp
        )

    bad = []
    for i, src in enumerate(instructions):
        g = gas_body[i][1] if i < len(gas_body) else "<missing>"
        p = pxx_body[i][1] if i < len(pxx_body) else "<missing>"
        if g != p:
            bad.append((src, g, p, gas_body[i][0], pxx_body[i][0]))
    if len(pxx_body) != len(gas_body):
        print("casm_att_diff: MISMATCH — pxx emitted %d instructions, gas %d"
              % (len(pxx_body), len(gas_body)))
        return 1
    if bad:
        print("casm_att_diff: MISMATCH against %s on %d of %d instructions"
              % (args.cc, len(bad), len(instructions)))
        for src, g, p, gb, pb in bad:
            print("  template : %s" % src)
            print("    gas    : %-32s [%s]" % (g, " ".join(gb)))
            print("    pxx    : %-32s [%s]" % (p, " ".join(pb)))
        return 1

    if args.self_check:
        # A control drawn from the population the question is about: take a
        # two-operand instruction from this very file and swap its operands.
        # The comparison MUST notice. If it does not, the comparison is not
        # reading the quantity it claims to read.
        victim = None
        for ins in instructions:
            head, _, rest = ins.partition(" ")
            if rest.count(",") == 1 and "(" not in rest:
                a, b = [x.strip() for x in rest.split(",")]
                if a != b:
                    victim = "%s %s, %s" % (head, b, a)
                    break
        if victim is None:
            raise SystemExit(
                "casm_att_diff: --self-check found no two-operand instruction to"
                " corrupt, so the positive control never ran"
            )
        original = None
        for ins in instructions:
            head, _, rest = ins.partition(" ")
            if rest.count(",") == 1 and "(" not in rest:
                a, b = [x.strip() for x in rest.split(",")]
                if a != b:
                    original = ins
                    break
        with tempfile.TemporaryDirectory() as tmp:
            _, p_swapped = compare(args.pxx, args.cc, args.objdump, [victim], tmp)
        with tempfile.TemporaryDirectory() as tmp:
            _, p_original = compare(args.pxx, args.cc, args.objdump, [original], tmp)
        if p_swapped[0][1] == p_original[0][1]:
            print("casm_att_diff: SELF-CHECK FAILED — pxx renders `%s` and `%s`"
                  % (original, victim))
            print("  identically, so the comparison above cannot see operand")
            print("  order and its PASS means nothing.")
            return 1
        print("casm_att_diff: self-check OK — swapping the operands of `%s`"
              " does change what pxx encodes" % original)

    print(
        "casm_att_diff: OK — %d instructions, each disassembling exactly as %s"
        " assembles the same AT&T text" % (len(instructions), args.cc)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
