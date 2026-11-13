#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""dropbear built by pxx from UNMODIFIED upstream source, then logged into.

feature-c-dropbear-builds-with-pxx. Not a unit test: it needs the fetched
tree (tools/install_lib_candidates.sh dropbear), so it is not in `make test`.

WHAT IT DOES
  1. gcc reference. Copies the pinned tree, runs dropbear's own `configure`
     with the configuration below, builds dropbear/dbclient/dropbearkey/scp
     with gcc, and relinks each with -Wl,-Map. The map says which
     libtomcrypt/libtommath archive members each program pulls, because
     `pascal26 --link` takes objects, not archives.
  2. pxx build. Every compile line from that gcc build is replayed through
     `pascal26 --emit-obj` with the same -I/-D flags and the same config.h,
     one object per translation unit, and each program is linked with
     `pascal26 --link`: no gcc, no ld, no libc.
  3. Proof (skipped by --build-only), on 127.0.0.1, non-privileged ports,
     throwaway keys under a temporary directory. ~/.ssh is never read or
     written; HOME is pointed at the work dir for every client.
       - dropbearkey (pxx) makes ed25519, ecdsa and RSA host keys, and
         ssh-keygen (OpenSSH) reads each public half.
       - a stock OpenSSH client logs in to the pxx dropbear by public key and
         runs a command. known_hosts holds the pxx-generated host keys and
         StrictHostKeyChecking=yes, so every login also checks a host-key
         signature made by pxx code.
       - the same login once per cipher, MAC, key exchange and host-key
         algorithm both sides support. A miscompiled primitive fails its row
         with a handshake or MAC error, not a quiet wrong answer.
       - 1 MiB of random bytes up and down the channel, sha256 both ends.
       - an interactive pty session (ssh -tt): the remote sees a /dev/pts tty.
       - scp in both directions (legacy protocol, -O). The server's `scp -t`
         is the pxx scp: dropbear runs with -e and the work bin dir first on
         PATH, and a row checks that the remote resolves scp to it.
       - the pxx dbclient logs in to a stock OpenSSH sshd (run as this user,
         its own config, host key and authorized_keys) and runs a command,
         once per cipher dbclient offers.

