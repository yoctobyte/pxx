---
slug: bug-p-a-pointer-type-alias-rejects-a-class-instance-that-plain-pointer-accepts
track: P
prio: 75
type: bug
blocked-by: []
status: working
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
