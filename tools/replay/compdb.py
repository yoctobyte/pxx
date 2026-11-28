#!/usr/bin/env python3
"""Replay any build that writes a compilation database (meson; `ninja -t
compdb`; CMake's CMAKE_EXPORT_COMPILE_COMMANDS; bear for make) through pxx,
and tally what pxx refuses. Not tied to one package or one unit count: the
unit list is always made fresh from the database the build wrote.

  compdb.py units DB [UNITS]     compile_commands.json -> a unit list
  compdb.py replay UNITS OUTDIR  compile every unit with pxx --emit-obj
  compdb.py census OUTDIR        the tally again, from a replay's logs

A unit list has one line per C compile, tab-separated, no shell quoting:
    DIR<TAB>SRC<TAB>OBJ<TAB>FLAG...
DIR is the directory the compiler ran in, SRC and OBJ as the build named
them (relative to DIR, or absolute). FLAG is every word pxx needs from the
command: -D, -U, -I, -include, -isystem / -iquote / -idirafter (as -I, in
place), -std=, -ffile-prefix-map= and -fmacro-prefix-map= (they change __FILE__).
A launcher (ccache, distcc) in front of the compiler is skipped. Everything else (warnings, -O, -g, -f*, -M*, -pipe, -pthread)
is dropped, and counted: `units` prints each dropped word kind once, so a new
build's surprises show up. C++ and assembler entries are skipped and counted.

replay: OUTDIR/<obj path>.o and .log per unit; OUTDIR/results.tsv
(obj, ok|FAIL, first error); then the census, the errors grouped with the
source location cut off so one gap counts once. Env: PXX (default this
tree's compiler), JOBS (4), PXXFLAGS (extra words, e.g. --threadsafe), and
PXX_NO_HOST_INCLUDE=1 to replay without the host's headers.
Exit status: 0 when every unit compiles.

Tickets: feature-tools-a-generic-compdb-replay (this tool), the wlroots
replay for Panorama, the meson children of the systemd and GNOME umbrellas.
"""
import collections, json, os, re, shlex, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
PXX = os.environ.get("PXX", os.path.join(HERE, "../../compiler/pascal26"))
JOBS = int(os.environ.get("JOBS", "4"))
EXTRA = shlex.split(os.environ.get("PXXFLAGS", ""))
# .S is preprocessed GNU assembly, which pxx --emit-obj takes (docs/reference/cli.md)
C_EXT = (".c", ".S")
SKIP_EXT = (".cc", ".cpp", ".cxx", ".C", ".s", ".m")
LAUNCHERS = {"ccache", "sccache", "distcc", "icecc"}
# flags that take the next word as their argument
TAKES = {"-o", "-MF", "-MT", "-MQ", "-include", "-isystem", "-iquote", "-idirafter",
         "-I", "-D", "-U", "-x", "-arch", "-target", "-imacros", "-Xclang", "--param"}


def entry_args(e):
    if "arguments" in e:
        return list(e["arguments"])
    return shlex.split(e["command"])


def unit_of(e, dropped):
    a = entry_args(e)
    d = e["directory"]
    src = e["file"]
    if src.endswith(SKIP_EXT) or not src.endswith(C_EXT):
        return None
    flags, obj, i = [], e.get("output"), 1
    while i < len(a) and os.path.basename(a[i - 1]) in LAUNCHERS:
        i += 1   # `ccache cc ...`: the compiler is the word after the launcher
    while i < len(a):
        x = a[i]
        nxt = a[i + 1] if i + 1 < len(a) else ""
        if x == "-o":
            obj = nxt; i += 2; continue
        if x in ("-I", "-D", "-U"):
            flags.append(x + nxt); i += 2; continue
        if x.startswith(("-I", "-D", "-U")):
            flags.append(x); i += 1; continue
        if x in ("-isystem", "-iquote", "-idirafter"):
            flags.append("-I" + nxt); i += 2; continue
        if x.startswith(("-isystem", "-iquote", "-idirafter")) and len(x) > len("-isystem"):
            flags.append("-I" + re.sub(r"^-(isystem|iquote|idirafter)", "", x)); i += 1; continue
        if x in ("-include", "-imacros"):
            if x == "-imacros":
                dropped[x] += 1
            else:
                flags += [x, nxt]
            i += 2; continue
        if x.startswith(("-std=", "-ffile-prefix-map=", "-fmacro-prefix-map=")):
            flags.append(x); i += 1; continue
        if x == "-c" or x == src or (not x.startswith("-") and os.path.normpath(os.path.join(d, x)) == os.path.normpath(os.path.join(d, src))):
            i += 1; continue
        if x in TAKES:
            dropped[x] += 1; i += 2; continue
        k = x if not x.startswith("-") else re.sub(r"[=,].*$", "", x)
        k = re.sub(r"^-(W|f|m|O|g)[^ ]*", r"-\1*", k)
        dropped[k] += 1
        i += 1
    if not obj:
        obj = os.path.splitext(os.path.basename(src))[0] + ".o"
    return [d, src, obj] + flags


