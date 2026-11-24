#!/usr/bin/env python3
"""Path B: replay every `gcc -c` of a package's gcc build log through pxx
(--emit-obj, x86-64) and tally the results. Compile only; no link.
usage: replay-cc.py PKG...   (logs in $PATHB_WORK/logs/PKG.make.log)
Env: PXXC, JOBS. Per-file logs in $PATHB_WORK/replay/PKG/."""
import os, re, shlex, subprocess, sys, collections
from concurrent.futures import ThreadPoolExecutor

PXXC = os.environ.get("PXXC", os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../compiler/pascal26"))
JOBS = int(os.environ.get("JOBS", "8"))
B = os.path.realpath(os.environ["PATHB_WORK"])  # make logs hold resolved paths
EXTRA = shlex.split(os.environ.get("PXXFLAGS", ""))

def units(log):
    out, stack = [], []
    for line in open(log, errors="replace").read().replace("\\\n", " ").splitlines():
        m = re.search(r"Entering directory '([^']*)'", line)
        if m: stack.append(m.group(1)); continue
        if "Leaving directory" in line:
            if stack: stack.pop()
            continue
        s = re.sub(r"^libtool: compile: +", "", line.strip())
        s = s.replace("`test -f", "").replace("`", "")
        # automake's depbase form: `depbase=...;\ gcc ... -c -o x.o x.c &&\ mv -f ...`
        if not s.startswith("gcc ") and "; gcc " in s:
            s = s[s.index("; gcc ") + 2:]
        if " &&" in s: s = s[:s.index(" &&")]
        if not s.startswith("gcc ") or not stack: continue
        try: a = shlex.split(s)
        except ValueError: continue
        if "-c" not in a: continue
        flags, src = [], None
        for i, x in enumerate(a[1:], 1):
            if x.startswith(("-I", "-D", "-U")): flags.append(x)
            elif x == "-include": flags += [x, a[i + 1]]
            elif x.endswith(".c") and a[i - 1] != "-o": src = x
        if src and "-fPIC" not in a or src:   # libtool compiles twice (PIC + not); keep one
            out.append((stack[-1], src, flags))
    seen, uniq = set(), []
    for cwd, src, flags in out:
        k = os.path.normpath(os.path.join(cwd, src))
        if k in seen: continue
        seen.add(k); uniq.append((cwd, src, flags))
    return uniq

def run(pkg, i, u):
    cwd, src, flags = u
    d = f"{B}/replay/{pkg}"
    name = re.sub(r"[^A-Za-z0-9_.]", "_", os.path.relpath(os.path.join(cwd, src), f"{B}/src/{pkg}"))
    r = subprocess.run([PXXC, "--emit-obj"] + EXTRA + flags + [src, f"{d}/{name}.o"], cwd=cwd,
                       capture_output=True, text=True, errors="replace", timeout=300)
    open(f"{d}/{name}.log", "w").write(r.stdout + r.stderr)
    err = next((l for l in (r.stdout + r.stderr).splitlines() if "error" in l), "")
    return name, r.returncode == 0, re.sub(r"^pascal26:\d+: ", "", err)

if __name__ == "__main__":
    for pkg in sys.argv[1:]:
        us = units(f"{B}/logs/{pkg}.make.log")
        os.makedirs(f"{B}/replay/{pkg}", exist_ok=True)
        with ThreadPoolExecutor(JOBS) as ex:
            res = list(ex.map(lambda iu: run(pkg, *iu), enumerate(us)))
        ok = sum(1 for _, g, _ in res if g)
        with open(f"{B}/replay/{pkg}/fails.txt", "w") as f:
            for n, g, e in res:
                if not g: f.write(f"{n}\t{e}\n")
        print(f"{pkg}: {ok}/{len(res)} compile")
        for e, c in collections.Counter(e for _, g, e in res if not g).most_common(6):
            print(f"   {c:4d}  {e[:150]}")
        sys.stdout.flush()
