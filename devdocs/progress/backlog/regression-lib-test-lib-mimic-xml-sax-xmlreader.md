---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 10 is `tools/expect_same.sh lib_mimic_xmlreader.1 "$(/tmp/lib_mimic_xmlreader | grep -c '=ok')" "25"`. The job's own `src` (`test/lib_mimic_xml_sax_xmlreader.npy`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `lib_mimic_xml_sax_xmlreader`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **The NAMED SHA cannot be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged, and it was not bisected. **That is a statement about ONE commit, not about the range**: this job still reads live `lib/**`, `test/**` and the Makefile, so a commit BELOW the named sha can have caused it. Read the Range section before concluding anything — it says how many commits here the job can actually observe, and it is the section that will tell you when the answer is genuinely the box.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/lib_mimic_xml_sax_xmlreader.npy at 2b2ec3fee1c5 in step 2/10, `tools/expect_same.sh lib_mimic_xmlreader.1 "$(/tmp/lib_mimic_xmlreader | grep -c '=ok')" "25"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-17T18:11:48Z
- **Test source:** test/lib_mimic_xml_sax_xmlreader.npy tools/expect_same.sh
- **Failing step:** line 2 of 10 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh lib_mimic_xmlreader.1 "$(/tmp/lib_mimic_xmlreader | grep -c '=ok')" "25"
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_mimic_xml_sax_xmlreader.npy'` at 2b2ec3fee1c5c5f34462f649a12fa17b66eec278

## Range
bad `2b2ec3fee1c5`, last good `9b8475d4e99e`, **1 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
note: xml_sax_xmlreader -> mimic_xml_sax_xmlreader (shim, subset)
ok: /tmp/testmgr-scratch-758032/lib_mimic_xmlreader  [code=1380120B  data=94012B  bss=70100B  procs=2228]
expect_same: MISMATCH [lib_mimic_xmlreader.1]
--- expected
+++ actual
@@ -1 +1 @@
-25
+24

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-09-19 (frankH) — bisected to the v410 -> v411 pin: a compiler/builtin regression

The watcher cannot narrow this: its one observable commit is the v411 pin
(`8d9d69bdc`). Differential, each pinned binary with its own frozen builtin
extracted from git, over identical live `lib/` and the row's exact command:

| pinned binary | result |
| --- | --- |
| v410 `c599e8546121` | 25/25 |
| v411 `bc884808fda5` | 24/25, `name_by_qname=FAIL got "('http://www.w3.org/1999/xlink', 'href')"` |

HEAD's compiler also answers 24. So the cause is in the compiler or builtin
build inputs between `764ee2ed2` (v410) and `9b8475d4e` (v411's source), in
the NilPy lane. The symptom is a tuple arriving as its repr STRING. It is also
the sole new red that stopped auto-pin in the first five verdicts after v411:
see bug-t-armed-autopin-has-refused-62-consecutive-times-... .