def cmd_units(db, out):
    dropped, skipped = collections.Counter(), 0
    seen, lines = set(), []
    for e in json.load(open(db)):
        u = unit_of(e, dropped)
        if u is None:
            skipped += 1; continue
        key = os.path.normpath(os.path.join(u[0], u[2]))
        if key in seen:
            continue
        seen.add(key)
        if any("\t" in w or "\n" in w for w in u):
            sys.exit("compdb: a word with a tab or newline: %r" % u)
        lines.append("\t".join(u))
    f = open(out, "w") if out else sys.stdout
    f.write("\n".join(lines) + "\n")
    if out:
        f.close()
    print("compdb: %d C units, %d other entries skipped" % (len(lines), skipped), file=sys.stderr)
    for k, c in sorted(dropped.items()):
        print("compdb:   dropped %-28s x%d" % (k, c), file=sys.stderr)


def obj_path(outdir, u):
    o = os.path.normpath(os.path.join(u[0], u[2]))
    return os.path.join(outdir, "objs", o.lstrip("/"))


def run(outdir, u):
    d, src, _ = u[0], u[1], u[2]
    o = obj_path(outdir, u)
    os.makedirs(os.path.dirname(o), exist_ok=True)
    try:
        r = subprocess.run([PXX, "--emit-obj"] + EXTRA + u[3:] + [src, o], cwd=d,
                           capture_output=True, text=True, errors="replace", timeout=600)
        text, ok = r.stdout + r.stderr, r.returncode == 0
    except subprocess.TimeoutExpired:
        text, ok = "replay: timeout after 600 s\n", False
    open(o + ".log", "w").write(text)
    err = "" if ok else next((l for l in text.splitlines() if "error" in l or "timeout" in l),
                             (text.strip().splitlines() or ["(no output)"])[-1])
    return os.path.relpath(o, os.path.join(outdir, "objs")), ok, err


def norm(e):
    """an error message with its location and names of files cut off, so the
    same gap in many files counts once"""
    e = re.sub(r"^pascal26:\d+: ", "", e)
    e = re.sub(r"\(searched: .*\)", "", e)
    e = re.sub(r"\bline \d+\b", "line N", e)
    return e.strip()


def census(outdir, res):
    ok = sum(1 for _, g, _ in res if g)
    print("replay: %d/%d units compile" % (ok, len(res)))
    for e, c in collections.Counter(norm(e) for _, g, e in res if not g).most_common():
        print("  %4d  %s" % (c, e[:220]))
    return ok == len(res)


def cmd_replay(units, outdir):
    us = [l.rstrip("\n").split("\t") for l in open(units) if l.strip()]
    os.makedirs(outdir, exist_ok=True)
    with ThreadPoolExecutor(JOBS) as ex:
        res = list(ex.map(lambda u: run(outdir, u), us))
    with open(os.path.join(outdir, "results.tsv"), "w") as f:
        for n, g, e in res:
            f.write("%s\t%s\t%s\n" % (n, "ok" if g else "FAIL", e))
    return census(outdir, res)


def cmd_census(outdir):
    res = []
    for l in open(os.path.join(outdir, "results.tsv")):
        n, g, e = (l.rstrip("\n").split("\t") + ["", ""])[:3]
        res.append((n, g == "ok", e))
    return census(outdir, res)


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["units"] and len(a) in (2, 3):
        cmd_units(a[1], a[2] if len(a) == 3 else None)
    elif a[:1] == ["replay"] and len(a) == 3:
        sys.exit(0 if cmd_replay(a[1], a[2]) else 1)
    elif a[:1] == ["census"] and len(a) == 2:
        sys.exit(0 if cmd_census(a[1]) else 1)
    else:
        sys.exit(__doc__)
