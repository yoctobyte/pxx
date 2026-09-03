---
type: bug
track: A
prio: 75
status: open
summary: Under -dPXX_SHORTSTRING on i386, writing a string field of a record is a
  compile error, "target i386: write of this operand not yet supported".
---

# i386 refuses a frozen record field write under the byte-prefix mode

**Blocks the phase-4 flip on i386.** The flip turns `-dPXX_SHORTSTRING` on
globally; today i386 cannot compile a record with a `string[N]` field being
assigned.

```pascal
type R = record f: string[10]; g: string[4]; end;
var r: R;
begin r.f := 'field'; end.
```

```
pascal26:2: error: target i386: write of this operand not yet supported
```

Compiles and runs correctly in the **default** mode on i386, and correctly in
BOTH modes on x86-64, arm32, aarch64 and riscv32. Also hit by an array of
records with a string field.

**This is an honest refusal, not a miscompile** — the backend says the operand
is unimplemented and stops, which is the right failure. It is a missing codegen
arm, so it should be cheap next to the wrong-value bugs in this family.

Found by running a 20-probe construct suite in both modes on all five runnable
targets; x86-64 alone shows nothing.
