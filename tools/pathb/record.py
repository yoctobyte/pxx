#!/usr/bin/env python3
"""Path B, host side: turn the gcc reference build into the ON-SITE RECIPE,
everything a target with only pxx, a POSIX shell and toybox-level tools needs
to compile the desktop bundle itself (onsite.sh).

usage: record.py            (env PATHB_WORK; the gcc build and fonts.sh done)
writes $PATHB_WORK/recipe/:
  sources.list   SRCDIR<TAB>TARBALL: what onsite.sh unpacks (--strip-components=1)
  gen.tar.gz     every file the gcc build generated or changed in the source
                 trees (config.h, xcb's generated C, the applied patches...),
                 the staged headers and run-time data (stage/usr/include,
                 share/X11, lib/X11), and LVGL's lv_conf.h
  compile.list   one pxx --emit-obj per line: PKG<TAB>CWD<TAB>OUT<TAB>ARG...
                 tab-separated, so no shell quoting; @W@ is the work dir
  fonts/         the bundle's PCF core fonts (fonts.sh; bdftopcf is host-only)
  tools/         make_bundle.sh, onsite.sh and the files they install
  RECIPE         what made it: the pxx commit, the recording dir
link.list comes later (linkplan.sh), from the compiled objects.
"""
import os, re, shlex, subprocess, sys, tarfile, io, hashlib, shutil, filecmp, tempfile

T = os.path.dirname(os.path.abspath(__file__))
B = os.path.realpath(os.environ["PATHB_WORK"])
R = f"{B}/recipe"
PXXFLAGS = ["--shared-runtime", "--threadsafe"]
MAP = "-ffile-prefix-map=@W@=/usr/src/pathb"

# srcdir -> tarball, in build order; the replayed packages are the gcc
# build's (gccbuild.sh), then the programs built without a make log
PKGS = [("xorgproto", "xorgproto-2024.1.tar.xz"), ("libXau", "libXau-1.0.12.tar.xz"),
        ("xtrans", "xtrans-1.5.2.tar.xz"), ("xcb-proto", "xcb-proto-1.17.0.tar.xz"),
        ("libxcb", "libxcb-1.17.0.tar.xz"), ("libX11", "libX11-1.8.10.tar.xz"),
        ("libXext", "libXext-1.3.6.tar.xz"), ("libXrender", "libXrender-0.9.12.tar.xz"),
        ("expat", "expat-2.6.4.tar.xz"), ("freetype", "freetype-2.13.3.tar.xz"),
        ("fontconfig", "fontconfig-2.15.0.tar.xz"), ("libXft", "libXft-2.3.8.tar.xz"),
        ("zlib", "zlib-1.3.1.tar.gz"), ("libfontenc", "libfontenc-1.1.8.tar.xz"),
        ("libXfont", "libXfont-1.5.4.tar.bz2"), ("tinyx", "tinyx-feab72c.tar.gz"),
        ("libICE", "libICE-1.1.1.tar.xz"), ("libSM", "libSM-1.2.4.tar.xz"),
        ("libXt", "libXt-1.3.1.tar.xz"), ("libXmu", "libXmu-1.2.1.tar.xz"),
        ("libXpm", "libXpm-3.5.17.tar.xz"), ("libXaw", "libXaw-1.0.16.tar.xz"),
        ("xclock", "xclock-1.1.1.tar.xz"), ("xcalc", "xcalc-1.1.2.tar.xz"),
        ("xeyes", "xeyes-1.1.2.tar.bz2"), ("xload", "xload-1.2.0.tar.xz"),
        ("xedit", "xedit-1.2.4.tar.xz"), ("jwm", "jwm-2.4.6.tar.xz")]
REPLAYED = [p for p, _ in PKGS if p not in ("xorgproto", "xtrans", "xcb-proto")]
OTHER = [("st-0.9.2", "st-0.9.2.tar.gz"), ("dwm-6.5", "dwm-6.5.tar.gz"), ("lvgl", "lvgl-9.2.2.tar.gz")]

