#!/usr/bin/env python3
"""Replay objects for one program of a package, read off gcc's link line.
usage: prog_objs.py PKG PROG
Finds the last `gcc ... -o PROG ...` link (no -c) in $PATHB_WORK/logs/PKG.make.log,
then maps each object on it, and each member of a package-local archive on it
(xedit's lisp/liblisp.a), to $PATHB_WORK/replay/PKG/<path_with_underscores>.c.o.
automake's per-target names (xclock-Clock.o) map to their source (Clock.c).
Prints the objects, space-separated; a miss goes to stderr and exits 1."""
import os, re, shlex, subprocess, sys
B = os.path.realpath(os.environ["PATHB_WORK"])  # make logs hold resolved paths
pkg, prog = sys.argv[1], sys.argv[2]
S, R = f"{B}/src/{pkg}", f"{B}/replay/{pkg}"

link, cwd, stack = None, None, []
srcof = {}   # absolute object path -> absolute source path, from the compile lines
for line in open(f"{B}/logs/{pkg}.make.log", errors="replace").read().replace("\\\n", " ").splitlines():
    m = re.search(r"Entering directory '([^']*)'", line)
    if m: stack.append(m.group(1)); continue
    if "Leaving directory" in line:
        if stack: stack.pop()
        continue
    s = re.sub(r"^libtool: (link|compile): +", "", line.strip())
    s = s.replace("`test -f", "").replace("`", "")
    if not s.startswith("gcc ") and "; gcc " in s:
        s = s[s.index("; gcc ") + 2:]
    if " &&" in s: s = s[:s.index(" &&")]
    if not s.startswith("gcc ") or not stack: continue
    try: a = shlex.split(s)
    except ValueError: continue
    if "-c" in a:
        # automake: `gcc ... -c -o liblisp_a-lisp.o test -f 'lisp/lisp.c' || echo './'lisp/lisp.c`
        if "-o" in a:
            o = a[a.index("-o") + 1]
            srcs = [x for x in a if x.endswith(".c")]
            if srcs:
                srcof[os.path.normpath(os.path.join(stack[-1], o))] = \
                    os.path.normpath(os.path.join(stack[-1], srcs[-1].lstrip("'")))
        continue
    if "-o" in a and a[a.index("-o") + 1] == prog:
        link, cwd = a, stack[-1]
if not link:
    sys.exit(f"prog_objs: no link of {prog} in {pkg}.make.log")

def replay_for(objpath):
    """objpath is absolute; its source is the same path with .c."""
    d, base = os.path.split(objpath)
    stem = base[:-2]
    # the compile line that produced it says which source it is
    hits = [src for o, src in srcof.items() if o == objpath] or \
           [src for o, src in srcof.items() if os.path.basename(o) == base]
    if len(set(hits)) == 1:
        rel = os.path.relpath(hits[0], S)
        o = f"{R}/{re.sub(r'[^A-Za-z0-9_.]', '_', rel)}.o"
        if os.path.exists(o): return o
    cands = (stem, stem.split("-", 1)[-1])            # xclock-Clock -> Clock
    for cand in cands:
        rel = os.path.relpath(os.path.join(d, cand + ".c"), S)
        o = f"{R}/{re.sub(r'[^A-Za-z0-9_.]', '_', rel)}.o"
        if os.path.exists(o): return o
    # an archive built from another directory (xedit's libre.a member
    # libre_a-re.o is lisp/re/re.c): the one replay object with that stem
    for cand in cands:
        hits = [f for f in os.listdir(R) if f.endswith(f"_{cand}.c.o")]
        if len(hits) == 1: return f"{R}/{hits[0]}"
    return None

out, bad = [], 0
# -lNAME found in a package-local -L directory is that directory's libNAME.a
# (xedit links its Lisp interpreter as `-L. -lre -llisp -lmp`)
ldirs = [os.path.normpath(os.path.join(cwd, x[2:])) for x in link[1:] if x.startswith("-L")]
args = []
for x in link[1:]:
    if x.startswith("-l"):
        hit = next((f"{d}/lib{x[2:]}.a" for d in ldirs
                    if d.startswith(S) and os.path.exists(f"{d}/lib{x[2:]}.a")), None)
        if hit: args.append(hit)
    else:
        args.append(x)
for x in args:
    p = os.path.normpath(os.path.join(cwd, x))
    if x.endswith(".o"):
        o = replay_for(p)
    elif x.endswith(".a") and p.startswith(S + "/"):
        for m in subprocess.run(["ar", "t", p], capture_output=True, text=True, check=True).stdout.split():
            o = replay_for(os.path.join(os.path.dirname(p), m))
            if o is None:
                sys.stderr.write(f"prog_objs: {prog}: no replay object for {x}({m})\n"); bad = 1
            elif o not in out:
                out.append(o)
        continue
    else:
        continue
    if o is None:
        sys.stderr.write(f"prog_objs: {prog}: no replay object for {x}\n"); bad = 1
    elif o not in out:
        out.append(o)
print(" ".join(out))
sys.exit(bad)
