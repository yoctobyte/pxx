---
prio: 75
---

# regression: 25c1dded (GNU statement expressions) — 150x cfront slowdown on GTK headers + cJSON/lua corpus breakage

- **Type:** regression (cfront). Track C. Single-commit range, verified locally at the SHA.
- **Found:** 2026-07-08 by Track T (borg full run at `25c1ddedcccb`); reproduced in a
  throwaway clone at that SHA.
- **Suspect commit:** `25c1dded` "feat(cfront): GNU statement expressions (({ ...; expr; })) (00214)" —
  only commit in the tested range.

## RESOLUTION (2026-07-08) — NOT a compiler regression; symptoms already green at HEAD

Investigated at HEAD (`d559cc19`; borg full **GREEN** at `3a6acc11`, the code SHA one below).
The stmt-expr commit is **provably inert** for all three symptoms — it did not cause any of them.

**Statement-expression code path is dead for every named corpus.**
- Instrumented `ParseCStmtExprAST` with a call counter, rebuilt, compiled the GTK
  header test: **`calls=0`**. The function never runs during header import (header
  import parses declarations/prototypes, not the inline-function bodies where glib's
  `G_LIKELY`/`G_UNLIKELY` → `({ … })` live).
- `grep -c '({'` = **0** in `cJSON.c`, `test/cjson/runner.c`, and the lua sources.
  No statement expressions occur, so the new code is never reached.
- The only other hunk (the `if CurTok.Kind = tkBegin` guard added to the `tkLParen`
  branch of `ParseCPrimary`) fires *only* on `(` immediately followed by `{` — absent
  in all three corpora. Confirmed by building the parent-`cparser.inc` compiler
  (`25c1dded^`) vs HEAD: identical cJSON runner (`code=251991B`), all 5 fixtures pass
  with both.

**Symptom 1 (GTK `test-core#599`/`#601` TIMEOUT) — pre-existing heavy parse, flaky under load.**
`uses gtk` pulls the real system `/usr/include/gtk-2.0` headers → **13619 procs**,
~17–40 s wall on this box (dominated by header parsing; emitted code byte-identical
base vs head). That behavior was enabled long ago by `c44dd55e` ("support self-hosted
compilation of system GTK headers"), **not** by 25c1dded. Under borg full-tier parallel
load it can cross the 90 s per-unit timeout → flaky TIMEOUT with empty log. borg's own
later runs show `#599` FIXED at `e0ccfaeb` and `#600/#601` FIXED at `523f0295` — a
load/timing artifact plus per-SHA job renumbering (the ticket already flags the numbering
churn), not a code fix. Re-timings here were pure noise (base 39/32 s vs head 26/20 s —
base *slower*).

**Symptom 2 (`test-cjson#00`/`test-lua#00` wrong-output) — shared-/tmp-path parallel race.**
Both runners read a **hardcoded** input path — `test/cjson/runner.c` →
`/tmp/pxx_cjson_input.json`, `test/lua/runner.c` → `/tmp/pxx_lua_input.lua` ("C argv is
not wired yet, so the Makefile copies each case to that fixed path"). The Makefile loop
copies each fixture to that one path, then runs. Under borg's **parallel** full-tier,
concurrent cases clobber each other's input file → the runner serializes a *different*
fixture's document. That is exactly the reported failure ("scalars.json emits
strings.json output") — an input-file race, **not** a miscompile / stale buffer.
Serial runs pass: `make test-cjson` and manual runs here round-trip **all 5** cJSON
fixtures (scalars, strings, nested, floats, floatarr) with a from-HEAD compiler; borg
full is GREEN at `3a6acc11`.

**Disposition:** resolved by investigation, no compiler change. 25c1dded was an innocent
bystander (only commit in the tested range; the cJSON corpus had just landed, so cJSON
was tested for the first time at that SHA). Two follow-ups filed:
- `flaky-corpus-runner-shared-tmp-path` (Track C) — cJSON/lua runners' fixed `/tmp`
  input path races under parallel test execution; give each case a unique path.
- `perf-gtk-system-header-parse` (Track A) — real GTK2 header import is ~20 s / 13619
  procs; parse-perf pass + a scaled per-unit timeout budget so it can't silently flake.

---

## Symptom 1 — pathological compile slowdown (reported as TIMEOUT on borg)
GTK header tests went from sub-second to minutes of compile:

- `tools/testmgr.py --tier full --job 'test-core#599'` at `25c1dded`
  (= `test/test_c_gtk.pas`): **85.1s** local on an idle fast box (unit-class
  norm: 0.5s). On borg under full-tier load it crossed the 90s unit timeout
  → TIMEOUT with empty log.
- `test-core#601` (= `test/test_c_gtk_types.pas`): **68.9s**.

Job numbering is per-SHA (the commit adds tests); at the bad SHA #599/#601
are the GTK-header tests. Guess: statement-expression parsing now does
heavy work (backtracking?) for every `({` / parenthesized-brace sequence in
real-world headers. Perf gate suggestion: GTK header tests should stay
<5s at scale 1.

## Symptom 2 — cJSON corpus wrong-output (FAIL, not slow)
At `25c1dded` with the cjson corpus fetched:

```
--- scalars.expected
-{"id":42,"neg":-7,"name":"alice","ok":true,"bad":false,"nothing":null}
+{"esc":"tab\there","nl":"line1\nline2","quote":"say \"hi\"","back":"a\\b","empty":""}
```

The runner emits the WRONG fixture's content for scalars.json (looks like
the strings.json output) — miscompiled control flow / stale buffer in the
compiled cJSON, not a formatting delta. `test-lua#00` red on borg too,
likely same root cause.

## Repro
```
git checkout 25c1dded
tools/install_lib_candidates.sh cjson
tools/testmgr.py --tier full --job 'test-cjson#00'    # RED, wrong-output
tools/testmgr.py --tier full --job 'test-core#599'    # ~85s (unit norm 0.5s)
```

## Gate
GTK header tests back to seconds; test-cjson/test-lua green with corpus
present; statement-expression feature tests still green.
