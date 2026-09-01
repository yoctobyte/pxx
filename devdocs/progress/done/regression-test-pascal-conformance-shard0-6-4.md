---
prio: 45
track: P
type: regression
status: done
found: 2026-08-31
found-by: twatch (seven)
triaged: 2026-09-01
triaged-by: claude-T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 0/6`. The job's own `src` (`tools/run_pascal_conformance.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard0/6 at aac20e75ed1f in step 1/1, `tools/run_pascal_conformance.sh ./compiler/pascal26 libr` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-08-31T05:36:10Z
- **Test source:** tools/run_pascal_conformance.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/run_pascal_conformance.sh`.
  ```
  tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 0/6
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard0/6'` at aac20e75ed1f58d94b12d8d4aea9fdff9356dad5

## Range
> **The named sha `aac20e75ed1f` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `aac20e75ed1f`, last good `17fd5566a65e`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL tgeneric32.pp — compile error:
pascal26:15: error: unknown type: TFoo$Integer
pascal26:18: error: undefined variable (TFoo$Integer)
FAIL tgeneric49.pp — compile error:
pascal26:14: error: expected 'begin' before 'deprecated'
(tail)
eric
SKIP tgeneric21.pp — gap: accepts-invalid — nested generic-in-generic declaration — semantics unverified, real gap (see bug-pascal-missing-diagnostics-fail-tests triage 2026-07-11)
FAIL tgeneric32.pp — compile error:
    pascal26:15: error: unknown type: TFoo$Integer
      near: : TFoo < Integer > ; >>> begin FooInt := 
    pascal26:18: error: undefined variable (TFoo$Integer)
      near: begin FooInt := TFoo < Integer >>> > . Create 
FAIL tgeneric49.pp — compile error:
    pascal26:14: error: expected 'begin' before 'deprecated'
      near: < T > = class end >>> deprecated 'Message A' ; 
SKIP tgeneric5.pp — gap: objfpc generic syntax + `typeinfo(_T)` intrinsic and typinfo unit
SKIP tgeneric65.pp — gap: generic record with nested `object` type
SKIP tgeneric76.pp — gap: generic record with static class methods + specialized aliases (TPointEx<T>) unsupported
SKIP tgeneric92.pp — gap: objfpc generic syntax + `with` over a generic type parameter record
SKIP tgenfunc19.pp — gap: generic global function + class helper method resolution via specialize
SKIP tgenfunc5.pp — gap: generic instance methods (objfpc generic function ... <T>)
SKIP tinterface4.pp — wontfix: needs FPC's `variants` unit and FPC's IInterface/NewInstance refcount internals
SKIP tmoperator2.pp — gap: record Initialize/Finalize management operators with managed fields
SKIP tmoperator8.pp — gap: management operators AddRef/Copy/Initialize/Finalize on records
SKIP tover1.pp — gap: overload resolution across shortstring/ansistring/widestring/pchar params
SKIP tprocvar3.pp — gap: delphi-mode procvar of object, @-less proc assignment, codepointer method addresses
SKIP tset2a.pp — gap: explicit enum ordinal values (dA:=8) + {$packset 1} packed-set semantics
SKIP tstring11.pp — gap: overload resolution RawByteString vs UnicodeString (char/array/pchar args)
test-pascal-conformance: 59 pass, 2 fail, 26 skip, 5 auto-gated (of 92)
test-pascal-conformance: FAILURES: tgeneric32.pp(compile) tgeneric49.pp(compile)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Triage (claude-T, seven, 2026-09-01) — re-laned T -> P

**The fallback lane was wrong, as its own banner warned. This is Track P.**
Neither failure is a Track T defect; the harness reported correctly.

**This stub already contained the answer on 2026-08-31T05:36:10Z.** Both
failing tests are named in the log tail, and the Range section already said
`1 commit(s) in range`. Two agents spent an evening re-deriving that by hand
before anyone opened the ticket. Nothing below is new information about the
tree; it is the triage the stub asked for.

### There are TWO failures, and they are unrelated

Confirmed by running the shard directly on seven at HEAD
(`tools/run_pascal_conformance.sh --shard 0/6 --report`):

```
test-pascal-conformance: 59 pass, 2 fail, 26 skip, 5 auto-gated (of 92)
FAILURES: tgeneric32.pp(compile) tgeneric49.pp(compile)
```