def w(path):
    """a path under the work dir, as the recipe spells it"""
    path = os.path.normpath(path)
    if path == B: return "@W@"
    if path.startswith(B + "/"): return "@W@" + path[len(B):]
    return path

def warg(a):
    """an argument with every work-dir path in it rewritten to @W@"""
    return a.replace(B, "@W@")

def check_line(fields):
    for f in fields:
        if "\t" in f or "\n" in f: sys.exit(f"record.py: a tab or newline in an argument: {f!r}")

# --- compile.list ---------------------------------------------------------
sys.path.insert(0, T)
import importlib.util
spec = importlib.util.spec_from_file_location("replaycc", f"{T}/replay-cc.py")
rc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc)          # its replay loop is behind __main__

lines = []
for pkg in REPLAYED:
    for cwd, src, flags in rc.units(f"{B}/logs/{pkg}.make.log"):
        # test programs (fontconfig's make check) link into nothing we ship,
        # and some name the build dir in a -D the prefix map cannot reach
        if os.path.basename(cwd) in ("test", "tests"): continue
        name = re.sub(r"[^A-Za-z0-9_.]", "_", os.path.relpath(os.path.join(cwd, src), f"{B}/src/{pkg}"))
        lines.append([pkg, w(cwd), f"@W@/replay/{pkg}/{name}.o", "--emit-obj"] + PXXFLAGS + [MAP]
                     + [warg(f) for f in flags] + [src])

# st 0.9.2 and dwm 6.5: their own .c files, no make log
INC = ["-I@W@/stage/usr/include", "-I@W@/stage/usr/include/freetype2"]
for f in ("st", "x"):
    lines.append(["st", "@W@/src/st-0.9.2", f"@W@/obj/st/{f}.o", "--emit-obj"] + PXXFLAGS + [MAP,
                  '-DVERSION="0.9.2"', "-D_XOPEN_SOURCE=600"] + INC + [f"{f}.c"])
for f in ("drw", "dwm", "util"):
    lines.append(["dwm", "@W@/src/dwm-6.5", f"@W@/obj/dwm/{f}.o", "--emit-obj"] + PXXFLAGS + [MAP,
                  '-DVERSION="6.5"', "-D_DEFAULT_SOURCE", "-D_BSD_SOURCE", "-D_XOPEN_SOURCE=700L"] + INC + [f"{f}.c"])

# LVGL's widgets demo (prep.sh made lv_conf.h; its file list is recorded here)
L = f"{B}/src/lvgl"
lfiles = sorted(os.path.relpath(os.path.join(d, f), L)
                for top in ("src", "demos/widgets") for d, _, fs in os.walk(f"{L}/{top}")
                for f in fs if f.endswith(".c"))
lfiles.append("demos/lv_demos.c")
LINC = ["-I@W@/obj/lvgl", "-I@W@/src/lvgl", "-DLV_CONF_INCLUDE_SIMPLE"]
for f in lfiles:
    t = f.replace("/", "_")[:-2]
    lines.append(["lvgl", "@W@/src/lvgl", f"@W@/obj/lvgl/o/{t}.o", "--emit-obj", "--shared-runtime", MAP] + LINC + [f])
lines.append(["lvgl", "@W@/src/lvgl", "@W@/obj/lvgl/o/main.o", "--emit-obj", "--shared-runtime", MAP] + LINC
             + ["pathb-main.c"])   # travels in gen.tar: RECIPE may live anywhere

for l in lines:
    for a in l[4:]:
        if "@W@" in a and not (a.startswith("-I") or a == MAP):
            sys.exit(f"record.py: the work dir in {a!r} ({l[2]}): the objects would depend on it")

os.makedirs(R, exist_ok=True)
with open(f"{R}/compile.list", "w") as fh:
    for l in lines:
        check_line(l)
        fh.write("\t".join(l) + "\n")

# --- sources.list ---------------------------------------------------------
with open(f"{R}/sources.list", "w") as fh:
    for d, t in PKGS + OTHER:
        fh.write(f"{d}\t{t}\n")
for d in os.listdir(f"{B}/src"):
    if d not in dict(PKGS + OTHER): sys.exit(f"record.py: src/{d} is in no recipe list")