CONFIGURATION (dropbear's own switches; no source is patched):
  --disable-zlib, and utmp/utmpx/wtmp/wtmpx/lastlog/pututline/pututxline and
  loginfunc off, so no login records are written. Password auth is compiled
  in (crtl's crypt does SHA-crypt), but these tests log in by key.
  CFLAGS adds -DMP_32BIT, for BOTH builds: libtommath's own 32-bit-digit
  configuration. Its default on x86-64 under __GNUC__ is 64-bit digits with
  a 128-bit mp_word declared `__attribute__((mode(TI)))`, and pxx has no
  128-bit integer (feature-c-int128-and-attribute-mode). pxx refuses that
  attribute by name rather than making the type 64 bits wide, which is what
  it silently did before: RSA key generation never found a prime.

THE LAST LINE IS A POSITIVE TOKEN: DROPBEAR-PXX-COMPLETE, with GREEN or RED.
No token means no result, whatever the exit status says.

usage: tools/dropbear_pxx.py [--pinned] [--keep] [--jobs N] [--build-only]
                             [--out DIR] [--port N]
  --pinned      use the stable pinned compiler (tools/pxx_stable.sh) instead
                of compiler/pascal26
  --keep        keep the work directory and print it
  --jobs N      parallel compiles (default 6), each under nice -n 15
  --build-only  stop after linking; with --out, copy the four binaries there
  --port N      first TCP port to use (default: a free one from the kernel)
"""
import argparse
import hashlib
import os
import re
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.environ.get("PXX_DROPBEAR_DIR", os.path.join(ROOT, "library_candidates", "dropbear"))
PROGRAMS = ["dropbear", "dbclient", "dropbearkey", "scp"]
# --target: the pxx build's CPU. The gcc reference (and so config.h and the
# compile lines) stays the host's: no cross gcc is needed, and the pxx crtl,
# not glibc, is the C library either way. A non-host binary runs through the
# kernel's binfmt_misc qemu handler, which the tests need anyway: dropbear
# execs the pxx scp itself.
TARGET = "x86_64"
CONFIGURE = ["--disable-zlib", "--disable-utmp", "--disable-utmpx", "--disable-wtmp",
             "--disable-wtmpx", "--disable-lastlog", "--disable-pututline",
             "--disable-pututxline", "--disable-loginfunc"]
TAG = "dropbear-pxx"
# dropbear's configure default is -Os -W -Wall; setting CFLAGS replaces it.
CFLAGS = "-Os -W -Wall -DMP_32BIT"

results = []          # (name, ok, detail)


def say(msg):
    print("%s: %s" % (TAG, msg), flush=True)


def die(msg):
    print("%s: %s" % (TAG, msg), file=sys.stderr, flush=True)
    print("DROPBEAR-PXX-COMPLETE RED")
    sys.exit(1)


def row(name, ok, detail=""):
    results.append((name, ok, detail))
    say("%-4s %s%s" % ("PASS" if ok else "FAIL", name, ("  -- " + detail) if detail else ""))
    return ok


def run(cmd, cwd=None, env=None, timeout=600, inp=None):
    """(rc, stdout, stderr). A timeout is a result, not a crash: rc -9 and a
    stderr line that says so, so the row that ran it fails with a reason and
    the rest of the run still reports."""
    try:
        p = subprocess.run(cmd, cwd=cwd, env=env, timeout=timeout, input=inp,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.TimeoutExpired as e:
        return -9, e.stdout or b"", (e.stderr or b"") + (b"\ntimed out after %ds" % timeout)
    return p.returncode, p.stdout, p.stderr


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def wait_port(port, proc, secs=30):
    end = time.time() + secs
    while time.time() < end:
        if proc.poll() is not None:
            return False
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                return True
        except OSError:
            time.sleep(0.2)
    return False


# ---------------------------------------------------------------- build ----

def gcc_reference(work, jobs):
    tree = os.path.join(work, "tree")
    shutil.copytree(SRC, tree, symlinks=True)
    env = dict(os.environ, CFLAGS=CFLAGS)
    rc, out, err = run(["nice", "-n", "15", "./configure"] + CONFIGURE, cwd=tree, env=env)
    open(os.path.join(work, "configure.log"), "wb").write(out + err)
    if rc != 0:
        die("gcc reference: configure failed, see %s/configure.log" % work)
    rc, out, err = run(["nice", "-n", "15", "make", "-j%d" % jobs, "PROGRAMS=" + " ".join(PROGRAMS)]
                       + PROGRAMS, cwd=tree, timeout=1800, env=env)
    if b"-DMP_32BIT" not in out + err:
        die("gcc reference: -DMP_32BIT did not reach the compile lines; libtommath would pick mode(TI)")
    log = os.path.join(work, "make-gcc.log")
    open(log, "wb").write(out + err)
    if rc != 0:
        die("gcc reference: make failed, see %s -- with no oracle there is nothing to compare against" % log)
    maps = {}
    for p in PROGRAMS:
        objs = prog_objs(tree, p)
        mp = os.path.join(work, p + ".map")
        rc, out, err = run(["gcc", "-Wl,-Map=" + mp, "-o", os.path.join(work, p + ".gcc")]
                           + objs + ["libtomcrypt/libtomcrypt.a", "libtommath/libtommath.a", "-lcrypt"],
                           cwd=tree)
        if rc != 0:
            die("gcc reference: relinking %s with a map failed: %s" % (p, err.decode(errors="replace")[-300:]))
        maps[p] = mp
    return tree, log, maps


def prog_objs(tree, prog):
    rc, out, err = run(["make", "-s", "--eval=print-%: ; @echo $($*)", "print-%sobjs" % prog], cwd=tree)
    objs = out.decode().split()
    if rc != 0 or not objs:
        die("cannot read %sobjs from dropbear's Makefile" % prog)
    return objs


def compile_units(tree, log):
    """(cwd, src, obj, flags) for every gcc compile line in the build log.

    A unit is the OBJECT a line writes, not its source: libtomcrypt compiles
    src/ciphers/aes/aes.c twice, once as aes.o and once with -DENCRYPT_ONLY as
    aes_enc.o. Keyed by source, the second compile overwrote the first and
    aes_desc went missing at link time."""
    units = []
    base = os.path.abspath(tree)
    for line in open(log, errors="replace"):
        if not (line.startswith("gcc ") and " -c" in line):
            continue
        a = shlex.split(line)
        flags, src, obj = [], None, None
        for i, x in enumerate(a[1:], 1):
            if x.startswith(("-I", "-D", "-U")) and x != "-D_FORTIFY_SOURCE=2":
                flags.append(x)
            elif x.endswith(".c"):
                src = x
            elif x == "-o" and i + 1 < len(a):
                obj = a[i + 1]
        if obj is None:
            die("compile line writes no -o object: " + line.strip()[:200])
        # make -j interleaves "Entering directory" lines, so the directory is
        # found by where the source exists, not by tracking them.
        for d in (base, os.path.join(base, "libtomcrypt"), os.path.join(base, "libtommath")):
            if os.path.exists(os.path.join(d, src)):
                units.append((d, src, obj, flags))
                break
        else:
            die("compile line names a source that is in none of the three dirs: " + src)
    return units


def unit_tag(tree, cwd, obj):
    rel = os.path.relpath(os.path.join(cwd, obj), os.path.abspath(tree))
    return rel[:-2].replace("/", "__")


def link_plan(tree, prog, mapfile, have):
    out = []
    for o in prog_objs(tree, prog):
        t = unit_tag(tree, os.path.abspath(tree), o)
        if t not in have:
            die("no translation unit for %s (%s)" % (o, t))
        out.append(t)
    mp = open(mapfile, errors="replace").read()
    for lib, mem in sorted(set(re.findall(r"(libtomcrypt|libtommath)\.a\(([^)]*)\.o\)", mp))):
        cand = [h for h in have if h.startswith(lib + "__") and h.endswith("__" + mem)]
        if len(cand) != 1:
            die("archive member %s(%s.o) maps to %d translation units" % (lib, mem, len(cand)))
        out.append(cand[0])
    return out


def target_flags():
    return [] if TARGET == "x86_64" else ["--target=" + TARGET]


def binfmt_ready(target):
    """A foreign binary must run by plain exec (dropbear execs scp and the
    tests exec dropbear), so qemu-user has to be registered with binfmt_misc."""
    if target == "x86_64":
        return True
    try:
        return open("/proc/sys/fs/binfmt_misc/qemu-" + target).read().startswith("enabled")
    except OSError:
        return False


def pxx_build(work, tree, log, maps, compiler, jobs):
    objdir = os.path.join(work, "obj")
    bindir = os.path.join(work, "bin")
    os.makedirs(objdir)
    os.makedirs(bindir)
    units = {}
    for c, s, o, f in compile_units(tree, log):
        t = unit_tag(tree, c, o)
        if t in units and units[t] != (c, s, f):
            die("two different compile lines write %s" % t)
        units[t] = (c, s, f)
    plans = {p: link_plan(tree, p, maps[p], units) for p in PROGRAMS}
    needed = sorted({t for plan in plans.values() for t in plan})

    def one(t):
        cwd, src, flags = units[t]
        o = os.path.join(objdir, t + ".o")
        # --function-sections (dead-code GC at link) is x86-64 only: the
        # aarch64 object writer has no R_AARCH64_CALL26 for cross-section calls.
        fs = ["--function-sections"] if TARGET == "x86_64" else []
        rc, out, err = run(["nice", "-n", "15", compiler, "--emit-obj"] + fs
                           + target_flags() + flags + [src, o], cwd=cwd, timeout=1200)
        text = (out + err).decode(errors="replace")
        open(os.path.join(objdir, t + ".log"), "w").write(text)
        ok = rc == 0 and os.path.exists(o)
        first = next((l for l in text.splitlines() if "error" in l), text.strip().splitlines()[-1:] or [""])
        return t, ok, first if not ok else ""

    say("compiling %d translation units with pxx (%d jobs)" % (len(needed), jobs))
    with ThreadPoolExecutor(jobs) as ex:
        res = list(ex.map(one, needed))
    bad = [r for r in res if not r[1]]
    row("pxx compiles all %d translation units" % len(needed), not bad,
        "; ".join("%s: %s" % (t, e) for t, _, e in bad[:5]) + (" ..." if len(bad) > 5 else ""))
    if bad:
        return None
    for p in PROGRAMS:
        objs = [os.path.join(objdir, t + ".o") for t in plans[p]]
        rc, out, err = run(["nice", "-n", "15", compiler, "--link"] + target_flags()
                           + ["-o", os.path.join(bindir, p)] + objs,
                           timeout=1200)
        text = (out + err).decode(errors="replace")
        open(os.path.join(work, "link-%s.log" % p), "w").write(text)
        ok = rc == 0 and os.path.exists(os.path.join(bindir, p))
        row("pxx links %s (%d objects)" % (p, len(objs)), ok,
            "" if ok else text.strip().splitlines()[-1] if text.strip() else "rc=%d" % rc)
        if not ok:
            return None
    return bindir


# ----------------------------------------------------------------- test ----

def ssh_base(t, port, key):
    return ["ssh", "-F", "/dev/null", "-p", str(port), "-i", key,
            "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes",
            "-o", "UserKnownHostsFile=" + os.path.join(t, "known_hosts"),
            "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=20"]


def private_authdir():
    """dropbear's -D dir for authorized_keys. dropbear (svr-authpubkey.c)
    refuses the keys when ANY component of the path is group- or
    world-writable, so /tmp (1777) can never hold it. Use a fresh dir under
    ~/.cache and check every component up front, so a failure says why
    instead of 'Permission denied (publickey)'."""
    base = os.path.join(os.path.expanduser("~"), ".cache", "dropbear-pxx")
    os.makedirs(base, mode=0o700, exist_ok=True)
    d = tempfile.mkdtemp(prefix="auth-", dir=base)
    AUTHDIRS.append(d)
    p = d
    while True:
        st = os.stat(p)
        if st.st_mode & 0o022 or st.st_uid not in (0, os.getuid()):
            die("%s is group/world-writable or foreign-owned; dropbear would refuse "
                "authorized_keys under %s" % (p, d))
        if p == "/":
            break
        p = os.path.dirname(p)
    return d


AUTHDIRS = []


def tests(work, bindir, port0):
    t = os.path.join(work, "t")
    home = os.path.join(t, "home")
    os.makedirs(home)
    # dropbear, like sshd's StrictModes, refuses an authorized_keys path with
    # a group- or world-writable component, and the caller's umask (002 here)
    # would leave t/ as drwxrwxr-x: "must be owned by user or root, and not
    # writable by group or others", then Permission denied. Every directory
    # the server or client walks is made 0700.
    for d in (t, home):
        os.chmod(d, 0o700)
    env = dict(os.environ, HOME=home)
    user = subprocess.run(["id", "-un"], stdout=subprocess.PIPE).stdout.decode().strip()
    dbk = os.path.join(bindir, "dropbearkey")

    # host keys, made by pxx dropbearkey
    hostkeys = {}
    for kt, extra in (("ed25519", []), ("ecdsa", ["-s", "256"]), ("rsa", ["-s", "2048"])):
        f = os.path.join(t, "host_" + kt)
        t0 = time.time()
        rc, out, err = run([dbk, "-t", kt, "-f", f] + extra, env=env, timeout=300)
        dt = time.time() - t0
        rc2, pub, _ = run([dbk, "-y", "-f", f], env=env)
        publine = next((l for l in pub.decode(errors="replace").splitlines()
                        if l.startswith(("ssh-", "ecdsa-"))), "")
        pf = f + ".pub"
        open(pf, "w").write(publine + "\n")
        rc3, fp, err3 = run(["ssh-keygen", "-l", "-f", pf])
        ok = rc == 0 and rc2 == 0 and rc3 == 0 and publine != ""
        row("dropbearkey makes a %s host key that ssh-keygen reads (%.1fs)" % (kt, dt), ok,
            "" if ok else (err + err3).decode(errors="replace").strip()[-200:])
        if ok:
            hostkeys[kt] = (f, publine)
    if "ed25519" not in hostkeys:
        return

    # client key (OpenSSH) and the server's authorized_keys dir
    ckey = os.path.join(t, "client_ed25519")
    run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", ckey, "-C", "dropbear-pxx-test"])
    authdir = private_authdir()
    shutil.copy(ckey + ".pub", os.path.join(authdir, "authorized_keys"))
    os.chmod(os.path.join(authdir, "authorized_keys"), 0o600)

    port = port0 or free_port()
    with open(os.path.join(t, "known_hosts"), "w") as kh:
        for kt, (f, publine) in hostkeys.items():
            kh.write("[127.0.0.1]:%d %s\n" % (port, " ".join(publine.split()[:2])))

    srv_env = dict(env, PATH=bindir + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"))
    srv_cmd = [os.path.join(bindir, "dropbear"), "-F", "-E", "-e", "-s", "-p", "127.0.0.1:%d" % port,
               "-D", authdir, "-P", os.path.join(t, "dropbear.pid")]
    for kt, (f, _) in hostkeys.items():
        srv_cmd += ["-r", f]
    srv_log = open(os.path.join(t, "dropbear.log"), "wb")
    srv = subprocess.Popen(srv_cmd, env=srv_env, stdout=srv_log, stderr=subprocess.STDOUT)
    try:
        if not row("pxx dropbear listens on 127.0.0.1:%d" % port, wait_port(port, srv),
                   "see %s/dropbear.log" % t):
            return
        base = ssh_base(t, port, ckey)
        dest = "%s@127.0.0.1" % user

        rc, out, err = run(base + [dest, "echo hello-from-dropbear; id -un"], env=env, timeout=120)
        row("OpenSSH logs in by public key and runs a command",
            rc == 0 and out.decode() == "hello-from-dropbear\n%s\n" % user,
            (out + err).decode(errors="replace").strip()[-300:])

        def algos(flag):
            rc, out, _ = run([os.path.join(bindir, "dropbear"), "-Q", flag], env=env)
            ours = [l.strip() for l in out.decode().splitlines() if l.strip()]
            rc, out, _ = run(["ssh", "-Q", {"cipher": "cipher", "mac": "mac", "kex": "kex",
                                            "sig": "HostKeyAlgorithms"}[flag]])
            theirs = set(out.decode().split())
            return [a for a in ours if a in theirs]

        matrix = []
        for c in algos("cipher"):
            matrix.append(("cipher " + c, ["-o", "Ciphers=" + c]))
        for m in algos("mac"):
            matrix.append(("mac " + m, ["-o", "Ciphers=aes128-ctr", "-o", "MACs=" + m]))
        for k in algos("kex"):
            matrix.append(("kex " + k, ["-o", "KexAlgorithms=" + k]))
        have_sig = {"ed25519": ["ssh-ed25519"], "ecdsa": ["ecdsa-sha2-nistp256"],
                    "rsa": ["rsa-sha2-256", "rsa-sha2-512"]}
        offered = set(algos("sig"))
        for kt in hostkeys:
            for s in have_sig[kt]:
                if s in offered:
                    matrix.append(("host key " + s, ["-o", "HostKeyAlgorithms=" + s]))
        for name, opts in matrix:
            rc, out, err = run(base + opts + [dest, "echo ok"], env=env, timeout=120)
            row("OpenSSH login, " + name, rc == 0 and out == b"ok\n",
                err.decode(errors="replace").strip()[-200:])

        blob = os.urandom(1 << 20)
        want = hashlib.sha256(blob).hexdigest()
        rc, out, err = run(base + [dest, "sha256sum"], env=env, inp=blob, timeout=300)
        row("1 MiB up the channel arrives intact", rc == 0 and out.decode().split()[:1] == [want],
            err.decode(errors="replace").strip()[-200:])
        upf = os.path.join(t, "blob.bin")
        open(upf, "wb").write(blob)
        rc, out, err = run(base + [dest, "cat " + shlex.quote(upf)], env=env, timeout=300)
        row("1 MiB down the channel arrives intact", rc == 0 and hashlib.sha256(out).hexdigest() == want,
            err.decode(errors="replace").strip()[-200:])

        # stdin stays OPEN until ssh exits: with -tt and stdin at EOF, OpenSSH
        # sends channel EOF at once, dropbear (unlike sshd) answers by closing
        # the pty master, and the child dies of SIGHUP before it prints. The
        # gcc build does exactly the same, so it is the test, not a miscompile.
        rfd, wfd = os.pipe()
        try:
            p = subprocess.Popen(base + ["-tt", dest, "tty; echo PTY-DONE"], env=env, stdin=rfd,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            os.close(rfd)
            try:
                out, err = p.communicate(timeout=120)
                rc = p.returncode
            except subprocess.TimeoutExpired:
                p.kill()
                out, err = p.communicate()
                rc = -9
        finally:
            os.close(wfd)
        text = out.decode(errors="replace")
        row("interactive pty session (ssh -tt)", rc == 0 and "/dev/pts/" in text and "PTY-DONE" in text,
            (text + err.decode(errors="replace")).strip()[-200:])

        rc, out, err = run(base + [dest, "command -v scp"], env=env, timeout=120)
        row("the server's scp is the pxx scp", out.decode().strip() == os.path.join(bindir, "scp"),
            out.decode().strip())
        scp = ["scp", "-O", "-F", "/dev/null", "-P", str(port), "-i", ckey, "-o", "IdentitiesOnly=yes",
               "-o", "BatchMode=yes", "-o", "UserKnownHostsFile=" + os.path.join(t, "known_hosts"),
               "-o", "GlobalKnownHostsFile=/dev/null", "-o", "StrictHostKeyChecking=yes"]
        up = os.path.join(t, "scp_up.bin")
        rc, out, err = run(scp + [upf, "%s:%s" % (dest, up)], env=env, timeout=300)
        row("scp upload", rc == 0 and os.path.exists(up) and
            hashlib.sha256(open(up, "rb").read()).hexdigest() == want,
            err.decode(errors="replace").strip()[-200:])
        down = os.path.join(t, "scp_down.bin")
        rc, out, err = run(scp + ["%s:%s" % (dest, upf), down], env=env, timeout=300)
        row("scp download", rc == 0 and os.path.exists(down) and
            hashlib.sha256(open(down, "rb").read()).hexdigest() == want,
            err.decode(errors="replace").strip()[-200:])
    finally:
        srv.terminate()
        try:
            srv.wait(10)
        except subprocess.TimeoutExpired:
            srv.kill()
        srv_log.close()

    dbclient_to_sshd(t, bindir, env, user, dbk)


def dbclient_to_sshd(t, bindir, env, user, dbk):
    sshd = shutil.which("sshd") or "/usr/sbin/sshd"
    if not os.path.exists(sshd):
        row("stock sshd present for the dbclient test", False, "no sshd on this host")
        return
    port = free_port()
    hk = os.path.join(t, "sshd_host_ed25519")
    run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", hk])
    ck = os.path.join(t, "dbclient_ed25519")
    rc, _, err = run([dbk, "-t", "ed25519", "-f", ck], env=env)
    rc2, pub, _ = run([dbk, "-y", "-f", ck], env=env)
    publine = next((l for l in pub.decode().splitlines() if l.startswith("ssh-")), "")
    ak = os.path.join(t, "sshd_authorized_keys")
    open(ak, "w").write(publine + "\n")
    os.chmod(ak, 0o600)
    cfg = os.path.join(t, "sshd_config")
    open(cfg, "w").write("\n".join([
        "Port %d" % port, "ListenAddress 127.0.0.1", "HostKey " + hk,
        "AuthorizedKeysFile " + ak, "PidFile " + os.path.join(t, "sshd.pid"),
        "UsePAM no", "StrictModes no", "PasswordAuthentication no",
        "KbdInteractiveAuthentication no", "PubkeyAuthentication yes", ""]))
    log = open(os.path.join(t, "sshd.log"), "wb")
    srv = subprocess.Popen([sshd, "-D", "-e", "-f", cfg], stdout=log, stderr=subprocess.STDOUT)
    try:
        if not row("stock sshd listens on 127.0.0.1:%d" % port, wait_port(port, srv),
                   "see %s/sshd.log" % t):
            return
        # dbclient's known_hosts: the sshd host key, in HOME/.ssh. dropbear
        # matches the bare host name and ignores the port (cli-kex.c
        # checkhostkey), so this is its format, not OpenSSH's [host]:port.
        os.makedirs(os.path.join(env["HOME"], ".ssh"), mode=0o700, exist_ok=True)
        hpub = open(hk + ".pub").read().split()
        open(os.path.join(env["HOME"], ".ssh", "known_hosts"), "w").write(
            "127.0.0.1 %s %s\n" % (hpub[0], hpub[1]))
        db = [os.path.join(bindir, "dbclient"), "-i", ck, "-p", str(port), "-l", user]
        rc, out, err = run(db + ["127.0.0.1", "echo hello-from-dbclient"], env=env, timeout=120)
        row("pxx dbclient logs in to stock sshd and runs a command",
            rc == 0 and out == b"hello-from-dbclient\n", (out + err).decode(errors="replace").strip()[-300:])
        rc, out, _ = run([os.path.join(bindir, "dbclient"), "-Q", "cipher"], env=env)
        for c in [l.strip() for l in out.decode().splitlines() if l.strip()]:
            rc, out, err = run(db + ["-c", c, "127.0.0.1", "echo ok"], env=env, timeout=120)
            row("dbclient login, cipher " + c, rc == 0 and out == b"ok\n",
                err.decode(errors="replace").strip()[-200:])
    finally:
        srv.terminate()
        try:
            srv.wait(10)
        except subprocess.TimeoutExpired:
            srv.kill()
        log.close()


# ----------------------------------------------------------------- main ----

def main():
    ap = argparse.ArgumentParser(description="build dropbear with pxx and log in to it")
    ap.add_argument("--pinned", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--build-only", action="store_true")
    ap.add_argument("--out")
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--target", default="x86_64", choices=["x86_64", "aarch64"])
    a = ap.parse_args()
    global TARGET
    TARGET = a.target
    if not a.build_only and not binfmt_ready(TARGET):
        die("--target=%s needs qemu-%s registered with binfmt_misc (see /proc/sys/fs/binfmt_misc)"
            % (TARGET, TARGET))

    if not os.path.isfile(os.path.join(SRC, "configure")):
        die("no dropbear tree at %s -- run: tools/install_lib_candidates.sh dropbear" % SRC)
    if a.pinned:
        compiler = subprocess.run([os.path.join(ROOT, "tools", "pxx_stable.sh")],
                                  stdout=subprocess.PIPE).stdout.decode().strip()
    else:
        compiler = os.path.join(ROOT, "compiler", "pascal26")
    if not os.access(compiler, os.X_OK):
        die("no compiler at " + compiler)
    # Snapshot the compiler BESIDE the original (it finds lib/crtl relative to
    # itself): `make compiler/pascal26` rewrites the original in place, and a
    # run takes minutes.
    snap = os.path.join(os.path.dirname(compiler), ".pxx-under-test-%d" % os.getpid())
    shutil.copy2(compiler, snap)
    csha = hashlib.sha256(open(snap, "rb").read()).hexdigest()
    work = tempfile.mkdtemp(prefix="dropbear-pxx-")
    try:
        say("source %s" % SRC)
        say("compiler %s sha256=%s" % (compiler, csha[:12]))
        say("target %s" % TARGET)
        say("work %s" % work)
        tree, log, maps = gcc_reference(work, a.jobs)
        row("gcc reference builds %s" % " ".join(PROGRAMS), True)
        bindir = pxx_build(work, tree, log, maps, snap, a.jobs)
        if bindir and a.out:
            os.makedirs(a.out, exist_ok=True)
            for p in PROGRAMS:
                shutil.copy2(os.path.join(bindir, p), os.path.join(a.out, p))
            say("binaries copied to %s" % a.out)
        if bindir and not a.build_only:
            tests(work, bindir, a.port)
    finally:
        os.unlink(snap)
        if a.keep:
            say("kept %s" % work)
        else:
            shutil.rmtree(work, ignore_errors=True)
        for d in AUTHDIRS:
            shutil.rmtree(d, ignore_errors=True)
    bad = [r for r in results if not r[1]]
    say("%d rows, %d failed" % (len(results), len(bad)))
    print("DROPBEAR-PXX-COMPLETE %s" % ("GREEN" if not bad else "RED"))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
