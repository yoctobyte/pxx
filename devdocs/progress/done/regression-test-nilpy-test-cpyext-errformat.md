---
prio: 70
status: done
owner: agent-an-night
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_cpyext_errformat.npy red at 36d1bffda39d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T15:21:24Z
- **Test source:** test/test_cpyext_errformat.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_cpyext_errformat.npy'` at 36d1bffda39d58099b403745c48b95cd8c1d7c58

## Range
bad `36d1bffda39d`, last good `0d8e7393a09c`, 14 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
/tmp/testmgr-scratch-3177678/test_cpyext_errformat26: symbol lookup error: /tmp/testmgr-scratch-3177678/test_cpyext_errformat26: undefined symbol: __pxx_PyErr_Message
(tail)
ok: /tmp/testmgr-scratch-3177678/test_cpyext_errformat26  [code=2492974B  data=53456B  bss=33108B  procs=2333]
/tmp/testmgr-scratch-3177678/test_cpyext_errformat26: symbol lookup error: /tmp/testmgr-scratch-3177678/test_cpyext_errformat26: undefined symbol: __pxx_PyErr_Message

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Root cause (2026-08-15, verified at HEAD)

Not a cpyext bug at all — the non-transitive `uses` flip (56a540143 /
63d1d0de9) applied Pascal's unit-visibility rule *between C translation
units*.

`test/nilpy_units/fmt_ext.pas` says
`uses pxxcio, '../../lib/cpyext/src/pyruntime.c', './fmt_ext_host.c';`.
Each `.c` becomes its own unit index, and neither names the other, so
`fmt_ext_host.c`'s `extern const char *__pxx_PyErr_Message(void);` found no
visible bodied proc, stayed a real external, and the program died at LOAD:
`undefined symbol: __pxx_PyErr_Message` (also `PyErr_Clear`, `PyErr_Format`).
All five cpyext tests failed the same way. `--no-strict-uses` did not help —
the rule is unconditional as of 56a540143.

C has no `uses`. Its external-linkage names live in ONE flat namespace shared
by every TU; an `extern` prototype in one `.c` binding to a definition in
another `.c` is the language rule (gcc/ISO C), and no source clause could
express it. So the Pascal rule stops at that boundary:

- `CTUnitIdx`/`CTUnitCount` (defs.inc) record every `.c` SOURCE pulled as a
  unit; marked in parser.inc's `isCUnit` branch. A `.h` is deliberately NOT
  marked — a header pulled through `uses` names a foreign library's exports,
  which must stay real externals.
- `VisibilityAllows` (symtab.inc) answers True when both sides are C TUs.

Verified: all five cpyext tests produce their expected output byte for byte
(errformat, hello, args_errors, containers, markupsafe, cython). Gate quick +
self-host fixedpoint GREEN.
- 2026-08-15 — resolved, commit c304fca4d.
