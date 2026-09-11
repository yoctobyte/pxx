---
slug: bug-p-a-conditional-directive-cannot-evaluate-in-over-a-set-constant
title: "`{$if}` cannot evaluate `in` over a set-valued constant"
track: P
prio: 35
type: bug
status: open
owner: ""
found-by: frankH
created: 2026-09-11
tags: [conditional-directives, lexer, fpc-corpus, sets]
blocked-by: []
summary: "SPLIT OUT of bug-p-a-conditional-directive-cannot-read-a-const-whose-value-is-not-an-integer-literal on 2026-09-11, whose other half is now fixed. `{$if (cs_opt_use_load_modify_store in supported_optimizerswitches)}` (FPC nld.pas:700) needs the `in` operator over a SET constant that is itself folded from three other set constants (`supported_optimizerswitches = genericlevel1optimizerswitches + ...`, x86_64/cpuinfo.pas:139 over globtype.pas:428-430), plus resolution of an enum MEMBER name. pxx answers `conditional directive: expected operator` at the `in`. 2 units of FPC's 207 stop here (nld, and ncnv whose interface uses nld -- ONE directive reached twice, not two). It is much larger than the half that was fixed: a third value kind on the directive's value stack, set-union folding, and enum-member resolution, where the fixed half reused walks that already existed. Both are behind the unit-cycle bug anyway, so neither buys a compiling unit today."
---

# `{$if}` over a set-valued constant

Split from
[[bug-p-a-conditional-directive-cannot-read-a-const-whose-value-is-not-an-integer-literal]]
when its other shape was fixed. Keeping the two together made that ticket's
summary describe work of two very different sizes as one thing.

- **Umbrella:** `umbrella-pxx-compiles-fpc-itself`

## The directive, and everything it needs

`nld.pas:700`:

```pascal
{$if (cs_opt_use_load_modify_store in supported_optimizerswitches)}
```

`x86_64/cpuinfo.pas:139`:

```pascal
supported_optimizerswitches = genericlevel1optimizerswitches+
                              genericlevel2optimizerswitches+ ...
```

`globtype.pas:428-430`:

```pascal
genericlevel1optimizerswitches = [cs_opt_level1,cs_opt_peephole];
genericlevel2optimizerswitches = [cs_opt_level2,cs_opt_remove_emtpy_proc];
genericlevel3optimizerswitches = [cs_opt_level3,cs_opt_constant_propagate, ...];
```

So one directive needs, and none of it exists in the conditional evaluator:

1. **A set value on the directive's value stack.** It is tagged today with
   kind 0 = bool, 1 = int, and 2 = no-value (added 2026-09-11 for the
   short-circuit fix). A set needs a fourth and a payload wider than an `Int64`.
2. **Set-union folding** across three named set constants, two of which are in
   a different unit from the third.
3. **Enum MEMBER resolution** — `cs_opt_use_load_modify_store` is a member of an
   enum, not a const, and nothing in this evaluator resolves one.
4. **The `in` operator**, which the expression grammar does not have at all.

## Why it is worth less than its unit count

2 units of 207, and they are **one directive**: ncnv's interface `uses nld`, so
it is the same line reached twice. Both are behind
[[bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface]]
anyway — no unit here compiles when this is fixed.

Contrast with the half that WAS fixed on 2026-09-11, which is the argument for
splitting rather than for doing this next: that one reused walks the evaluator
already had (`PasCondTypeAlias`, `OrdinalNameToTk`, `OrdinalTypeBound`) and added
no new value kind, and it still bought zero compiling units — it moved rgobj to
the next wall. This one builds four new mechanisms for the same yield.

**The cheaper question to ask first:** whether the evaluator should answer `in`
at all, or whether a directive it cannot evaluate should be reported with the
operator named rather than as `expected operator`, which describes the grammar
and not the program. That is a smaller change and it is what a reader of
nld.pas:700 actually needs.
