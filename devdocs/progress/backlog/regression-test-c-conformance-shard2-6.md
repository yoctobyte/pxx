---
prio: 70
---


> **Root cause already diagnosed — see [[bug-c-plain-char-lost-its-type-identity-not-just-its-signedness]].**
> One commit (`07414aa89`) turned plain `char` into an 8-bit integer
> rather than a signed character type. Do not triage this stub
> separately; it goes green when that ticket does.
> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-c-conformance#shard2/6 red at ff1a30aae401 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-03T11:09:51Z
- **Test source:** tools/run_c_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance#shard2/6'` at ff1a30aae4014fa8b6d4b235f5667c2760035e68

## Range
bad `ff1a30aae401`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
SKIP 00207.c — VLA (int a[n], runtime bound) — refused loudly since the silent-zero sizing corrupted the frame; feature-c-vla-via-alloca
FAIL 00219.c — compile error:
    pascal26:2805: error: _Generic: no matching association and no default
      near:       >>>  printf  
test-c-conformance: 35 pass, 1 fail, 1 skip (of 37)
test-c-conformance: FAILURES: 00219.c(compile)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
