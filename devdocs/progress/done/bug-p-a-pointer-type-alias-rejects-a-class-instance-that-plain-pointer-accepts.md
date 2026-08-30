---
slug: bug-p-a-pointer-type-alias-rejects-a-class-instance-that-plain-pointer-accepts
track: P
prio: 75
type: bug
blocked-by: []
status: done
found: 2026-08-30
summary: "v394 breaks Track B's gate: make lib-test is RED at lib_synapse_ssl, because a parameter typed as a Pointer ALIAS (SslPtr = Pointer) no longer accepts a class instance, while a parameter typed as plain Pointer still does. Cross-unit worked on v393 and fails on v394; the SAME-unit case fails on BOTH pins, so v394 did not introduce the defect -- it made the cross-unit path consistent with an already-broken same-unit path. Real vendored Pascal (Synapse) stopped compiling."
owner: frankA
---

# A `Pointer` type alias rejects a class instance that plain `Pointer` accepts

**Track B's gate is RED on the currently blessed pin.** `make lib-test` fails at
`lib_synapse_ssl` under **v394 `e2ea9034a65ea8b6`** (`cc5e02d6c`) and passes
under **v393 `1d69760deabe2865`**. Found by frankB, 2026-08-30, while running
Track B's gate for unrelated work.

```
pascal26:456: error: no overload of SslCtxSetDefaultPasswdCbUserdata matches these arguments
  argument types: (Pointer, class)
  candidates:
    SslCtxSetDefaultPasswdCbUserdata(Pointer, Pointer)
  in: external/synapse/ssl_openssl3.pas
```

The call is `SslCtxSetDefaultPasswdCbUserdata(FCtx, self)`; the declaration is
`procedure …(ctx: PSSL_CTX; u: SslPtr)` in `ssl_openssl3_lib.pas:266`, where
`SslPtr` is an alias for `Pointer`.

## Measured, not reasoned — the isolating table

Same source, two pinned binaries, one factor varied per row. The first
hypothesis (*"a class instance no longer converts to Pointer"*) was **wrong** and
is recorded as wrong: a plain `Pointer` parameter still accepts `self` on both
pins.

| case | v393 | v394 |
| --- | --- | --- |
| cross-unit, **literal `Pointer`** param, plain class | ok | ok |
| cross-unit, **alias** `SslPtr = Pointer` param, plain class | ok | **FAIL** |
| cross-unit, **alias** param, derived class | ok | **FAIL** |
| cross-unit, literal `Pointer` param, derived class | ok | ok |
| **same-unit**, alias param, plain class | **FAIL** | **FAIL** |

**The alias is the trigger. Class derivation is irrelevant** — it was in the
first repro only because Synapse's class is derived, and dropping it changes
nothing.

## The finding that reframes it, and it is the reason this is filed as a bug

**The same-unit case fails on BOTH pins.** So v394 did not introduce a defect;
it made the **cross-unit** path agree with a same-unit path that was already
broken. The likely mechanism — **stated as a hypothesis, not measured**, because
this is a frontend internal and nobody should record a root cause they did not
diff — is that cross-unit alias resolution previously *lost* the alias and saw
plain `Pointer`, and now preserves it, hitting the same rejection the same-unit
path always had.

If that is right, the real defect is the older one: **a `Pointer` alias should
accept exactly what `Pointer` accepts**, since it *is* `Pointer`. Fixing only
the cross-unit regression would restore Synapse and leave the same-unit arm
broken — the classic double-case where the second arm is the one that stays
broken (`devdocs/dev/normalise-dont-special-case.md`). Fix the alias's
assignability, not the unit boundary.

## Minimal repro (same-unit form — fails on both pins, so no binary hunting needed)

```pascal
program m;
type
  SslPtr = Pointer;
  TD = class
    procedure Go;
  end;
procedure Takes(ctx: Pointer; u: SslPtr);
begin
  if (ctx = nil) and (u = nil) then writeln('n');
end;
procedure TD.Go;
begin
  Takes(nil, self);          { error: no overload of Takes matches these arguments }
end;
var d: TD;
begin
  d := TD.Create; d.Go; writeln('ok');
end.
```

Split `SslPtr` and `Takes` into a separate unit to get the v393/v394 differential.

## Track, and why it might be A

Filed **P** (Pascal overload resolution / assignability is dialect semantics).
**If the fix lands in `defs.inc` / `symtab.inc` type identity it is a Track A
change** and should be re-filed or self-resolved per the combined-track rule.
Whoever picks it up should decide that on the first read rather than assuming
this frontmatter got it right.

## Impact and what is NOT known

- **Track B's gate is red**, so B cannot land anything with a green gate until
  this is fixed or the pin is reverted.
- `lib-test` **aborts** at `lib_synapse_ssl`, so every job after that line is
  **unrun on v394**. The blast radius is at least this; it is not known to be
  only this, and nobody should read "one test fails" from an aborted suite.
- CLAUDE.md's compat table puts this squarely in bug territory rather than
  compat: *"real Pascal source compiles wrong, or not at all → bug."* Synapse is
  vendored third-party Pascal that compiled yesterday.