# --- gen.tar.gz -----------------------------------------------------------
# A file goes in if the gcc build made or changed it in a source tree and it
# is not a build product. The pristine tree is the bare tarball, exactly what
# onsite.sh lays gen.tar over: so the files our patches/ change travel in
# gen.tar too, and the target needs no patch tool.
SKIP_DIRS = {".libs", ".deps", "autom4te.cache", ".git"}
SKIP_SUFFIX = (".o", ".lo", ".la", ".a", ".so", ".Po", ".Plo", ".log", ".trs", ".pyc")
SKIP_NAMES = {"config.status", "libtool", "Makefile", "stamp-h1", "stamp-h", "config.cache"}

def is_elf(p):
    with open(p, "rb") as f: return f.read(4) == b"\x7fELF"

def pristine(d, t, into):
    os.makedirs(into)
    subprocess.run(["tar", "-xf", f"{B}/dl/{t}", "-C", into, "--strip-components=1"], check=True)

members = []   # (arcname, path)
tmp = tempfile.mkdtemp(prefix="pathb-pristine-", dir=B)
for d, t in PKGS + OTHER:
    built = f"{B}/src/{d}"
    if not os.path.isdir(built): continue
    pr = f"{tmp}/{d}"
    pristine(d, t, pr)
    for root, dirs, files in os.walk(built):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
        for f in sorted(files):
            p = os.path.join(root, f)
            rel = os.path.relpath(p, built)
            if os.path.islink(p) or f in SKIP_NAMES or f.endswith(SKIP_SUFFIX): continue
            if not os.path.isfile(p) or is_elf(p): continue
            q = os.path.join(pr, rel)
            if os.path.isfile(q) and filecmp.cmp(p, q, shallow=False): continue
            members.append((f"src/{d}/{rel}", p))
shutil.rmtree(tmp)
for top in ("stage/usr/include", "stage/usr/share/X11", "stage/usr/lib/X11"):
    for root, dirs, files in os.walk(f"{B}/{top}"):
        dirs.sort()
        for f in sorted(files):
            p = os.path.join(root, f)
            if os.path.isfile(p) and not os.path.islink(p):
                members.append((os.path.relpath(p, B), p))
members.append(("obj/lvgl/lv_conf.h", f"{B}/obj/lvgl/lv_conf.h"))
members.append(("src/lvgl/pathb-main.c", f"{T}/lvgl/main.c"))

def add(tf, arc, path):
    ti = tarfile.TarInfo(arc)
    data = open(path, "rb").read()
    ti.size = len(data); ti.mode = 0o755 if os.access(path, os.X_OK) else 0o644
    ti.mtime = 1767225600; ti.uid = ti.gid = 0; ti.uname = ti.gname = ""
    tf.addfile(ti, io.BytesIO(data))

raw = io.BytesIO()
with tarfile.open(fileobj=raw, mode="w", format=tarfile.USTAR_FORMAT) as tf:
    for arc, p in sorted(members):
        add(tf, arc, p)
import gzip
with open(f"{R}/gen.tar.gz", "wb") as fh:
    fh.write(gzip.compress(raw.getvalue(), compresslevel=9, mtime=0))

# --- tools: what onsite.sh runs and installs ------------------------------
if os.path.isdir(f"{R}/tools"): shutil.rmtree(f"{R}/tools")
os.makedirs(f"{R}/tools")
for f in ("onsite.sh", "make_bundle.sh"):
    shutil.copy2(f"{T}/{f}", f"{R}/tools/{f}")
for d in ("files", "patches", "lvgl"):
    shutil.copytree(f"{T}/{d}", f"{R}/tools/{d}")

pxx = subprocess.run(["git", "-C", f"{T}/../..", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
with open(f"{R}/RECIPE", "w") as fh:
    fh.write(f"pxx={pxx}\nrecorded_in={B}\nunits={len(lines)}\ngen_files={len(members)}\n")
print(f"recipe: {len(lines)} compiles, {len(members)} generated/staged files -> {R}")
