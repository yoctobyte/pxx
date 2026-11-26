#!/usr/bin/env python3
"""mkunits.py TREE RAINYDAY ARCHIVE... : the compile list of an all-pxx rumpnic,
for onsite.sh, on stdout. HOST SIDE (record.sh runs it).

TREE is a gcc rump build (Rainyday's tools/rump-build.sh: cc-commands.log,
netbsd/, obj/, tools/), RAINYDAY a Rainyday checkout (drivers/, include/,
docs/rump-pxx/harness/). ARCHIVE is obj-relative, as drivers/Makefile's
rump-libs prints them. One line per object, in link order, words separated by
single spaces:

    OBJ KIND RENAME DIR SRC ARG...

  OBJ     the object's name in the on-site obj/ directory
  KIND    k  a rump kernel object: --freestanding --system-libs and the two
             harness headers (gcc's predefined macros, no layer), as
             Rainyday's tools/rump-pxx-build.sh compiles them
          s  a .S file of the kernel: the translated arguments only
          h  a hosted object (librumpuser, virtif's host side, rumpnic's own
             files): --threadsafe, the C library's headers
  RENAME  1 if NetBSD's rule renames the object's globals to rumpns_* (gcc's
          member of the archive has rumpns_ names), else 0
  DIR     the directory the compile runs in
  SRC     the source, relative to DIR or absolute

Every path is written with @T@ for TREE and @R@ for RAINYDAY, which onsite.sh
replaces with where it unpacked them. The method is Rainyday's
tools/rump-pxx/{pxxcc,mkarch}.py and tools/rump-pxx-build.sh (ALLPXX=1),
taken over without python, ar, nm or objcopy on the target: the archives are
never made (pxx --link takes the members), and NetBSD's rename is pxx's
--rename-globals.
"""
import os, shlex, subprocess, sys, tempfile

tree, rd = (os.path.realpath(p) for p in sys.argv[1:3])
archives = sys.argv[3:]


def sub(p):
    p = os.path.normpath(p)
    for root, tag in ((tree, "@T@"), (rd, "@R@")):
        if p == root:
            return tag
        if p.startswith(root + "/"):
            return tag + p[len(root):]
    return p


def translate(cwd, argv):
    """gcc argv -> (src, pxx args), as pxxcc.py's translate."""
    args, src, i = [], None, 0
    a = argv[1:]
    while i < len(a):
        x = a[i]
        if x in ("-I", "-D", "-U", "-include", "-imacros", "-isystem", "-o", "-MF", "-MT", "-x"):
            i += 1
            v = a[i]
            if x in ("-I", "-isystem"):
                args.append("-I" + sub(os.path.join(cwd, v)))
            elif x == "-D":
                args.append("-D" + v)
            elif x == "-U":
                args.append("-U" + v)
            elif x in ("-include", "-imacros"):
                args += ["-include", sub(os.path.join(cwd, v))]
        elif x.startswith("-I"):
            args.append("-I" + sub(os.path.join(cwd, x[2:])))
        elif x.startswith("-D") or x.startswith("-U"):
            args.append(x)
        elif x in ("-nostdinc", "-fcommon"):
            args.append(x)
        elif x.startswith("-"):
            pass
        elif x.endswith(".c") or x.endswith(".S"):
            src = os.path.normpath(os.path.join(cwd, x))
        i += 1
    return src, args


# (cwd, output name) -> (cwd, src, args)
outmap = {}
for line in open(os.path.join(tree, "cc-commands.log")):
    line = line.strip()
    if not line.startswith("cd "):
        continue
    cdpart, _, cmd = line.partition(" && ")
    cwd = os.path.normpath(shlex.split(cdpart)[1])
    argv = shlex.split(cmd)
    if "-c" not in argv or "-E" in argv or "-M" in argv or "-MM" in argv:
        continue
    src, args = translate(cwd, argv)
    if src is None:
        continue
    out = None
    for k, x in enumerate(argv):
        if x == "-o" and k + 1 < len(argv):
            out = argv[k + 1]
    if out is None:
        out = os.path.basename(src)[:-2] + ".o"
    outmap.setdefault((cwd, out), (cwd, src, args))

lines = []
shims = os.path.join(rd, "docs/rump-pxx/harness")
kern = ["--freestanding", "--system-libs", "-include", sub(os.path.join(shims, "gcc-predef.h")),
        "-include", sub(os.path.join(shims, "layer-none.h"))]
missing = 0
for ai, a in enumerate(archives):
    gar = os.path.join(tree, "obj", a)
    adir = os.path.normpath(os.path.dirname(gar))
    members = subprocess.run(["ar", "t", gar], capture_output=True, text=True, check=True).stdout.split()
    lib = os.path.basename(a)[:-2]
    for m in members:
        if lib == "librumpnet_virtif" and m.endswith("virtif_user.o"):
            continue                 # its hosted twin is compiled below
        job = outmap.get((adir, m))
        if job is None:
            print("mkunits: no compile for %s in %s" % (m, a), file=sys.stderr)
            missing += 1
            continue
        cwd, src, args = job
        gmem = subprocess.run(["ar", "p", gar, m], capture_output=True, check=True).stdout
        with tempfile.NamedTemporaryFile(suffix=".o") as t:
            t.write(gmem)
            t.flush()
            nm = subprocess.run(["nm", t.name], capture_output=True).stdout.decode()
        rename = 1 if any(l.split()[-1].startswith("rumpns_") for l in nm.splitlines() if l.split()) else 0
        kind = "s" if src.endswith(".S") else "k"
        a_ = (kern if kind == "k" else []) + args
        lines.append(["%02d_%s_%s" % (ai, lib, m), kind, str(rename), sub(cwd), sub(src)] + a_)

inc = sub(os.path.join(tree, "obj/dest.stage/usr/include"))
hosted = [(os.path.join(tree, "netbsd/sys/rump/net/lib/libvirtif/virtif_user.c"),
           ["-I" + inc, "-DVIRTIF_BASE=virt", "-I" + sub(os.path.join(tree, "netbsd/sys/rump/net/lib/libvirtif"))])]
loglines = open(os.path.join(tree, "cc-commands.log")).read().splitlines()
ru = os.path.join(tree, "netbsd/lib/librumpuser")
for c in sorted(os.listdir(ru)):
    if not (c.startswith("rumpuser") and c.endswith(".c")) or c == "rumpuser_mem.c":
        continue
    if not any(" -c " in l and c in l for l in loglines):
        continue                     # only what the gcc build compiled
    hosted.append((os.path.join(ru, c), ["-DRUMPUSER_CONFIG=yes", "-I" + sub(os.path.join(tree, "tools/autoconf")),
                   "-I" + sub(os.path.join(tree, "tools/compat/include")), "-I" + inc, "-DLIBRUMPUSER", "-D_REENTRANT"]))
for c in ("rumpnic/rumpnic.c", "lib/vfiodev.c", "lib/confine.c"):
    hosted.append((os.path.join(rd, "drivers", c), ["-I" + inc, "-I" + sub(os.path.join(rd, "include/uapi"))]))
hl = []
for src, args in hosted:
    hl.append(["h_" + os.path.basename(src)[:-2] + ".o", "h", "0", sub(os.path.dirname(src)), sub(src)] + args)
# hosted first, as rump-pxx-build.sh links them
for l in hl + lines:
    for w in l:
        if " " in w or not w:
            sys.exit("mkunits: a word onsite.sh cannot split: %r" % w)
    print(" ".join(l))
if missing:
    sys.exit("mkunits: %d archive members without a compile" % missing)
