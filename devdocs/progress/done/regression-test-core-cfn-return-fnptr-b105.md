---
prio: 70
track: C
owner: frankD
summary: "FIXED at 2148d95fa (frankD) — an UNINITIALISED READ, not the declarator collision I guessed. A function RETURNING a function pointer, `void (*look(int a))(void)`, no longer parses — `more than 16 parameters not supported (MAX_PROC_PARAMS)`. Three-line repro. The declarator shape NEXT DOOR to the function-typed PARAMETER that d71642873 added, and that new feature itself works. THE AUTO-FILED RANGE IS WRONG: it points at 18b3ec2a6, but my optdiff log at 9df0058fe already shows this file BUILD-FAIL, one commit after d71642873 and two before the blamed sha. Do not bisect toward the i386 commit."
status: done
---

> **Track guessed as C from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/cfn_return_fnptr_b105.c /tmp/cfn_return_fnptr_b10526`, which names `test/cfn_return_fnptr_b105.c`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/cfn_return_fnptr_b105.c at 65b719ab48ae in step 1/2, `./compiler/pascal26 test/cfn_return_fnptr_b105.c /tmp/cfn_return_fnptr_b10526` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-02T00:40:16Z
- **Test source:** test/cfn_return_fnptr_b105.c tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/cfn_return_fnptr_b105.c`.
  ```
  ./compiler/pascal26 test/cfn_return_fnptr_b105.c /tmp/cfn_return_fnptr_b10526
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/cfn_return_fnptr_b105.c'` at 65b719ab48ae3a2af0ba5acea881cbb891fe6eca

## Range
> **The named sha `65b719ab48ae` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `65b719ab48ae`, last good `49d0ac95f76d`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:21: error: C function definition: more than 16 parameters not supported (MAX_PROC_PARAMS)
(tail)
pascal26:21: error: C function definition: more than 16 parameters not supported (MAX_PROC_PARAMS)
  near: z      >>>   v 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triaged (frankZ, plexus, 2026-09-02) — bounded, and the filed range is wrong

Reproduces at HEAD, binary `e7376b4065be84f6`, `converged after 1 round(s)`.

### Three-line repro

```c
void t(void){}
void (*look(int a, int b))(void){ (void)a; (void)b; return t; }
int main(void){ return look(1,2)==t ? 42 : 1; }
```
```
pascal26:2: error: C function definition: more than 16 parameters not supported (MAX_PROC_PARAMS)
```

`test/cfn_return_fnptr_b105.c`'s own header says why it exists: *"sqlite's
sqlite3OsDlSym uses this shape and must be registered as a real function, not
skipped as a function-pointer variable declaration."*

### The boundary — four probes

| declarator | |
|---|---|
| `void (*p)(void) = t;` — function-pointer VARIABLE | ok |
| `int apply(int cb(int), int x)` — function-typed PARAMETER | **ok** |
| `void (*look(int a))(void) { ... }` — function RETURNING a fn ptr | **BROKEN** |
| the same with a forward declaration as well | **BROKEN** |

**The feature `d71642873` added works.** It is the sibling declarator that
broke — the shape `normalise-dont-special-case.md` warns about, where two
readings of one syntax diverge.

### DO NOT BISECT TOWARD `18b3ec2a6`

The stub says last-good `49d0ac95f76d`, bad `65b719ab48ae`, 2 commits in range,
which points at `18b3ec2a6 feat(A): i386 passes a by-value record...`. That is
not it, and the linear range lies here because `49d0ac95f76d` is a tstate commit
off seven's line:

```
d71642873 ancestor of 49d0ac95f76d ?  NO
d71642873 ancestor of 9df0058fe    ?  YES
```

and my own `optdiff --shard 1/12` log **at `9df0058fe`** already lists
`cfn_return_fnptr_b105.c` under `BUILD-FAIL` — recorded before `18b3ec2a6`
existed. So it was broken one commit after `d71642873` and two before the sha
the watcher blamed. This is the auto-filer's documented weakness (*"the named
sha CANNOT be the cause"*) in a sharper form: the RANGE, not just the sha, can
be wrong when the last-good comes from another host's line.

### Mechanism — a HYPOTHESIS, and it was WRONG (see the section below)

Not instrumented; recorded so it can be confirmed or discarded rather than
re-derived. `void (*look(A,B))(void)` contains, inside the parens, exactly the
`name(params)` shape `CParseFnSigGroup` now claims for a function-typed
parameter. But that spelling only MEANS a function-typed parameter **inside a
parameter list**; at declarator level within `(*...)` it is a function
declarator whose return type is the outer `(void)`. If the shared path is
entered there, the inner list is eaten as the pointer's params, `)(void)`
desyncs, and the body is read as further parameters — which fits `near: z >>> v`,
`z` being the last inner parameter and `v` the first token of
`return v->xSym(...)`.

### Owner

**frankD**, who wrote `CParseFnSigGroup` and is in `cparser.inc` now. Told with
this boundary and the repro; deliberately not taken in parallel, because two
agents on one question is the collision git cannot see. Reassign to whoever
picks it up if that changes.

## FIXED — `2148d95fa` (frankD), and my mechanism was wrong

Verified at HEAD, binary `f28b7828e18d4d5f`, `converged after 2 round(s)` from
the pin: the three-liner returns 42 and `test/cfn_return_fnptr_b105.c` returns
42.

**The cause was an uninitialised read, not a shared-path desync.**
`ParseCSubroutine` has a `paramsOverflow` local checked AFTER the `fnRetIsFunc`
branch and assigned in only ONE arm — the `not fnRetIsFunc` parameter loop.
`void (*look(int a))(void)` takes the other arm, parses no parameter list of
its own, and so never writes it; the check then read whatever the stack held.
frankD moved the initialiser above the branch.

**My hypothesis above is kept, struck, because being wrong in a specific way is
the useful part.** It fitted the four probes I had. It does not fit the fifth
probe I did not run: `void (*look(void))(void)` — the ZERO-parameter shape —
stayed green through the whole outage. A parser desync would have hit that too.
The uninitialised read explains it exactly: the stack slot happened to hold
zero there. So the boundary table I built was real and the reading I put on it
was not, and the missing probe is the one that would have discriminated the two
readings. *Vary the shape until it stops failing* — I varied it four ways and
stopped at the first coherent story.

`CParseFnSigGroup` was the **trigger and not the defect**: it changed what was
on the stack. A change that cannot touch a variable and still moves its value is
the tell for an uninitialised read, and I read it as ownership of a shared path
instead.

**The attribution half stands and is why this stays filed.** The auto-filed
range is still wrong — `49d0ac95f76d` is a tstate commit off seven's line, so
the "2 commits in range" is not a range of this line's commits at all, and it
blames `18b3ec2a6`. Anyone bisecting on that stub goes the wrong way. That is
not superseded by the fix.

frankD's `test/c_fn_returning_fnptr_params.c` (6 rows against gcc) covers the
shape going forward; its row 1 is deliberately the zero-parameter case,
labelled, because a test built around that alone would have proved nothing.

## Log
- 2026-09-02 — auto-closed by the seven watcher: `test-core#src:test/cfn_return_fnptr_b105.c` passes at 588d8512f101 (tier native); it was red at 65b719ab48ae. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
