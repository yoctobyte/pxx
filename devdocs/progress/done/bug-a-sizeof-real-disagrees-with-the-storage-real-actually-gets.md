---
slug: bug-a-sizeof-real-disagrees-with-the-storage-real-actually-gets
track: A
prio: 70
type: bug
blocked-by: []
summary: "`SizeOf(Real)` answered 8 on xtensa and riscv32 for a variable that occupies 4. The declaration path and the SizeOf path read the rule from two different tables and only one was target-aware, so GetMem/Move/FillChar got a size four bytes too large, silently, on the targets least able to survive it."
status: done
---

# `SizeOf(Real)` disagreed with the storage `Real` actually gets

Split out of [[bug-a-real-is-single-on-hosted-riscv32]], which reported the
wrong half. `Real` being Single on the ESP class is **intended** — see
`docs/language/types.md`. What was broken was the *reporting*.

## Measured (2026-08-27, riscv32)

```
runtime-var   4      <- SizeOf(r) where r: Real     correct
runtime-type  8      <- SizeOf(Real)                WRONG
```

and the arithmetic was genuinely single-precision (`1.0/3.0` folds to
`0.33333334326744079590`), confirming the *storage* was right all along. The
pinned compiler lays out `array[0..999] of Real` in 4000 bytes on riscv32 —
it was only ever the answer to `SizeOf(<type name>)` that lied.

## Cause — the rule was written out twice and the copies disagreed

Both in `compiler/pasparser_lval.inc`:

| table | consulted by | said |
| --- | --- | --- |
| `BuiltinScalarTypeKind` (~6176) | `var r: Real` — the declaration path | target-keyed: `tySingle` on xtensa/riscv32 |
| `BuiltinTypeNameTk` (~6316) | `SizeOf`, casts, TypeInfo, helper resolution | hard-wired `tyDouble` |

The irony is on the record: `BuiltinTypeNameTk`'s own header comment says
*"One table, so the next builtin type cannot be present in half the compiler."*
`Real` was present in half the compiler, in that table, under that comment.

A third copy sat in `compiler/pasparser_expr.inc:4402` — `tkReal_T: tiTk :=
tyDouble` in the TypeInfo token-kind arm — so `TypeInfo(Real)` would have
reported Double on a Single target too. Three copies of one rule is the
`root-cause-over-microfix.md` threshold exactly ("two mechanisms is a smell,
three is a design flaw").

## Why it mattered more than a wrong number

`SizeOf` is what `GetMem`, `Move`, `FillChar` and every manual serialiser are
handed. A `SizeOf(Real)` of 8 over 4-byte storage is a four-byte overrun per
element, with no diagnostic, on the two targets with no MMU, no guard pages and
the least RAM to spare — where the corruption surfaces as something unrelated,
much later. Silent-wrong-behaviour, so a normal bug regardless of the
FPC-parity ceiling.

## Fix

One routine, `RealTypeKind` in `compiler/util.inc`, and all three sites call it.
Deliberately **not** folded into `TargetIsEspClass`: that predicate's header
lists "Real is Single" among the concepts that merely share its spelling without
being the same concept, and it stays that way — `RealTypeKind` answers "what
does the type name `Real` mean here", which is a dialect question that happens
to have the same answer today.

## Outcome (2026-08-27)

Fixed. `SizeOf(Real)` now equals `SizeOf(r)` on every target; `Double` is
unchanged at 8 everywhere; the single-precision arithmetic and the 4-byte
storage on the ESP class are untouched, because those were never the defect.

Measured after, by array stride (the Single targets have no host to run on):

| target | Real | | target | Real |
| --- | --- | --- | --- | --- |
| x86-64 | 8 | | riscv32 | **4** |
| i386 | 8 | | xtensa | **4** |
| aarch64 | 8 | | esp32c3 | **4** |
| arm32 | 8 | | | |

`--target=riscv32` and `--target=esp32c3` remain byte-identical, the invariant
the Makefile asserts with `cmp`.

Tests: `test/test_sizeof_real_matches_storage.pas`, wired into `test-core`,
byte-identical to the FPC 3.2.2 oracle. It asserts the identity that regressed —
`SizeOf(T) = SizeOf(var of T)` — rather than a literal 8, so it is meaningful on
targets where the answer differs; it cannot fail on x86-64, which is the point
of also recording the stride table above.

`test/test_typeinfo_scalar_names.pas` gained a `TypeInfo(Real)` row. Its header
had *discussed* `Real` for months without the program ever calling
`TypeInfo(Real)`, so the third copy of the rule had no coverage at all — that
is how it survived. The row reports `Real 4 Double` on x86-64; FPC says
`Real 4 Real`, because FPC gives the alias its own RTTI entry and we report the
underlying type. Kind agrees; the name difference is the pre-existing declared
divergence, not new.

Docs, the half the owner called out (*"ticket didnt read the docs - or we never
documented this properly"* — it was the latter: `types.md` said `Real` was an
"alias of `Double`", unqualified):

- `docs/language/types.md` — per-target table, the rationale, and the
  serialisation trap.
- `docs/targets/esp32.md` — stated where an ESP user meets it.
- `docs/language/fpc-compatibility.md` — listed as a deliberate divergence.

Gate: `tools/gate.sh quick` GREEN, self-host fixedpoint, three corpora at
baseline.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
