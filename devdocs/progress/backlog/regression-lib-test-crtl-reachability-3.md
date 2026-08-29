---
prio: 70
track: C
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