## The diagnostic is its own tell — the renderer resolves the alias, the checker does not

Spotted by frank-coordinator on an independently-written repro; confirmed here
against the captured output rather than taken on report. The declaration is

```pascal
procedure Takes(ctx: Pointer; u: SslPtr);
```

and the rejection prints

```
argument types: (Pointer, class)
candidates:
  Takes(Pointer, Pointer)
```

**`SslPtr` has become `Pointer` in the candidate line.** So whatever renders
candidates already normalises the alias to its underlying type, while the
assignability check that rejected the call did not reach the same answer. Two
layers disagreeing about the same type, one of them correctly.

That is a much narrower place to look than "alias resolution": the resolved form
demonstrably exists and is reachable at diagnostic time. The question is why the
check is deciding on the unresolved one.

**Binding constraint for whoever fixes it — both arms, or it is not fixed.** The
same-unit case fails on both pins (table above). A fix that restores only the
cross-unit path makes Synapse compile and leaves the older arm broken, which is
exactly the sibling that stays broken in
`devdocs/dev/normalise-dont-special-case.md`. Grep for the sibling before closing:
the acceptance is that BOTH the same-unit and cross-unit alias forms accept a
class instance, verified by value, not that `lib_synapse_ssl` goes green.

## Status: pin reverted, this is no longer blocking

v394 was reverted to v393 as `b8fd07377`, so Track B's gate is green again and
nothing is blocked on this. It stays **urgent** because the defect is real, older
than v394, and will re-break the gate the moment a pin carries the change again —
the revert bought time, it did not fix anything.

Collateral, recorded so it is not discovered later:
[[feature-lib-tkinter-grid-pad-accepts-a-two-tuple]] was closed against v394 and
has been **reopened**, verified failing again on the reverted pin. It closes on
the next pin that carries `51b0753e7`.

---

## Resolved 2026-08-30 (frankA) — one cause, three symptoms, two eras

**Root cause: `RegisterGeneralAlias` (`compiler/symtab.inc`) recorded
`AliasElemTk := tk`** — conflating *"what kind is T?"* with *"what does T point
AT?"*. Invisible for non-pointer aliases, where nothing reads the element. For
pointer aliases every general alias recorded a `tyPointer` element regardless of
target:

| alias | recorded elem | correct |
| --- | ---: | ---: |
| `= Pointer` | 17 | 0 (untyped sentinel) |
| `= PChar` | 17 | 3 |
| `= PRec` | 17 | 5 |
| `^Pointer` | 17 | 17 — right, by coincidence |

**Fix:** `ParseTypeKind` has just run for the right-hand side — the same reason
`LastTypeStrCap` is readable four lines below — so the target's own pointer facts
are live in the `LastTypePointer*` globals. Record those. Non-pointer aliases keep
prior behaviour exactly; the subrange call site can never reach the new branch
(it passes only `tyChar`/`tyInteger`). Landed `9b01b1b9b`.

### The ticket's framing was right to distrust itself, and the correction matters

The ticket says v394 *"made the cross-unit path agree with an already-broken
same-unit path"*, and a two-cause reading was circulated on top of it. **Both are
wrong, and the premise was checkable:** the `MatchParamCompatible` narrowing
(`8b75fcabd`, 08-28 00:46) **is** an ancestor of the v393 pin (`d3f9dee6c`), and
the pinned v393 binary reproduces the same-unit repro with the identical error.
There was never a second cause.

**What actually differed between the pins is DETERMINISM, and this is the finding
worth carrying off this ticket.** Measured on v393, the overload symptom is
**position-dependent**:

| shape | v393 | v394 | fixed |
| --- | --- | --- | --- |
| same-unit, alias formal at param index 0 | ok | ok | ok |
| same-unit, alias formal at index 1 or 2 | **FAIL** | FAIL | ok |
| cross-unit (Synapse's shape) | ok | **FAIL** | ok |

That is the fingerprint of the recycled-symbol read fixed by
`bug-p-a-parameters-pointer-element-type-is-lost-between-registration-and-overload-matching`:
the matcher read a slot `SymRollbackTo` had handed back, which on some paths
happened to hold `tyUnknown` — the untyped-pointer sentinel — and so **failed
open**. That fix did not introduce this defect; **it made a garbage channel
deterministic**, turning a shape-dependent wrong answer into a consistent one.
Synapse went from *accidentally passing* to *reliably failing*. A bisect lands on
that commit every time, correctly, and is wrong about what it means.

### The third symptom, which had no ticket and is the serious one

The two loud symptoms pulled the whole investigation into a compile-time story
about overload resolution. The same wrong element also produced **wrong runtime
values**:

- **deref** — `p^.field` through an alias of a pointer-to-record did not compile
  (*"a pointer has no members"*). Loud.
- **overload** — a `Pointer` alias refused a class instance. Loud; took B's gate red.
- **pchar** — `c[i]` through an alias of `PChar` printed **`378951523` instead of
  `pxx`** on v393. **Silent wrong output, present for the life of the defect.**

Found only by varying the *spelling* of the alias rather than re-running the
reported shape.

### Verification

- Both arms the ticket required: same-unit **and** cross-unit, green.
- `lib_synapse_ssl` **compiles and runs** on the fixed build: 3 `=ok` lines and
  `SYNAPSE-SSL OK` (the assertions the Makefile makes), not merely "it compiled".
- Self-host fixedpoint converged (`fb2ce9b87b09`).
- `gate.sh quick`: self-host **PASS**, `testmgr --tier quick` **PASS**, FPC seed
  canary **PASS**. The run is RED solely on `-O3 backend parity`, which is
  **unrelated and pre-existing**: `823f1c85b` took `ir_codegen.inc`'s -O3 gate-site
  count 22 → 23 without bumping `EXPECTED`. This commit does not touch that file.

### Regression test

`test/test_pointer_alias_identity.pas` + `test/units/uptralias.pas`, wired into
`test-core`. Two of its arms are controls that could genuinely have failed:

- **`ctrl ok`** — `^Pointer` must **stay** element 17. An over-propagating fix
  turns it into the untyped sentinel; nothing else in the test would notice.
- **`atpos`** — the alias formal at parameter index 1 and 2. A fix verified only
  at index 0 would have been tested **exclusively on the shape that was already
  green on the broken binary**.

### What is still NOT bounded

The ticket's own warning stands: `lib-test` **aborted** at `lib_synapse_ssl` on
v394, so every job after that line is still unrun and the blast radius was never
measured. `lib_synapse_ssl` passing is necessary, not sufficient — a full
`lib-test` on a build carrying this fix (Track B's gate, frankB) is what closes
that, and it is a prerequisite for the pin, not for this ticket.

## Log
- 2026-08-30 — resolved, commit 3dab2c9cb.

## 2026-08-30 — sha correction: `ce3560ecd` never existed on origin

Corrected by the coordinator. The write-up cited **`ce3560ecd`**; `git merge-base` answers
*"not a valid object name"* for it. The commit landed as **`9b01b1b9b`** — *"fix(P/A): a
pointer type alias is the type it aliases"*, 05:53 — and every occurrence above has been
updated.

**This is `bug-t-resolve-cites-a-sha-the-rebase-then-rewrites` biting the write-up rather
than a `resolve` line.** `ce3560ecd` was real in the author's local reflog before the
rebase, which is why `git show --stat ce3560ecd` worked there and fails everywhere else.
Caught by frankB, whose own citation had moved the same way in the same window
(`6534f6f19` → `e26901160`).

**The rule the tooling already encodes:** pass no sha to `resolve` — it writes
`PENDING-COMMIT` and `tools/sync.sh` fills in the sha the commit **landed** as. A sha named
before the push is the pre-rebase one, and this repo rebases nearly every sync because the
watcher publishes tstate continuously. That protection covers the `Log:` line; **prose in
the body is outside it**, which is where this one got through.

## What the reporter's factor table could and could not see (frankB, after the fix)

Folded in rather than replacing the original table with the answer, because the
two instruments found different things and the difference is the reusable part.

**The table found the trigger in minutes and got the mechanism wrong.** It said
*cross-unit* alias vs *same-unit* alias, and I hypothesised that cross-unit
resolution used to lose the alias and now preserves it. The measured mechanism is
`AliasElemTk := tk` conflating "what kind is T" with "what does T point at", and
the v393 behaviour was **position-dependent** — an alias formal at parameter
index 0 accepted, at index 1 or 2 rejected — which is the signature of a
recycled-symbol read, not a rule about unit boundaries.

**My table could not have seen that, and the reason is structural: every row I
varied held the parameter position fixed at index 1.** The alias formal was the
second parameter in all five rows, because that is where it sits in Synapse's
`SslCtxSetDefaultPasswdCbUserdata(ctx, u)` and I built the repro by shrinking the
real call rather than by enumerating a space.

**That is not a flaw in the method.** A factor table is blind along exactly the
axes it holds fixed, and holding most axes fixed is what makes it fast — it
isolated the trigger from a 90-second suite failure without touching the
frontend. The lesson is not "vary more axes", which is unbounded; it is that a
factor table locates a **trigger** and a second instrument is needed for a
**mechanism**, and a hypothesis built only from the table should be labelled as
one. It was, and the label is why frankA went looking rather than implementing my
version.

**The inherited-repro hazard, stated for the next person.** Shrinking a real
failure preserves whatever the real call happened to fix — here, the argument
position. It is the cheapest way to a repro and it silently inherits the
original's coincidences. The counter is not to stop doing it; it is to notice
which properties came from the source rather than from the investigation, and to
say so when handing the repro on.

**One thing this closes that the fix's own acceptance did not.** The five-row
table was re-run on a build carrying `9b01b1b9b` from a tree with
`external/synapse` genuinely present, and all five pass **including the same-unit
arm that failed on both v393 and v394** — the "both arms or it is not fixed"
constraint, checked independently of the fixing lane's own acceptance. Build
provenance: worktree at HEAD `5dd4d33b2`, seeded from the pin and dated
`2000-01-01` so the build could not silently no-op, `converged after 2 round(s)`,
built sha `fb2ce9b87b09` ≠ seed `1d69760deabe`.
