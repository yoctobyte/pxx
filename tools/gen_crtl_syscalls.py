#!/usr/bin/env python3
"""crtl's <sys/syscall.h> arms, from the measured syscall maps.

Supersedes tools/gen_crtl_arm32_syscalls.py, which did one arch. Two modes,
and which one an arch gets is a fact about where its table CAME FROM:

  EMIT    the arch has no kernel header on this box, so the map IS the table.
          arm32 and xtensa.
  VERIFY  the arch's arm was generated from this box's kernel headers, so the
          map is a SECOND INSTRUMENT and its job is to disagree. x86_64, i386,
          aarch64, riscv32. Nothing is written; a disagreement is reported.

VERIFY IS THE MORE VALUABLE HALF AND IT IS WHY THIS TOOL EXISTS RATHER THAN A
SECOND COPY OF THE arm32 ONE. A kernel header and a qemu -strace sweep fail in
completely different ways -- one is a transcription of a table, the other is an
observation of a running emulator -- so agreement between them is corroboration
in a way that two runs of either alone can never be. Measured 2026-09-04 over
5 maps: i386 395/395, aarch64 277/277, arm32 369/369 agree, and riscv32
disagrees on exactly 9 rows, all of them the asm-generic __NR3264_ slots (see
RISCV32 below). That 9 is a finding, not a defect in either instrument.

RISCV32 AND THE NINE. asm-generic gives one NUMBER to a slot and lets the word
size pick which syscall sits in it, so on rv32 number 43 is sys_statfs64, 62 is
sys_llseek, 222 is sys_mmap2. The header calls them statfs, lseek and mmap
because those are the SLOT names and they are what the kernel's own
asm-generic/unistd.h spells -- but llseek and mmap2 do not take the arguments
lseek and mmap take, so a caller who reads the name and writes the obvious call
gets a wrong-shaped one that still runs. lib/crtl/src/sys/statfs.c already
carries a riscv32 arm for exactly this. The others are unused by crtl today;
the header now says so beside them, because the trap is the NAME and a
generator cannot fix a name the kernel chose.

WHAT THESE MAPS ARE AN ORACLE ABOUT: qemu, not a kernel on real hardware. Every
cross-target test in this tree runs under qemu, so they are right for the whole
population that exercises them, and a first run on hardware is where they would
be falsified. That sentence is stamped into every block this tool writes.

CONTROLS, asserted here and not only in the map's own generator -- a consumer
that trusts its input has no guard at all:

  * three CONSECUTIVE, DISTINCT names. read+write alone cannot catch a constant
    shift within a family: adjacent numbers in one family answer alike, which
    is how a behavioural control failed to fail while the arm32 arm was being
    built (readv 145 / writev 146 both answer EBADF). The triple is per-arch
    because the tables are not related -- 3/4/5 on arm32 and i386, 11/12/13 on
    xtensa, 63/64/56 on the asm-generic pair.
  * rows AUDITED BEHAVIOURALLY for this arch, as a regression test against the
    extractor bugs that have actually occurred. arm32's three (2 fork, 29
    pause, 248 exit_group) were all wrong in the first map it produced.
  * NO DUPLICATE NAMES. A property of the OUTPUT, and the one that caught those
    two arm32 misnamings when five input-side controls had all passed. It is
    also what caught riscv32 259 taking the probe's own exit_group name.
  * a floor on the row count, so a truncated map cannot quietly emit a short
    header.

Refuses to write anything if any control fails, and demonstrating both refusal
paths on an injected fault is part of using it.

'?' ROWS ARE PRINTED INTO THE HEADER AS COMMENTS, NOT SKIPPED. A skipped row
leaves an absent SYS_* whose consumer silently takes an ENOSYS arm -- the same
shape as the silent-zero class this runtime has been closing all week. ABSENT,
?noreturn, ?unnamed and ?silent are four different statements and only ABSENT
means nothing is at that number; the header now carries the other three where
they occur, so a missing name has a visible reason next to it.

THE TABLE IS PARTIAL, ALWAYS. An absent SYS_* stays a COMPILE ERROR, which is
this header's existing contract and the right answer: a program that names one
is told, rather than handed a number somebody inferred.
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAPS = ROOT / "devdocs/dev/syscall-maps"
HDR = ROOT / "lib/crtl/include/sys/syscall.h"

# name -> (mode, #if line that opens the arm, consecutive distinct triple,
#          behaviourally audited rows, row-count floor)
ARCHES = {
    "arm32": dict(
        mode="emit", begin="#elif defined(__arm__)",
        triple=[(3, "read"), (4, "write"), (5, "open")],
        audited=[(2, "fork"), (29, "pause"), (248, "exit_group")],
        floor=300,
        blurb="arm32 EABI"),
    "xtensa": dict(
        mode="emit", begin="#else",
        triple=[(11, "dup2"), (12, "read"), (13, "write")],
        audited=[],          # filled in by the behavioural audit below
        floor=250,
        blurb="xtensa-linux",
        caveat=[
            "NOTHING CAN EXERCISE THIS TABLE TODAY, AND THAT IS WHY IT SAYS SO HERE.",
            "pxx cannot build a C program for xtensa at all -- cparser.inc:11666",
            "answers `C program entry stub not implemented for this target yet',",
            "with or without --platform=posix -- and `--emit-obj --target=xtensa'",
            "on a C source dies earlier still, in the backend, on crtl's own",
            "ctype.c: `call0 target 56674 is not 4-aligned'. So every number below",
            "is CORRECT BY THE SAME METHOD AS THE arm32 ARM AND VERIFIED BY NONE OF",
            "THE SAME EVIDENCE: arm32's was confirmed by running the ten-row crtl",
            "census under qemu-arm and matching i386 row for row, and that census",
            "cannot be built for xtensa. Do not read the presence of this table as",
            "the target working. Whoever lands the entry stub should run",
            "test/c_crtl_syscall_guarded_bodies.c against i386 in the same commit;",
            "that is the check this arm is waiting for.",
        ]),
    "i386": dict(mode="verify", begin="#elif defined(__i386__)"),
    "aarch64": dict(mode="verify", begin="#elif defined(__aarch64__) || defined(__riscv)"),
    "riscv32": dict(
        mode="verify", begin="#elif defined(__aarch64__) || defined(__riscv)",
        # The asm-generic __NR3264_ slots: ONE number, and the word size picks
        # which syscall sits in it. The header spells the SLOT name because
        # that is what asm-generic/unistd.h spells; on rv32 the number reaches
        # the 64-bit-offset variant, whose arguments are not the same. This set
        # is listed so a NEW disagreement is a failure and these nine are not.
        # Shrinking or growing it is the finding, either way.
        expect_differ={
            25: ("fcntl", "fcntl64"), 43: ("statfs", "statfs64"),
            44: ("fstatfs", "fstatfs64"), 45: ("truncate", "truncate64"),
            46: ("ftruncate", "ftruncate64"), 62: ("lseek", "llseek"),
            71: ("sendfile", "sendfile64"), 222: ("mmap", "mmap2"),
            223: ("fadvise64", "fadvise64_64"),
        },
        # Newer than the asm-generic/unistd.h this box ships.
        expect_absent={258: "riscv_hwprobe"}),
}

# x86_64 HAS NO MAP AND DOES NOT NEED ONE. It is the host: its arm comes from
# this box's own asm/unistd_64.h, and every native test in the tree exercises
# it directly rather than through an emulator. Sweeping it would measure the
# same kernel the header was copied from -- one instrument, read twice.


def read_map(arch):
    """(named rows, marker rows). A marker row has a '?' name: assigned, but
    this instrument cannot name it. It is NOT an absent number."""
    named, markers = [], []
    for line in (MAPS / (arch + ".txt")).read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        f = line.split()
        if not re.fullmatch(r"[0-9]+", f[0]):
            continue
        (markers if f[1].startswith("?") else named).append((int(f[0]), f[1]))
    return sorted(named), sorted(markers)


def stamp(arch):
    out = []
    for line in (MAPS / (arch + ".txt")).read_text().splitlines():
        if line.startswith("# range:") or line.startswith("# compiler:"):
            out.append("   " + line[2:])
    return out


def header_arms():
    """Every arm of the live header, as {arm-opening-line: {name: number}}."""
    arms, cur = {}, None
    for line in HDR.read_text().splitlines():
        if line.startswith("#if defined(__x86_64__)") or line.startswith("#elif defined("):
            cur = line
            arms.setdefault(cur, {})
            continue
        if line.startswith("#else"):
            cur = None
            continue
        if cur is not None:
            m = re.match(r"#\s*define\s+__NR_(\w+)\s+(\d+)\s*$", line)
            if m:
                arms[cur][m.group(1)] = int(m.group(2))
    return arms


def check(arch, named, cfg):
    by_num = dict(named)
    names = [n for _, n in named]
    bad = []
    if len(named) < cfg["floor"]:
        bad.append("only %d rows, floor is %d" % (len(named), cfg["floor"]))
    for num, want in cfg["triple"] + cfg["audited"]:
        got = by_num.get(num)
        if got != want:
            bad.append("control row %d: expected %s, map says %r" % (num, want, got))
    tn = [n for _, n in cfg["triple"]]
    if len(set(tn)) != 3:
        bad.append("the consecutive triple is not distinct")
    tnum = sorted(n for n, _ in cfg["triple"])
    if tnum != list(range(tnum[0], tnum[0] + 3)):
        bad.append("the triple is not consecutive: %r" % (tnum,))
    dups = {n for n in names if names.count(n) > 1}
    if dups:
        bad.append("duplicate name(s): " + ", ".join(sorted(dups)))
    return bad


def block(arch, named, markers, cfg):
    out = [cfg["begin"],
           "/* %s. NOT from a kernel header -- there is none on this box for this" % cfg["blurb"],
           "   target -- but MEASURED, by tools/qemu_syscall_map.sh, and emitted here by",
           "   tools/gen_crtl_syscalls.py from devdocs/dev/syscall-maps/%s.txt." % arch,
           "   Do not hand-edit: regenerate.",
           "",
           "   IT IS AN ORACLE ABOUT QEMU, not about a kernel on real hardware. Every",
           "   %s test in this tree runs under qemu, so these are right for the" % arch,
           "   whole population that exercises them; a first run on hardware is where",
           "   they would be falsified. Carry that sentence with any number taken out",
           "   of here -- 'measured' on its own overstates it.",
           "",
           "   THE TABLE IS PARTIAL, DELIBERATELY. It holds what the sweep established.",
           "   A number it never saw is absent, and naming its SYS_* is still a compile",
           "   error -- which is the right answer, and the same one this header gave for",
           "   %s before it had any table at all." % arch,
           ""]
    if cfg.get("caveat"):
        out += ["   " + l for l in cfg["caveat"]] + [""]
    out += stamp(arch) + [" */"]
    if markers:
        out += ["",
                "/* ASSIGNED NUMBERS THIS INSTRUMENT COULD NOT NAME. They are listed rather",
                "   than dropped: a dropped row leaves a SYS_* absent for a reason nobody",
                "   can see, and a consumer then takes its ENOSYS arm silently. ?noreturn",
                "   did not come back (it blocked, or does not return by design); ?unnamed",
                "   returned and qemu printed no name; ?silent returned and qemu printed no",
                "   line at all. Look one up in the kernel's own table, not here."]
        for num, kind in markers:
            out.append("      %-5d %s" % (num, kind))
        out.append(" */")
    out.append("")
    for num, name in named:
        out.append("# define __NR_%-28s %d" % (name, num))
    out.append("")
    for _, name in named:
        out.append("# define SYS_%-29s __NR_%s" % (name, name))
    return "\n".join(out) + "\n"


def verify(arch, cfg):
    exp_differ = cfg.get("expect_differ", {})
    exp_absent = cfg.get("expect_absent", {})
    named, markers = read_map(arch)
    arms = header_arms()
    arm = arms.get(cfg["begin"])
    if arm is None:
        print("  %-8s NO SUCH ARM in the header (%s)" % (arch, cfg["begin"]))
        return 1
    by_num = {v: k for k, v in arm.items()}
    agree_n = sum(1 for n, nm in named if by_num.get(n) == nm)
    absent = [(n, nm) for n, nm in named if n not in by_num]
    differ = [(n, nm, by_num[n]) for n, nm in named if n in by_num and by_num[n] != nm]
    new_differ = [(n, nm, hn) for n, nm, hn in differ
                  if exp_differ.get(n) != (hn, nm)]
    stale = [n for n in exp_differ if n not in {d[0] for d in differ}]
    new_absent = [(n, nm) for n, nm in absent if exp_absent.get(n) != nm]
    print("  %-8s agree=%-4d header-lacks=%-3d differ=%-2d "
          "(%d expected) marker=%d  -> %s"
          % (arch, agree_n, len(absent), len(differ), len(differ) - len(new_differ),
             len(markers), "OK" if not (new_differ or new_absent or stale) else "FAIL"))
    for n, nm, hn in new_differ:
        print("      UNEXPECTED %4d  map=%-22s header=%s" % (n, nm, hn))
    for n, nm in new_absent:
        print("      UNEXPECTED %4d  map=%-22s header has no number there" % (n, nm))
    for n in stale:
        print("      EXPECTED-BUT-GONE %4d  %s: the set is stale, or the map changed"
              % (n, exp_differ[n]))
    return len(new_differ) + len(new_absent) + len(stale)


def emit(arch, cfg):
    named, markers = read_map(arch)
    bad = check(arch, named, cfg)
    if bad:
        print("gen_crtl_syscalls: REFUSING to write %s:" % arch, file=sys.stderr)
        for b in bad:
            print("  " + b, file=sys.stderr)
        return 1
    text = HDR.read_text()
    new = block(arch, named, markers, cfg)
    begin = cfg["begin"]
    if begin == "#else":
        # The final arm of the arch chain. Its #else is the ONLY top-of-line
        # #else in this header and its #endif is the FIRST one after it -- the
        # last #endif in the file belongs to the include guard, and taking that
        # one would delete the chain's terminator along with the arm.
        i = text.index("\n#else\n")
        j = text.index("\n#endif", i)
        text = text[:i + 1] + new + text[j + 1:]
    elif begin in text:
        start = text.index(begin)
        end = text.index("#else\n", start)
        text = text[:start] + new + text[end:]
    else:
        print("gen_crtl_syscalls: no insertion point for %s" % arch, file=sys.stderr)
        return 1
    HDR.write_text(text)
    print("gen_crtl_syscalls: wrote %d %s numbers, %d marker row(s) (controls pass)"
          % (len(named), arch, len(markers)))
    return 0


def main(argv):
    want = argv[1:] or sorted(ARCHES)
    rc = 0
    ver = [a for a in want if ARCHES[a]["mode"] == "verify"]
    if ver:
        print("VERIFY -- the map is a second instrument against a header-derived arm:")
        for a in ver:
            rc |= min(verify(a, ARCHES[a]), 1)
    for a in [a for a in want if ARCHES[a]["mode"] == "emit"]:
        rc |= emit(a, ARCHES[a])
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
