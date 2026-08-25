---
prio: 45
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/lib_mimic_xml_etree_elementtree.npy red at fd93e4a71c37 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-22T21:01:39Z
- **Test source:** test/lib_mimic_xml_etree_elementtree.npy

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_mimic_xml_etree_elementtree.npy'` at fd93e4a71c37a7932b9ef73e4c9f8a7deceb3c34

## Range
bad `fd93e4a71c37`, last good `98ed38202254`, 137 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
note: xml_etree_elementtree -> mimic_xml_etree_elementtree (shim, subset)
ok: /tmp/testmgr-scratch-3295108/lib_mimic_xml_etree  [code=2358728B  data=61689B  bss=51420B  procs=1788]
Unhandled exception: TypeError: can only concatenate str (not "method") to str

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
