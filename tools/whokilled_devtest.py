#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: "nothing found" and "could not look" must never print the same.

`tools/whokilled.sh` exists because one sentence in a ticket cost six days:

    the kernel log is unreadable unprivileged so OOM can be neither confirmed
    nor excluded

That is the repo's most expensive recurring defect in a new costume — a check
that reports clean when it could not see. The script's entire value is the
three-way verdict (CLEAR / FOUND / CANNOT-TELL) plus a non-zero exit when any
probe was blind, so a caller cannot mistake blindness for an all-clear.

Which means the CANNOT-TELL branches are the script. On the box where it was
written every probe returns CLEAR, so those branches ran zero times — and a
canary that has never been seen to fail is not yet a canary. This drives them
by putting a fake `journalctl` / `systemctl` / `sysctl` first on PATH.

Run: tools/whokilled_devtest.py   (exit 0 = pass)
"""
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "whokilled.sh")

# A kernel log long enough to clear the completeness floor, so a test that means
# to exercise "the log is readable" is not accidentally testing the floor.
LONG_LOG = "\n".join("plexus kernel: line %d" % i for i in range(200))
OOM_LINE = ("Aug 20 03:14:15 plexus kernel: Out of memory: Killed process 12345 "
            "(csmith_fuzz.py) total-vm:8000000kB")


def fake_bin(d, name, body):
    p = os.path.join(d, name)
    with open(p, "w") as f:
        f.write("#!/usr/bin/env bash\n" + body + "\n")
    os.chmod(p, 0o755)


def run(kernel_log="", oomd_log="", oomd_active="active", oomd_installed=True,
        cgroup_root=None):
    """Run whokilled.sh against a synthetic box. Returns (rc, output)."""
    d = tempfile.mkdtemp(prefix="whokilled-devtest-")
    # journalctl: -k -> kernel log, -u systemd-oomd -> unit log, else empty.
    fake_bin(d, "journalctl", """
for a in "$@"; do
  [ "$a" = "-k" ] && { cat <<'EOF'
%s
EOF
  exit 0; }
done
for a in "$@"; do
  [ "$a" = "systemd-oomd" ] && { cat <<'EOF'
%s
EOF
  exit 0; }
done
exit 0
""" % (kernel_log, oomd_log))
    fake_bin(d, "systemctl", """
case "$1" in
  list-unit-files) %s ;;
  is-active) echo "%s" ;;
