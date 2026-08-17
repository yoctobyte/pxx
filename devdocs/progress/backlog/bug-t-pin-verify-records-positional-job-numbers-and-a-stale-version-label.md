---
track: T
prio: 55
type: bug
blocked-by: []
summary: "The pin_verify record is unattributable and mislabelled. Its `red` list stores POSITIONAL job names (`lib-test#117`), which name a different file as soon as the job list changes — resolved at HEAD, lib-test#117 is lib_tls.pas; resolved at the verified sha it is lib_tls13_keys.pas. And its `ver` said v347 while the verified tree carried pin 346. Neither unattributed red reproduces under either pin."
---

# `pin_verify` records positional job numbers and a stale version label

- **Type:** bug (report format) — **Track T** (owns `tools/testmgr.py` and the
  report format). Filed, not fixed: T owns its own tooling.
- **Found:** 2026-08-17 by frank3, asked to attribute three reds from the
  `pin_verify` record. Two of the three could not be attributed *from the record
  at all*, which is the finding.
- **Measured against:** the record in `devdocs/progress/tstate/plexus.json`, and
  binaries v346 / v347 extracted from git.

## The record

```json
"pin_verify": {
  "date": "2026-08-17T21:28:40Z",
  "red": ["lib-test#36", "lib-test#117", "test-nilpy#12"],
  "sha": "08bdf27290b79f9f40711b2051922e300df52208",
  "tier": "full", "ver": "v347", "verdict": "RED"
}
```

## Defect 1 — the version label is wrong

`sha 08bdf2729` is a docs commit at **22:26:29** local. The v347 pin commit
`f5da30bc9` landed at **22:27:54**, 85 seconds later, and 08bdf2729 is its
ancestor. The pin version *in that tree* is therefore 346:

```
$ git show 08bdf2729:stable_linux_amd64/default/VERSION
346
```

So a record labelled `"ver": "v347"` verified a tree pinned at **v346**. The
label appears to be taken from the pin state at *report* time rather than from
the tree at the *verified sha*. Anyone reasoning "v347 is red, the pin I just
took is bad" — the natural reading, and the one that actually happened — is
reasoning about the wrong pin.

## Defect 2 — `red` stores positional names, so it is unattributable

`Job.name` is positional (`tools/testmgr.py:1163`):

```python
self.name = "%s#%02d" % (target, index)
```

`index` is the job's position in the target's `make -n` recipe, so **every
`#NN` shifts when a test is added or removed**. Measured, resolving the same
three names two ways:

| name | resolved at the verified sha | resolved at HEAD |
| --- | --- | --- |
| `lib-test#36` | `test/crtl_exp2.c` | `test/crtl_exp2.c` (+ merged group) |
| `lib-test#117` | `test/lib_tls13_keys.pas` | **`test/lib_tls.pas`** |
| `test-nilpy#12` | `examples/tk/field_class_identity.npy` | **`examples/tk/uses_tkinter_and_configparser.pas`** |

Two of three name a **different file** depending on which sha you resolve
against — and nothing in the record says which to use. Between those two shas a
`test-nilpy` job was inserted at Makefile line ~302, shifting everything after
it.

testmgr already has the fix in hand and uses it elsewhere: `Job.sel` ("stable
selector", `tools/testmgr.py:1173`), and `open_regressions` stores exactly that
alongside the display name:

```json
{"name": "lib-test#36", "job": "lib-test#src:test/crtl_exp2.c", ...}
```

**`pin_verify.red` stores only the positional half.** That is precisely why
`lib-test#36` was the one red anybody could attribute — not because it was
better understood, but because it independently appears in `open_regressions`
where the stable selector is recorded.

**Fix:** store the `src:` selector in `pin_verify.red` (either instead of, or
alongside, the display name), and take `ver` from the verified tree.

## What the three reds actually were

Reproduced by hand, with binaries extracted from git so each is a named sha:

| job | file | v346 | v347 |
| --- | --- | --- | --- |
| `lib-test#36` | `test/crtl_exp2.c` | — | known open regression, `timeout`, opened 15:39, `pin_built: true` |
| `lib-test#117` | `test/lib_tls13_keys.pas` | **pass** (5 ok / 0 FAIL) | **pass** (5 ok / 0 FAIL) |
| `test-nilpy#12` | `examples/tk/field_class_identity.npy` | **compiles** | **compiles** |

`field_class_identity.npy` also compiles with a HEAD-built compiler, producing
byte-identical output sizes under all three.

**The pin-lag hypothesis is disconfirmed.** A `lib/**` job that needs a
post-pin compiler behaviour would fail under the old pin and pass under the new
one; `lib-test#117` passes under *both*. And `test-nilpy#12` is `pin_built:
false` — it builds with the HEAD compiler, so the pin cannot be its cause
either.

And the stable per-job map in the same file already says so:

```
lib-test#src:test/lib_tls13_keys.pas                pass
test-nilpy#src:examples/tk/field_class_identity.npy pass
```

Only **three** jobs are non-`pass` in the whole map: `crtl_exp2.c` (`timeout`,
the known regression) and two `lib_synapse` jobs (`skip` — `external/` is absent
in the watcher's clone, which is the guard in `Makefile`/`install_externals.sh`
behaving as designed).

So the two unattributed reds are most likely **transient** — timeout or resource
contention during a 186-job parallel `lib-test`, the same class as `crtl_exp2`'s
recorded `timeout`. Not proven; but they do not reproduce, and the per-job map
disagrees with the pin_verify list.

## Why this is worth 55

A RED verdict nobody can attribute is worse than a red nobody has looked at: it
is *read*, it dispatches work, and here it dispatched a hunt for a bad pin that
was not bad. The failure is not that the run found reds — it is that **the record
does not carry enough information to identify what went red**, so the reds cannot
be confirmed, dismissed, or tracked across runs. Positional identity also means
two runs' red lists cannot be compared at all if the job list changed between
them, which quietly undermines `new_red` / `fixed` diffing whenever a test is
added.

## Gate

`pin_verify.red` entries resolve to a file without knowing the sha, and `ver`
matches the pin version in the verified tree. A regression test can construct
two job lists differing by one inserted job and assert the recorded identity is
unchanged.
