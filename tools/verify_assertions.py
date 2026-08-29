#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Execute a bounded SAMPLE of Makefile assertion sites without running a suite.

Written for the 2476 `expect_same.sh` conversions of 2026-08-29, none of which
any tier had executed. The question a sample CAN answer -- and a sweep is not
needed for -- is whether a MECHANICAL transformation is uniformly broken: a
conversion defect is uniform by construction, so a spread sample settles it in
a minute where a sweep costs the box an hour.

WHAT A PASS HERE DOES NOT MEAN. It is not coverage. It says the transformation
executes on the sites sampled, and nothing whatever about the sites it did not
run or about whether the assertions are RIGHT. Read a green as "no uniform
defect visible", never as "the conversions are verified". The run prints the
count it did not touch for exactly this reason.

THE INVARIANT, and every guard in the devtest serves it:

    NEVER FAIL ON AN INPUT THAT WAS NOT DEMONSTRABLY PRODUCED.

Every FAIL this tool emitted while it was being written was its own aperture,
five times running, each printing an empty `actual` under a confident MISMATCH
banner: a producer sitting before the PREVIOUS assertion; a build line ending
`2>&1` whose redirect was read as its output path; an unexpanded `$(PXX_STABLE)`
running a command named `-Fulib/rtl`; a compile buried inside a quoted
`hyperfine --command-name '...'` that no resolver reaches; and a `printf` that
was the producer being filtered out as bookkeeping. A tool that blames the code
under test for files it failed to build is worse than no tool -- its verdict is
confident, wrong, and generates work. So an input that is absent after setup is
reported as a fact about the sample, not as a defect in the tree.

