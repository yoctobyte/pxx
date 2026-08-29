---
prio: 70
track: B
summary: "NOT the crtl steps the job is named after — those are green at HEAD. tools/reportlab_diff.py exits 1 when the vendored oracle is PRESENT but does not IMPORT (host seven has no Pillow), so the Makefile prints 'the mimic diverged from the oracle' when nothing was compared. Third arm of a guard that already handles two. Track B file."
---

> **Track guessed as C** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 37 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:tools/crtl_reachability.py red at ee62e6dc0582 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T18:57:16Z
- **Test source:** tools/crtl_reachability.py tools/gen_crtl_map.py +34

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:tools/crtl_reachability.py'` at ee62e6dc0582f6a018102c4e1d1d9a083d7e4f32

## Range
bad `ee62e6dc0582`, last good `154d1aa3fba6`, **41 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
identical to gcc
ok: /tmp/testmgr-scratch-1053930/crtl_libc_oracle  [code=354952B  data=11344B  bss=68440B  procs=772]
  crtl-oracle: ok (byte-identical to gcc's libc)
ok: /tmp/testmgr-scratch-1053930/crtl_setjmp_oracle  [code=301945B  data=6128B  bss=60252B  procs=724]
  crtl-setjmp: ok (byte-identical to gcc)
ok: /tmp/testmgr-scratch-1053930/lib_inttohex_strict  [code=293712B  data=24696B  bss=76164B  procs=716]
Traceback (most recent call last):
  File "/tmp/tmp2h3pbk4j/many_fonts_ref.py", line 1, in <module>
    from reportlab.pdfgen import canvas
  File "/home/seven/trackt-watch/library_candidates/reportlab/src/reportlab/pdfgen/canvas.py", line 19, in <module>
    from reportlab import rl_config
  File "/home/seven/trackt-watch/library_candidates/reportlab/src/reportlab/rl_config.py", line 45, in <module>
    _DEFAULTS=_defaults_init()
              ^^^^^^^^^^^^^^^^
  File "/home/seven/trackt-watch/library_candidates/reportlab/src/reportlab/rl_config.py", line 13, in _defaults_init
    from reportlab.lib.utils import rl_exec
  File "/home/seven/trackt-watch/library_candidates/reportlab/src/reportlab/lib/utils.py", line 15, in <module>
    from PIL import Image
ModuleNotFoundError: No module named 'PIL'
Traceback (most recent call last):
  File "/home/seven/trackt-watch/tools/reportlab_diff.py", line 140, in <module>
    sys.exit(main())
             ^^^^^^
  File "/home/seven/trackt-watch/tools/reportlab_diff.py", line 131, in main
    name, msg = run_case(n, CASES[n], tmp, tol)
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/seven/trackt-watch/tools/reportlab_diff.py", line 82, in run_case
    subprocess.run([sys.executable, ref_py], check=True, env=env)
  File "/usr/lib/python3.12/subprocess.py", line 571, in run
    raise CalledProcessError(retcode, process.args,
subprocess.CalledProcessError: Command '['/usr/bin/python3', '/tmp/tmp2h3pbk4j/many_fonts_ref.py']' returned non-zero exit status 1.
reportlab_diff: the mimic diverged from the oracle

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triaged 2026-08-29 by frankC (Track C) — NOT Track C. Retracked to B.

The stub's `track: C` was guessed from the first of **36** source files in the
job bundle. The two steps the job is actually named after are **green at HEAD**
(`c513c0190`), measured, not assumed:

```
python3 tools/crtl_reachability.py
  crtl-reachability: OK -- 39 headers, 24 modules, every declared function reachable   (rc=0)
python3 tools/gen_crtl_map.py --check
  crtl-map: OK -- 323 crtl functions mapped to 22 headers                              (rc=0)
```

So does every crtl/C step in the log tail — `cstring_batch`, `cerrno_strings`,
`cprintf_hexfloat`, `cposix_io`, `cwctype`, `ctime_localtime`, `crtl-oracle`,
`crtl-setjmp` all report "identical to gcc". This is the same shape as
[[regression-lib-test-crtl-reachability]]: the red is a *later step in the same
recipe*, not the one the job selector names.

### Diagnosis — the guard has three arms and only two are implemented

`tools/reportlab_diff.py` returns 77 ("prerequisite absent, nothing compared")
for two cases: the vendored oracle directory missing, and `pdftotext` missing.
The file's own comment explains exactly why that third exit code exists —
*"a box with no poppler-utils reports 'the mimic diverged from reportlab' when
nothing was compared at all"*. The **third** arm is unguarded: the oracle
directory is **present but does not import**. Host `seven` has
`library_candidates/reportlab/src` fetched and **no Pillow**, so
`reportlab.lib.utils` dies on `from PIL import Image`, `run_case`'s
`subprocess.run(..., check=True)` raises `CalledProcessError` out of `main()`
uncaught, the script exits **1**, and the Makefile renders that as
`reportlab_diff: the mimic diverged from the oracle` — a divergence verdict for
a comparison that never happened.

Reproduced deterministically in a scratch root (this box's oracle is absent, so
it takes the first guard and skips): a `reportlab/__init__.py` that raises
`ImportError: No module named 'PIL'` yields the identical traceback — same
`reportlab_diff.py` line 82, same `CalledProcessError`, `EXIT: 1`.

### Why it matters more than one skipped probe

The recipe `exit 1`s here, so **every lib-test step after the reportlab block
never runs on seven** — roughly 750 lines of the recipe, silently uncovered
behind a red attributed to a C filename. Coverage hole, not just a noisy red.

### Fix (Track B — `tools/reportlab_diff.py` is a B file: `261184893 test(B)`, `e1aec56d3 feat(pcl)`)

Import-check the oracle in `main()`, beside the two guards already there:

```python
r = subprocess.run([sys.executable, "-c", "import reportlab.pdfgen.canvas"],
                   env=dict(os.environ, PYTHONPATH=ORACLE),
                   capture_output=True, text=True)
if r.returncode != 0:
    print("reportlab oracle present but unimportable — %s"
          % r.stderr.strip().split("\n")[-1])
    return 77          # nothing was compared; not a divergence
```

Separately, and independently of the code fix: **host `seven` should get Pillow
installed** (`python3 -m pip install pillow` / `apt install python3-pil`) so the
probe actually runs there instead of skipping. The guard stops the false
verdict; it does not restore the coverage.

*(Left unfixed by frankC deliberately — Track C does not edit Track B files.
One-line-shaped change, fully specified above.)*
