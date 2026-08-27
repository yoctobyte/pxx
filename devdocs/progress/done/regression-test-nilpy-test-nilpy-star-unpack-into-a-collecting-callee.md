---
prio: 70
track: N
status: done
owner: agent-A
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **This expectation records a REFUSAL** (TypeError). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_star_unpack_into_a_collecting_callee.npy red at b4d62b3dcfde (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-26T17:07:22Z
- **Test source:** test/test_nilpy_star_unpack_into_a_collecting_callee.npy test/test_nilpy_star_unpack_into_a_collecting_callee.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_star_unpack_into_a_collecting_callee.npy'` at b4d62b3dcfde3189556650457d574c72a975c90f

## Range
> **The named sha `b4d62b3dcfde` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b4d62b3dcfde`, last good `90892318c94c`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:46: error: expected expression
(tail)
pascal26:46: error: expected expression
  near: print  c  take  >>>  xs  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Root cause (2026-08-27)

**Not the star-unpack machinery at all — the OVERLOAD PROBE.**
`FindUMethOverloadAhead` (`compiler/pasparser_call.inc`) picks a method
overload by parsing the call's arguments SPECULATIVELY with `ParseArgExpr` to
learn their types, then rewinding. A `*` is not an expression, so the probe
reported `expected expression` — and `Error` HALTS, so the probe's own
"unsupported arg shape" escape (`nArgs <> nExplicitArgs`, further down) was
never reached. A perfectly well formed call died inside a routine whose entire
job is to look and put the tokens back.

The file already documents this exact failure mode twice, for the two shapes
found before this one: `**` dict-keywords (`PyDictKwOverloadAhead`) and an
`array of const` `[...]` literal (`ArgListHasBracketElem`), each answered
*before* the probe runs. `*` is the third sibling and was missed —
`normalise-dont-special-case.md`'s grep-for-the-sibling rule, one shape late.

**Why the boundary looked like a call-site rule.** Measured:

| call | fixed params | written+receiver | result |
| --- | --- | --- | --- |
| `c.take(*xs)`  | 1 (self)    | 1 | FAIL |
| `c.take(0,*xs)`| 1           | 2 | ok   |
| `c.two(*xs)`   | 2 (self,x)  | 1 | ok   |
| `c.two(1,*xs)` | 2           | 2 | FAIL |

Failure tracks "written arguments already fill the fixed parameters" — which is
not a rule about stars, it is the probe's own arity filter deciding whether it
gets to RUN. Both rows are the one cause.

## Fix

`ArgListHasStarUnpack(lp)` beside `ArgListHasBracketElem`: a token-level walk
for a `*` at argument-start at bracket depth 0 (`**` lexes as two `tkStar`, so
one test covers both). Gated `isNilPy` and answered before the probe; selection
falls back to `FindUMethArity`, which is what these calls had before the probe
existed — and arity is all that is knowable anyway, since an unpacked list's
length is a runtime value.

## Verified

- `test_nilpy_star_unpack_into_a_collecting_callee` — byte-identical to
  `.expected` (all 30 lines).
- `c.take(*xs)` / `c.two(1,*[9])` / `c.two(*xs)` — all match the CPython oracle.
- `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Note for whoever takes `feature-a-error-does-not-halt-so-a-parse-can-be-speculative`

This ticket is that feature's third bug report. Three shapes have now been
patched around, one at a time, each with a token-level pre-check that duplicates
knowledge the parser already has. The probe cannot be made shape-complete by
enumeration — the next construct that is not an expression will do this again.
An `Error` that a speculative parse can CATCH removes the whole class, and the
`nArgs <> nExplicitArgs` escape already sitting below the loop is the recovery
path it would restore to service.
- 2026-08-27 — resolved, commit fbf1579f2.
