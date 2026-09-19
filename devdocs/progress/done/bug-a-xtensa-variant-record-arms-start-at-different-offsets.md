---
slug: bug-a-xtensa-variant-record-arms-start-at-different-offsets
track: A
prio: 45
type: bug
status: done
created: 2026-09-18
found-by: frankH
owner: frankS
summary: "FIXED. THREE TARGETS, NOT ONE -- xtensa, arm32 AND riscv32, all of which have a 4-byte pointer and an Int64 that aligns to 8 as a MEMBER. ParseRecordVariantPart laid the variant part out from AlignTo(curOff, TARGET_PTR_SIZE), which its own comment describes as a base that 'satisfies EVERY alignment'; on those three it does not, so an Int64 arm was aligned up to 8 while an Integer arm started at 4 and the two arms of one variant part began at different offsets. Writing through one and reading through the other then returns the wrong bytes, with no diagnostic. x86-64 escaped because its pointer is already as wide as the widest member alignment -- the coincidence the code mistook for a rule -- and i386 because TypeFieldAlign caps its scalars at 4. The downward shift below that line was ALREADY the right mechanism and could never fire, because vDelta came out NEGATIVE (4 - 8) and the guard is `if vDelta > 0`. Fix: the base is now AlignTo(curOff, TypeAlign(tyInt64)) -- derived from TypeAlign's own ladder, which tops out at 8 for anything wider than 4 bytes, rather than spelled as 8, so this site and the cap cannot drift. x86-64 and i386 layouts are byte-identical before and after. Guarded by test_varm26 plus five cross rows (i386, arm32, riscv32, aarch64, xtensa) that ASSERT RELATIONS AND COMPARE AGAINST THE x86-64 RUN OF THE SAME SOURCE, carrying no per-target offset at all -- the ticket asked for exactly that. Positive control: on the pinned compiler the first row reads `arms agree: FALSE` on all three affected targets and TRUE on i386."
---

# xtensa variant-record arms start at different offsets

```pascal
program VO;
type TVar = record Tag: Integer; case Integer of 0: (A: Int64); 1: (L, H: Integer); end;
var r: TVar;
begin
  WriteLn('A@', PtrUInt(@r.A) - PtrUInt(@r), ' L@', PtrUInt(@r.L) - PtrUInt(@r), ' size=', SizeOf(r));
end.
```

| target | output |
| --- | --- |
| x86-64 | `A@8 L@8 size=16` |
| i386 | `A@4 L@4 size=12` |
| **xtensa** (`--platform=posix --xtensa-soft-mulhigh`) | **`A@8 L@4 size=16`** |

Every arm of a variant part must begin at the same offset. On xtensa, a value
stored through `A` and read through `L`/`H` (or the reverse) reads the wrong
bytes. Programs overlay variant arms on purpose, so this produces wrong values.

Found while differentially checking typed-const record baking
(bug-a-a-typed-const-record-is-built-by-startup-code-not-stored-as-data): the
baked image was right and matched the layout table. The layout table itself is
what differs.

Test to add with the fix: assert the RELATION `@r.A = @r.L` rather than a
per-target offset, so the row carries no expected width.

# What it was (2026-09-19)

One line, and the comment above it already stated the premise that was false:

```pascal
variantBaseOff := AlignTo(curOff, TARGET_PTR_SIZE);
```

> *Laid out from a base that satisfies EVERY alignment, then shifted back down
> to the alignment the branches actually need...*

`TARGET_PTR_SIZE` is 4 on xtensa, arm32 and riscv32, and `TypeFieldAlign(tyInt64)`
is 8 on all three. So the base satisfied every alignment on exactly the two
targets anybody measures on, and the shift that was supposed to fix up the rest
could not run: `vDelta := variantBaseOff - vNewBase` came out **-4**, and the
guard is `if vDelta > 0`. A negative delta is the signature of the base being
under-aligned, and it was discarded silently.

**The probable mechanism named in the original ticket was right** -- "the
arm-start alignment and the Int64 field placement consult different alignment
answers" -- and it was filed as unverified. It is verified now and it is
narrower than that: they consult the same answer, `TypeFieldAlign`, for the
FIELDS, and a different one, `TARGET_PTR_SIZE`, for the arm START.

## Scope, measured rather than assumed

| target | before | after |
| --- | --- | --- |
| x86-64 | `A@8 L@8 size=16` | unchanged |
| i386 | `A@4 L@4 size=12` | unchanged |
| aarch64 | `A@8 L@8 size=16` | unchanged |
| xtensa | **`A@8 L@4 size=16`** | `A@8 L@8 size=16` |
| arm32 | **`A@8 L@4 size=16`** | `A@8 L@8 size=16` |
| riscv32 | **`A@8 L@4 size=16`** | `A@8 L@8 size=16` |

The ticket named xtensa because that is where it was found. Running the same
probe across all six targets before touching anything is what turned one target
into three -- and arm32 and riscv32 are not ESP targets, so nobody looking at
this as an ESP bug would have swept them.

## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 823bdad3d.