Run: tools/verify_assertions.py [N] [--all] [--grep PAT]   (exit 0 = no FAILs)
"""
import argparse
import os
import re
import subprocess
import sys

REPO = (os.environ.get("VERIFY_ASSERTIONS_REPO")
        or os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MARKER = "expect_same.sh"

VAR_ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*[:?]?=\s*(.*)$")
VAR_REF = re.compile(r"\$\(([A-Za-z_][A-Za-z0-9_]*)\)")
PATH_TOKEN = re.compile(r"[/\w.+-]+")
REDIR = re.compile(r"^\d*(>>|>|<)")


def join_continuations(lines):
    """Merge backslash-continued recipe lines into one logical command.

    Replayed piecewise, a continued line runs `--warmup 3 ...` as a command of
    its own; the shell error then reads as broken setup. The placeholder is a
    no-op RECIPE line rather than an empty one, so the target grouping below
    still sees a tab and does not read the hole as a target boundary.
    """
    out = list(lines)
    i = 0
    while i < len(out):
        if out[i].rstrip().endswith("\\"):
            merged = out[i].rstrip()[:-1]
            j = i
            while j + 1 < len(out) and out[j].rstrip().endswith("\\"):
                j += 1
                merged += " " + out[j].strip().rstrip("\\")
                out[j] = "\t:"
            out[i] = merged
            i = j
        i += 1
    return out


def make_vars(lines, tmp):
    """The Makefile's own top-level assignments, expanded to a fixpoint.

    Without this, any recipe naming a variable beyond TESTTMP/COMPILER runs
    with the reference left in. Anything still unresolved afterwards is NAMED
    in the skip reason rather than left to surface as a shell error.
    """
    v = {}
    for l in lines:
        if l.startswith(("\t", " ", "#")):
            continue
        m = VAR_ASSIGN.match(l)
        if m:
            v.setdefault(m.group(1), m.group(2).strip())   # first wins, as `?=`
    v["TESTTMP"] = tmp
    for _ in range(8):                       # make is recursive too
        for k, val in list(v.items()):
            v[k] = VAR_REF.sub(lambda mm: v.get(mm.group(1), mm.group(0)), val)
    return v


def expand(line, vars_):
    line = VAR_REF.sub(lambda m: vars_.get(m.group(1), m.group(0)), line)
    line = line.replace("$$", "$").strip()
    # make's RECIPE PREFIXES: @ (silent), - (ignore errors), + (always run).
    # They are make syntax, not part of the command. Left in place, the shell
    # ran `@tools/expect_same.sh ...`, got "command not found", and the
    # recipe's own `|| { echo FAIL; ...; exit 1; }` fired -- so the tool
    # reported a FAIL for a test that passes when actually run. The invariant
    # below did not catch it because a command DID run and DID fail; it just
    # was not the command make would have run.
    while line[:1] in ("@", "-", "+"):
        line = line[1:].lstrip()
    return line


def unexpanded(cmd):
    """-> the first make variable this tool could not resolve, or None."""
    m = VAR_REF.search(cmd)
    return m.group(1) if m else None


def spans(lines):
    """-> [(assertion_index, [candidate_setup_indices])], per target.

    Candidates are every non-assertion recipe line since the TARGET began, not
    since the previous assertion. A target routinely asserts twice against one
    binary (`label`, `label.2`) with the build before the FIRST; resetting at
    each assertion left later ones running a binary that was never built.

    Candidates are not all replayed -- see needed_setup(). Replaying whole
    targets is not an option: the median site has 698 preceding recipe lines,
    and replaying every site would run 2.46 million of them.
    """
    out, setup = [], []
    for i, l in enumerate(lines):
        if not l.startswith("\t"):
            setup = []                       # a new target: nothing carries over
            continue
        if MARKER in l:
            out.append((i, list(setup)))
        else:
            setup.append(i)
    return out


def produced_paths(cmd, tmp):
    """Paths under the scratch root this command WRITES.

    Three forms: an explicit `-o out`, a trailing output argument (the
    `<compiler> [flags] <source> <output>` recipe shape), and a `>`/`>>`
    redirect target. `2>&1` is a descriptor, not a file, and reading it as one
    is how a binary that redirects its build log never got built at all.

    Deliberately narrow otherwise: treating every mentioned path as produced
    would pull in the readers too and replay far more than the assertion needs.
    """
    toks = cmd.split("|")[0].split()
    out, cut = set(), len(toks)
    for i, t in enumerate(toks):
        m = REDIR.match(t)
        if not m:
            continue
        cut = min(cut, i)                    # the argument form ends here
        if m.group(1) in (">", ">>"):
            rest = t[m.end():] or (toks[i + 1] if i + 1 < len(toks) else "")
            if not rest.startswith("&"):
                out.add(rest)
    toks = toks[:cut]
    for i, t in enumerate(toks):
        if t == "-o" and i + 1 < len(toks):
            out.add(toks[i + 1])
    if toks and toks[-1].startswith(tmp + "/"):
        out.add(toks[-1])
    return {o for o in out if o.startswith(tmp + "/")}


def referenced_paths(cmd, tmp):
    return {t for t in PATH_TOKEN.findall(cmd) if t.startswith(tmp + "/")}


def needed_setup(assertion, candidates, lines, vars_, tmp):
    """The MINIMAL setup lines producing what the assertion reads.

    Walks producers backwards to a fixpoint, so a binary built ten assertions
    earlier is found while the nine irrelevant builds between it and here are
    not run. This is what makes a sample cheap enough to be worth taking.

    No "is this line worth running" filter is applied to the result. An earlier
    draft skipped `printf`/`echo`/`stat` lines as bookkeeping and thereby
    dropped every recipe whose producer IS a redirect; selection here is by
    what a line produces, so by construction there is nothing left to filter.
    """
    want = referenced_paths(assertion, tmp)
    chosen, changed = set(), True
    while changed:
        changed = False
        for j in reversed(candidates):
            if j in chosen:
                continue
            cmd = expand(lines[j], vars_)
            if produced_paths(cmd, tmp) & want:
                chosen.add(j)
                want |= referenced_paths(cmd, tmp)
                changed = True
    return sorted(chosen)


def label_of(assertion):
    parts = assertion.split()
    return parts[1] if len(parts) > 1 else "?"


def run_one(lines, idx, candidates, vars_, tmp):
    """-> ('ok'|'FAIL'|'SKIP', label, detail)"""
    assertion = expand(lines[idx], vars_)
    label = label_of(assertion)
    for j in needed_setup(assertion, candidates, lines, vars_, tmp):
        cmd = expand(lines[j], vars_)
        miss = unexpanded(cmd)
        if miss:
            return "SKIP", label, \
                "unresolved make variable $(%s) on line %d" % (miss, j + 1)
        r = subprocess.run(cmd, shell=True, cwd=REPO,
                           capture_output=True, text=True)
        if r.returncode != 0:
            tail = ((r.stderr or r.stdout).strip().splitlines() or ["failed"])[-1]
            return "SKIP", label, "setup line %d: %s" % (j + 1, tail[:70])
    miss = unexpanded(assertion)
    if miss:
        return "SKIP", label, "unresolved make variable $(%s)" % miss
    absent = sorted(q for q in referenced_paths(assertion, tmp)
                    if not os.path.exists(q))
    if absent:                               # THE INVARIANT, see module docstring
        return "SKIP", label, "not produced by any resolved setup line: %s" \
            % ", ".join(os.path.basename(q) for q in absent[:3])
    r = subprocess.run(assertion, shell=True, cwd=REPO,
                       capture_output=True, text=True)
    if r.returncode == 0:
        return "ok", label, ""
    return "FAIL", label, (r.stdout or r.stderr).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("n", nargs="?", type=int, default=12,
                    help="how many sites to sample (spread across the file)")
    ap.add_argument("--all", action="store_true", help="every site (slow)")
    ap.add_argument("--grep", help="only sites whose line matches this")
    a = ap.parse_args()

    tmp = os.environ.get("TESTTMP") or "/tmp/verify-assertions-%d" % os.getpid()
    os.makedirs(tmp, exist_ok=True)

    lines = join_continuations(
        open(os.path.join(REPO, "Makefile"), errors="replace").read().splitlines())
    vars_ = make_vars(lines, tmp)
    sites = spans(lines)
    if a.grep:
        sites = [s for s in sites if re.search(a.grep, lines[s[0]])]
    total = len(sites)
    if not a.all and a.n < total:
        step = max(1, total // a.n)
        sites = sites[::step][:a.n]          # spread, not neighbours: adjacent
                                             # sites share one target and one
                                             # conversion batch
    counts = {"ok": 0, "FAIL": 0, "SKIP": 0}
    print("verify-assertions: %d of %d `%s` sites, TESTTMP=%s"
          % (len(sites), total, MARKER, tmp))
    for idx, setup in sites:
        st, label, detail = run_one(lines, idx, setup, vars_, tmp)
        counts[st] += 1
        print("  %-4s %s%s" % (st, label[:56],
                               ("\n       " + detail.replace("\n", "\n       ")[:400])
                               if detail else ""))
    print("\n  %d executed: %d pass, %d FAIL, %d skipped (setup out of reach)"
          % (len(sites), counts["ok"], counts["FAIL"], counts["SKIP"]))
    if not a.all:
        print("  NOT COVERAGE: %d sites were not run and nothing here speaks "
              "for them." % (total - len(sites)))
    return 1 if counts["FAIL"] else 0


if __name__ == "__main__":
    sys.exit(main())
