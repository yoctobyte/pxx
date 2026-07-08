---
prio: 75
---

# regression: 25c1dded (GNU statement expressions) — 150x cfront slowdown on GTK headers + cJSON/lua corpus breakage

- **Type:** regression (cfront). Track C. Single-commit range, verified locally at the SHA.
- **Found:** 2026-07-08 by Track T (borg full run at `25c1ddedcccb`); reproduced in a
  throwaway clone at that SHA.
- **Suspect commit:** `25c1dded` "feat(cfront): GNU statement expressions (({ ...; expr; })) (00214)" —
  only commit in the tested range.

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