esac
""" % ("exit 0" if oomd_installed else "exit 1", oomd_active))
    fake_bin(d, "sysctl", 'echo 1')
    env = dict(os.environ, PATH=d + os.pathsep + os.environ["PATH"])
    # Point the cgroup probe at a directory we control (or at nothing).
    src = open(SCRIPT).read()
    root = cgroup_root if cgroup_root is not None else os.path.join(d, "no-such-cgroup")
    src = src.replace("root=/sys/fs/cgroup/user.slice/user-1000.slice",
                      "root=%s" % root)
    sp = os.path.join(d, "whokilled.sh")
    open(sp, "w").write(src)
    os.chmod(sp, 0o755)
    r = subprocess.run(["bash", sp], env=env, capture_output=True, text=True,
                       timeout=60)
    return r.returncode, r.stdout + r.stderr


def cgroup_tree(oom_kill):
    """A minimal cgroup tree with one memory.events carrying oom_kill=N."""
    d = tempfile.mkdtemp(prefix="whokilled-cg-")
    sub = os.path.join(d, "some.scope")
    os.makedirs(sub)
    for path in (os.path.join(d, "memory.events"), os.path.join(sub, "memory.events")):
        with open(path, "w") as f:
            f.write("low 0\nhigh 0\nmax 0\noom 0\noom_kill %d\n" % oom_kill)
    return d


FAILS = []


def check(name, cond, detail):
    if cond:
        print("  ok   %s" % name)
    else:
        print("  RED  %s" % name)
        FAILS.append("%s\n      %s" % (name, detail))


def main():
    print("whokilled: blindness must not read as clean")

    # 1. The founding case: an unprivileged kernel log is EMPTY, not an error.
    rc, out = run(kernel_log="", oomd_log="x\n")
    check("empty kernel log -> CANNOT-TELL, not CLEAR",
          "CANNOT-TELL" in out and "CLEAR        kernel" not in out,
          "an unreadable kernel log printed:\n%s" % out)
    check("blind probe forces non-zero exit", rc == 2,
          "rc=%d; a caller that checks only the exit code would read this as clean" % rc)

    # 2. A short-but-nonempty log is the sneaky case — filtering, not silence.
    rc, out = run(kernel_log="one line\ntwo lines\n", oomd_log="x\n")
    check("truncated kernel log -> CANNOT-TELL",
          "CANNOT-TELL  kernel OOM killer" in out,
          "a 2-line kernel log was accepted as a complete log:\n%s" % out)

    # 3. A readable, quiet log is the only thing that may say CLEAR — and an
    #    exit of 0 requires EVERY probe to have looked, not just this one. (The
    #    first draft of this case left the cgroup probe blind and asserted rc==0;
    #    the script correctly returned 2. The test was wrong, which is the
    #    cheapest possible demonstration that the exit code means what it says.)
    rc, out = run(kernel_log=LONG_LOG, oomd_log="started\n",
                  cgroup_root=cgroup_tree(0))
    check("readable quiet kernel log -> CLEAR", "CLEAR        kernel OOM killer" in out,
          out)
    check("all-clear exits 0 only when every probe looked", rc == 0,
          "rc=%d with all three probes reporting:\n%s" % (rc, out))

    # 4. FOUND must beat CLEAR and must show the evidence, not just a count.
    rc, out = run(kernel_log=LONG_LOG + "\n" + OOM_LINE, oomd_log="started\n")
    check("kernel OOM present -> FOUND", "FOUND        kernel OOM killer" in out, out)
    check("FOUND quotes the evidence line", "csmith_fuzz.py" in out,
          "verdict without evidence is a claim, not a measurement:\n%s" % out)

    # 5. systemd-oomd is the probe a kernel-only check wrongly exonerates.
    rc, out = run(kernel_log=LONG_LOG,
                  oomd_log="Aug 20 03:14 plexus systemd-oomd[1]: Killed "
                           "/user.slice/.../csmith.scope due to memory pressure\n")
    check("oomd kill -> FOUND even when the kernel is CLEAR",
          "FOUND        systemd-oomd" in out and "CLEAR        kernel" in out,
          "a userspace OOM kill was missed while the kernel read clean:\n%s" % out)

    # 6. Not installed / not active are genuine CLEARs, not blindness.
    rc, out = run(kernel_log=LONG_LOG, oomd_installed=False)
    check("oomd absent -> CLEAR (absence of the mechanism is real evidence)",
          "CLEAR        systemd-oomd" in out, out)
    rc, out = run(kernel_log=LONG_LOG, oomd_active="inactive")
    check("oomd inactive -> CLEAR", "CLEAR        systemd-oomd" in out, out)

    # 7. cgroup counters: unreadable is blindness, zero is CLEAR, N is FOUND.
    rc, out = run(kernel_log=LONG_LOG, oomd_log="started\n")
    check("missing cgroup root -> CANNOT-TELL",
          "CANNOT-TELL  cgroup memory.events" in out, out)
    rc, out = run(kernel_log=LONG_LOG, oomd_log="started\n",
                  cgroup_root=cgroup_tree(0))
    check("cgroup counters all zero -> CLEAR",
          "CLEAR        cgroup oom_kill counters" in out, out)
    check("CLEAR states the counters are LIVE-only", "already exited" in out,
          "a live counter reading zero says nothing about a past incident, and "
          "the output must say so:\n%s" % out)
    rc, out = run(kernel_log=LONG_LOG, oomd_log="started\n",
                  cgroup_root=cgroup_tree(3))
    check("cgroup oom_kill>0 -> FOUND", "FOUND        cgroup oom_kill" in out, out)

    if FAILS:
        print("\nwhokilled_devtest: %d RED" % len(FAILS))
        for f in FAILS:
            print("  - %s" % f)
        return 1
    print("whokilled_devtest: all green")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001
        print(fail_detail(e))
        sys.exit(1)
