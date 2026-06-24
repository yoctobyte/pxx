# bug: cross gates red on two pre-existing tests (were masked behind ArgStr)

- **Type:** bug (Track A — cross codegen)
- **Status:** backlog
- **Found:** 2026-06-24, after fixing `bug-argstr-managed-dest-cross`
- **Severity:** medium — keeps `make test-i386` / `test-aarch64` / `test-arm32`
  red. Both are independent of the ArgStr fix; they were simply hidden because
  the gate stops at the first failing test and `test_arm32_arg_runtime` (earlier
  in the gate) failed first.

## Background

The cross gate has been red at `test_arm32_arg_runtime` since that test landed
(7b20bef, 2026-06-23). With ArgStr now fixed (`bug-argstr-managed-dest-cross`,
2026-06-24) the gate runs further and exposes two failures that were accumulating
unnoticed behind the early stop. Both reproduce on HEAD with the ArgStr change
stashed, so neither is a regression from that work.

## Failure 1 — `test_cross_frozen_strlen_deref` (i386 + arm32)

Run under `-dPXX_MANAGED_STRING`. Cross output diverges from the x86-64 oracle on
the 2nd/3rd lines:

```
i386 / arm32 : 5 / 1869566548 / 1869566548 / 26984 / 26984
x86-64 oracle: 5 / 500085772884 / 500085772884 / 26984 / 26984
```

A done ticket exists — `bug-frozen-string-length-pointer-deref-cross` (resolved
2026-06-19, `Length(p^)` of a frozen string returning 0 on cross). The current
divergence is a *different* number (not 0), so either that fix regressed for this
test shape or the test was added/extended afterward in a state that never passed
cross. Note x86-64 itself prints `500085772884` (a 64-bit read of string bytes),
so the test asserts cross==x86-64 on what is already an odd value — re-examine
whether the test or the codegen is wrong. aarch64 was not reached (it dies earlier
on Failure 2).

## Failure 2 — `test_classref` (aarch64)

```
./compiler/pascal26 --target=aarch64 test/test_classref.pas /tmp/x
pascal26:186: error: target aarch64: load through pointer of this type not yet supported ()
```

The `186` is a line in `typinfo` (`uses typinfo`; the test is 36 lines), not the
test — specifically `GetClass`'s loop `if entries[i].NamePtr^ = name then`
(typinfo.pas ~180), where `NamePtr: PString = ^TRttiStr` and
`TRttiStr = string[255]`.

### Root cause (investigated 2026-06-24, not yet fixed — bigger than a quick patch)

This is NOT really classref/metaclass and NOT aarch64-only — it is a frozen/inline
string dereferenced **through a pointer field**, broken on every target:

- `ir.inc` AN_DEREF/FIELD/INDEX value lowering: a frozen-string value "IS its
  address", so for `p^` it returns the address node `left` and re-tags it
  `IRTk[left] := ASTTk[node]` (so consumers see a frozen string, not a raw
  pointer). The comment even documents this.
- For a simple `ps^` (ps a pointer *variable*), `left` is an `IR_LOAD_SYM` and the
  in-place re-tag is harmless (still an 8-byte slot load).
- For `entries[i].NamePtr^` (deref of a pointer-typed *field*), `left` is an
  `IR_LOAD_MEM(fieldAddr, tyPointer)` that loads the field's pointer value. The
  re-tag mutates that very load to `tyString`, turning a pointer-load into a
  string-load. aarch64's `IR_LOAD_MEM` type guard then rejects `tk=4`; **x86-64
  does not error but mis-handles it and segfaults at runtime** (confirmed).

Minimal repro (segfaults on x86-64, errors on aarch64):

```pascal
type TRttiStr = string[255]; PString = ^TRttiStr;
     TEntry = record NamePtr: PString; X: Integer; end; PEntry = ^TEntry;
var arr: array[0..1] of TEntry; s0: TRttiStr; entries: PEntry; name: string; i: Integer;
begin
  s0 := 'TFoo'; arr[0].NamePtr := @s0; entries := @arr[0]; name := 'TFoo';
  for i := 0 to 1 do if entries[i].NamePtr^ = name then writeln('match ', i);
end.
```

### Proper fix (sketch)

Don't mutate the tag of the `left` address node in place when it is a load that
actually fetches the pointer (`IR_LOAD_MEM`/`IR_FIELD`/`IR_INDEX`): the pointer
must still be loaded pointer-width, only *presented* as a frozen-string address.
Either wrap it in a tag-only pass-through node, or keep `left` as `tyPointer` and
carry the frozen-string-ness on the consuming op. Also note `string[255]` here
resolves to legacy `tyString` (ord 4), not `tyFixedString` — the migration alias
is inconsistent and worth pinning down at the same time. (An attempt that merely
widened the AN_DEREF type set and/or the aarch64 guard was reverted: it fixes the
simple `ps^` case but not the pointer-field case, and the underlying in-place
re-tag of a pointer-load is the real defect.) i386/arm32 were not separately
checked but share the same `ir.inc` lowering, so expect the same break.

## Acceptance

- `make test-i386`, `make test-aarch64`, `make test-arm32` fully green.
- Each fix verified against the x86-64 oracle under `tools/run_target.sh`.

## Repro

```
git stash    # (if the ArgStr change is uncommitted; not needed once committed)
./compiler/pascal26 -dPXX_MANAGED_STRING --target=i386 test/test_cross_frozen_strlen_deref.pas /tmp/fs
tools/run_target.sh i386 /tmp/fs                 # vs the x86-64 build's output
./compiler/pascal26 --target=aarch64 test/test_classref.pas /tmp/cr   # errors at :186
```
