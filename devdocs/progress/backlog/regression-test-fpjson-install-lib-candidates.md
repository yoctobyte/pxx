---
prio: 70
track: B
---

> **Track guessed as B** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/dev has advanced 11 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-fpjson#src:tools/install_lib_candidates.sh red at 99f1dc81a039 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-26T07:38:43Z
- **Test source:** tools/install_lib_candidates.sh test/fpjson/testutils.pas +1

## Repro
`tools/testmgr.py --tier full --job 'test-fpjson#src:tools/install_lib_candidates.sh'` at 99f1dc81a039d8785db504b9f9b8917cf4e59783

## Range
> **The named sha `99f1dc81a039` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `99f1dc81a039`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
compiling fpjson suite runner ...
FAIL  TTestFactory.ObjectCreateInteger: "Correct class" expected: <TMyInteger> but was: <TMyInt64>
test-fpjson: FAIL (exit 0)
== suite TTestIterator (8)
> TTestIterator.TestNull
> TTestIterator.TestInteger
> TTestIterator.TestInt64
> TTestIterator.TestFloat
> TTestIterator.TestBoolean
> TTestIterator.TestString
> TTestIterator.TestArray
> TTestIterator.TestObject
run: 203  failures: 2  errors: 0  ignored: 0
FAIL  TTestFactory.ArrayCreateInteger: "Correct class" expected: <TMyInteger> but was: <TMyInt64>
FAIL  TTestFactory.ObjectCreateInteger: "Correct class" expected: <TMyInteger> but was: <TMyInt64>

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