**The error string is not a discriminator here.** Both a peer agent and I first
took `expected 'begin' before 'deprecated'` for *the* failure, built repros from
it, and reasoned about the wrong construct. `tgeneric32.pp` contains the token
`deprecated` zero times.

### Failure 1 — `tgeneric32.pp`: specialization anchoring. THIS is the regression.

```
pascal26:15: error: unknown type: TFoo$Integer
pascal26:18: error: undefined variable (TFoo$Integer)
pascal26:19: error: a value of this type has no members
```

Self-contained, no corpus needed:

```pascal
program tgeneric32;
{$MODE DELPHI}
type
  TFoo<T> = class
    constructor Create;
  end;
constructor TFoo<T>.Create;
begin
  inherited Create;
end;
var
  FooInt: TFoo<Integer>;
begin
  FooInt := TFoo<Integer>.Create;
  FooInt.Free;
end.
```

**Prime suspect: `b613b5fcf` "fix(P): a mode-Delphi generic alias anchors at its
USE, not behind the template".** It is the ONLY buildable commit in
`17fd5566a65e..aac20e75ed1f` — the other five touch `devdocs/` only — and the
symptom (a specialization failing to resolve) is what that title describes.

NOT PROVEN. Confirming needs a build at `b613b5fcf`'s parent, which nobody has
done cleanly yet: a peer built a parent and got a result that contradicts
`job_last_pass`, which points at their build rather than at the tree. Whoever
takes this should `sha256sum` the two binaries before trusting a bisect —
`test-selfcompile-odiff` exists in this repo precisely because a stale stamp
once "printed 'verified' three times in one day without building anything".

### Failure 2 — `tgeneric49.pp`: a known gap that is skipped for its sibling

```
pascal26:14: error: expected 'begin' before 'deprecated'
  near: < T > = class end >>> deprecated 'Message A' ;
```

Line 14 closes `TTest<T> = class` with `end deprecated 'Message A';` — a hint
directive on a **generic** class declaration. Change `TTest<T>` to `TTest` and
it compiles; drop the message string and it still fails; the mode is irrelevant
(`tgeneric49.pp` guards `{$mode delphi}` with `{$ifdef fpc}`, and pxx does not
define `fpc`, so it compiles in default mode — all three variants fail alike).

**`tgeneric50.pp` is already in `test/pascal-conformance/pxx.skip`** with the
reason *"gap: hint directives (deprecated/platform/experimental) on generics and
specializations"* — exactly this construct. So the gap is known and waived for
50 and not for 49.

Two readings, and they need different fixes:
1. pxx accepted this by accident and `b613b5fcf` tightened generic parsing into
   the known gap — then it is part of failure 1;
2. it is simply a missing skiplist entry beside `tgeneric50.pp`.

A peer's build at `17fd5566a65e` failed this construct, which favours (2) — but
that is the same build whose result contradicts `job_last_pass`, so it settles
nothing yet. Resolve failure 1 first; this one may fall out of it.

### Ruled out, so nobody re-checks

- **Resharding.** Membership is `(index mod N) == I` over the enumerated suite,
  so a corpus or skiplist change moves files between shards and can fake a
  regression. `git log 17fd5566a65e..aac20e75ed1f -- test/pascal-conformance/
  tools/run_pascal_conformance.sh library_candidates/fpc-testsuite/` is empty;
  last `pxx.skip` change was 2026-08-25. Membership was stable across the break.
- **This job never blocked a pin.** See
  `chore-t-fpc-conformance-noise-skews-priority`. Filing it at prio 70 in Track
  T's backlog is the priority skew, not the defect.

### Why this sits in `backlog-tools/` with `track: P`

The filename is the watcher's; moving it risks the autoticket re-filing a
duplicate stub. The `track:` field is the lane of record.

---

## RESOLVED (claude-T, seven, 2026-09-01) — both failures fixed, shard verified green

```
test-pascal-conformance: 61 pass, 0 fail, 26 skip, 5 auto-gated (of 92)
```

Run on seven against a compiler whose `srchash` MATCHES the tree, so the result
is conclusive in both directions. Leaving the close itself to
`close_stub_tickets()` rather than moving this file by hand.

### Failure 1 — `tgeneric32.pp`: cause CONFIRMED, fixed by `78e3b6426`

The bisect closed. Both verdicts forced to print `converged after` and to name
the binary, after the first attempt was found to be accepting a stamp path that
builds nothing:

```
b613b5fcf^   GOOD   bin=8cb1778e7539
b613b5fcf    BAD    bin=5175d0569e42
```

So `b613b5fcf` is confirmed, and the earlier "prime suspect, NOT PROVEN" above
can be read as settled.

**Root cause.** `b613b5fcf` introduced `DGenDeclAnchor`, which walks forward from
the template to the use to place the minted alias, ending the type section at a
bare routine heading at depth 0. Its heading list held `tkProcedure` and
`tkFunction` only. `constructor` and `destructor` are **soft keywords** here —
`tkIdent`, compared by text — so there is no `tkConstructor` token for a reader
to notice missing. The walk ran straight through the constructor and its body
and anchored the alias after the use. A `procedure` in the same position was
fine, which is why the symptom read as a specialization bug.

Three other heading lists in the same file already spell both soft keywords out
(`:450`, `:921`, `:1105`), and `:450` carries a comment explaining why they need
saying. Four sites, one omission — the file's own convention was already right
three times, and the sibling grep is what turned this from plausible to
confirmed.

**This is not a defect in `b613b5fcf`'s design.** Anchoring at the use is sound;
the regression is one incomplete list inside the new walk.

### Failure 2 — `tgeneric49.pp`: fixed by `9801b0bcb`

The template capture in `pasparser_generic.inc` scans the token array ahead of
the parser and had no equivalent of `pasparser_decl.inc`'s
`SkipHintDirectives`, so it stopped on the `end` and left the outer parser
resuming on the directive. `SkipHintDirectiveToks` is the token-index twin and
shares `IsHintDirectiveName` so the list lives in one place. All five
directives, classes and records.

Verified passing on seven. `tgeneric49.pp` was never in `pxx.skip`, so no
skiplist change was needed.

### Still open, and deliberately NOT folded in

- **`tgeneric50.pp` stays skipped.** Its `pxx.skip` reason names two gaps —
  *"hint directives … on generics **and specializations**"* — and only the
  generics half is closed. The residual is a hint directive on a
  **specialization alias**, which leaves the alias undefined:

  ```pascal
  TTest<T> = class end;
  TOk  = TTest<Integer>;                              { works }
  TBad = TTest<Integer> deprecated 'M' experimental;  { TBad goes undefined }
  ```

  A third site for the same concept, separate from the two template-capture
  terminators. The entry stays accurate for what remains; narrowing its wording
  is a data change, not part of this ticket.

- **The `near:` excerpt defect** surfaced while diagnosing this: correct line
  number, excerpt drawn from an unrelated token stream. Filed separately as
  `bug-p-error-context-near-quotes-an-unrelated-token-stream` — it is not part
  of this regression and folding it in would have buried it.

### Addendum 2026-09-01 — the "still open" item above is closed

The `tgeneric50.pp` specialization-alias arm recorded above as still open **was
fixed the same evening** and `tgeneric50.pp` now compiles clean under a
`srchash MATCH` binary. Two consequences:

- The `pxx.skip` entry for `tgeneric50.pp` is now **stale**, not half-right as
  stated above. Folded into `chore-t-pxx-skip-generic-entries-are-stale`, which
  found it is one of 11 stale generic entries rather than a one-off.
- The `near:` defect's original repro went with it. Re-based on a live 10-line
  pair in `bug-p-error-context-near-quotes-an-unrelated-token-stream`; the
  defect reproduces, the old evidence does not.

Left as a caution for anyone reading this ticket cold: every generic-related
observation in it was written while that area was changing hourly. Re-verify
before acting, and under a compiler whose `srchash` matches the tree — a
failure under a mismatched binary proves nothing.

## Re-verified on plexus (frankZ, 2026-09-02) — still green, and the ticket was never closed

claude-T's fix is confirmed from a second box. `tgeneric32.pp` and
`tgeneric49.pp` both pass; **shard 0/6 is `62 pass, 0 fail, 25 skip, 5
auto-gated (of 92)`** at commit `922dfa971`, binary `0f1d03315f4eaaa7`, corpus
`fpc-testsuite @ 0d122c49534b48`. All six shards are green in the same run —
the table is on [[regression-test-pascal-conformance-shard1-6-2]].

This ticket had said RESOLVED in its body since 2026-09-01 while its frontmatter
still said `status: backlog`, so it stayed wired to
[[umbrella-one-full-tier-run-with-no-red-tier]] as a live blocker for a day.
Closing it now. The write-up above stands as claude-T's.
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
