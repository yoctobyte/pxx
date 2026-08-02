---
prio: 70
status: done
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_dataclass_dict_factory.npy red at 2fbb5a270acc (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-02T12:56:11Z
- **Test source:** test/test_nilpy_dataclass_dict_factory.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_dataclass_dict_factory.npy'` at 2fbb5a270accfcafd3583cb605a91d0a8742149b

## Range
bad `2fbb5a270acc`, last good `01d3efe7739d`, 4 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-756523/test_nilpy_dcdict26  [code=1240842B  data=33064B  bss=8572B  procs=1102]
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## Resolved 2026-08-02 — commit e1e9ea07a

The triage was right on every point: `2fbb5a270` is innocent, and `ef73cf545`
was the only code change in the range and was the cause. Mine.

That commit generalised the class-attribute branches in `PyRegisterClassMembers`
to match `name : ann = value` — which is precisely how a `@dataclass` field is
written. Those branches run BEFORE the `isDC` ones, so a dataclass's fields were
registered as ordinary class attributes and never reached the branches that
record their defaults into the `PyDc*` tables and build the generated ctor. Hence
the segfault, and hence a `field(default_factory=dict)` test being the one to
catch it.

Fix: the annotated shape is a PLAIN class's attribute only. A dataclass keeps the
pre-existing unannotated-only rule, so its behaviour is exactly what it was.

`test/test_nilpy_annotated_class_attribute.npy` now carries a `@dataclass` with
`str` / `float` / `default_factory=list` fields as a permanent control — the
interaction is pinned rather than remembered.

Gate: `gate.sh quick` GREEN, self-host fixedpoint byte-identical, both dataclass
tests green.

Filed by the Track B agent rather than by me; the range table saved the next
reader a bisect against a tickets-only commit.
- 2026-08-02 — resolved, commit e1e9ea07a.
