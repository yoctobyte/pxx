#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: fuzz.sh's divergence key is EXIT + stdout, never the reaper's stderr.

`run_target_capture` folded stderr into the compared string with `2>&1`. On a
crashing mutant the last line of stderr is not the program speaking — it is
whoever reaped it. `timeout` says "the monitored command dumped core", qemu says
"uncaught target signal 11". Same program, same output, same exit code, three
DIVERGENCEs — and an identical crash on every target is the STRONGEST evidence
of no backend divergence, so the tool inverted its own meaning. It fired on
every crashing mutant, and a textual mutation set produces those constantly
(bug-t-fuzz-sh-reports-an-identical-crash-as-a-divergence).

Both halves are tested, and the second is the one that matters: it is trivial to
"fix" a false positive by breaking detection.

  * identical stdout + identical exit, DIFFERENT reaper stderr -> no divergence;
  * genuinely different stdout                                 -> still reported.

Drives the real tools/fuzz.sh against a fake ROOT: a stub compiler, a stub
cross-runner, and one seed. No pxx build, no qemu.
Run: python3 tools/fuzz_compare_key_devtest.py
"""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

REAL = pathlib.Path(__file__).resolve().parent / "fuzz.sh"

SEED = """program cross_stub;
begin
  if 1 <> 2 then writeln('a-1');
  writeln('b-2');
end.
"""

# The "compiler": writes a shell script standing in for the compiled binary.
# Same program for every target — the divergence, when we want one, is injected
# by the stub runner, exactly as a real backend difference would appear.
COMPILER = """#!/usr/bin/env bash
[ -n "${STUB_CALLS:-}" ] && echo x >> "$STUB_CALLS"
out=""
for a in "$@"; do case "$a" in -Fu*|--target=*) ;; *) prev=$out; out="$a";; esac; done
cat > "$out" <<'BIN'
#!/usr/bin/env bash
echo "line-one"
echo "line-two"
echo "program-said-this-on-stderr" >&2
exit 139
BIN
chmod +x "$out"
"""

# The cross runner. Reports the same crash in ITS OWN words on stderr — the
# real qemu/shell difference — and, when STUB_DIVERGE is set, also changes the
# program's STDOUT, which is a real divergence and must survive.
RUNNER = """#!/usr/bin/env bash
arch="$1"; bin="$2"
if [ -n "${STUB_DIVERGE:-}" ]; then
  echo "line-one"
  echo "line-TWO-DIFFERENT"
  echo "uncaught target signal 11 (Segmentation fault)" >&2
  exit 139
fi
"$bin"
rc=$?
echo "uncaught target signal 11 (Segmentation fault)" >&2
exit $rc
"""


def build_root(tmp):
    root = pathlib.Path(tmp) / "fakeroot"
    (root / "tools").mkdir(parents=True)
    (root / "lib" / "rtl").mkdir(parents=True)
    (root / "test").mkdir()
    (root / "stable_linux_amd64" / "default").mkdir(parents=True)
    shutil.copy(REAL, root / "tools" / "fuzz.sh")
    for path, text in ((root / "stable_linux_amd64" / "default" / "pinned", COMPILER),
                       (root / "tools" / "run_target.sh", RUNNER)):
        path.write_text(text)
        path.chmod(0o755)
    (root / "test" / "test_cross_stub.pas").write_text(SEED)
    return root


def run(root, findings, diverge, calls=None):
    """fuzz.sh for a few seconds; return its output.

    It is killed rather than allowed to finish its minute, so the summary line
    never prints — hence `calls`, a file the stub compiler appends to. Proving
    trials really happened is not optional here: a run that compiled NOTHING
    would also report no divergence, and would pass the check that matters
    while testing nothing at all.
    """
    env = dict(os.environ, FUZZ_FINDINGS_DIR=str(findings))
    if calls:
        env["STUB_CALLS"] = str(calls)
    if diverge:
        env["STUB_DIVERGE"] = "1"
    env.pop("PXX_STABLE", None)
    p = subprocess.Popen([str(root / "tools" / "fuzz.sh"), "--minutes", "1"],
                         cwd=str(root), env=env, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True)
    try:
        out, _ = p.communicate(timeout=6)
    except subprocess.TimeoutExpired:
        p.kill()
        out, _ = p.communicate()
    return out


def main():
    failures = []

    def check(cond, msg):
        print("  %-4s %s" % ("ok" if cond else "FAIL", msg))
        if not cond:
            failures.append(msg)

    with tempfile.TemporaryDirectory() as tmp:
        root = build_root(tmp)

        print("identical crash on every target, different reaper stderr")
        f1 = pathlib.Path(tmp) / "find1"
        calls = pathlib.Path(tmp) / "calls"
        out = run(root, f1, diverge=False, calls=calls)
        check("DIVERGENCE" not in out,
              "no divergence reported (stderr is not in the key)")
        check(list(f1.glob("*.pas")) == [],
              "and nothing was saved as a finding")
        n = len(calls.read_text().splitlines()) if calls.exists() else 0
        check(n >= 4, "the run really did compile mutants (%d compiler calls, "
                      "so the clean result is not vacuous)" % n)

        print("genuinely different stdout — detection must survive the fix")
        f2 = pathlib.Path(tmp) / "find2"
        out = run(root, f2, diverge=True)
        check("DIVERGENCE" in out, "divergence still reported")
        check(bool(list(f2.glob("*.pas"))), "and the mutant was saved for triage")
        txt = "".join(p.read_text() for p in f2.glob("*.txt"))
        check("stderr is NOT part of the comparison" in txt,
              "the write-up still carries stderr, labelled as triage-only")

    if failures:
        print("\n%d check(s) FAILED" % len(failures))
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
