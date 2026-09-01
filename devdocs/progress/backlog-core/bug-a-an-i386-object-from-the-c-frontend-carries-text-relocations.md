---
slug: bug-a-an-i386-object-from-the-c-frontend-carries-text-relocations
track: A
prio: 40
type: feature
status: new
blocked-by: []
owner: ""
created: 2026-09-01
found-by: frankA (while adding .init_array to the i386 object writer; pre-existing, not caused by it)
summary: "i386 --emit-obj output is POSITION-DEPENDENT: .rel.text carries only absolute relocations -- CENSUSED 518 R_386_32 in a Pascal object and 566 in a C one, zero of anything else -- so linking gives `relocation in read-only section .text` and `creating DT_TEXTREL in a PIE`, and `-Wl,-z,text` refuses outright. Pre-existing and NOT from the .init_array work: two warnings measured identically on objects built before and after it. This is the exact i386 twin of feature-a-x86-64-object-output-is-position-dependent (done, p50, three phases d0537380a / 44b256356 / a3b1af61a, which took x86-64 to 273 R_X86_64_PC32 and zero absolutes in .text). Originally filed as a bug about a few offending sites; the census says it is a codegen model, and i386 is HARDER than the x86-64 twin was -- x86-64 had rip-relative addressing to convert to, i386 has no PC-relative data addressing at all and needs a GOT base register established per function."
---

# An i386 object from the C frontend carries text relocations

Found while making i386 objects run their initialisers
(`bug-a-an-i386-emit-obj-object-still-never-runs-its-initialisers`). **Not caused
by that work** — measured on an object built before it and one built after, and
both produce the same two warnings:

```
ld.bfd: cl386.o: warning: relocation in read-only section `.text'
ld.bfd: warning: creating DT_TEXTREL in a PIE
```

## Why it matters despite the program running

`ld` resolves this by marking `.text` writable at load. So the object links, the
program runs, every existing row stays green — which is exactly why it survived.
What it costs is real: `-Wl,-z,text` refuses the link outright, hardened
distributions build with it, and a writable `.text` cannot be shared between
processes.

## The x86-64 side already solved this and the difference is instructive

`test-emit-obj`'s x86-64 rows assert that `.text` carries **no** absolute
relocation, and that assertion exists because `IR_PROCADDR` was emitting
`mov rax, imm64` — an `R_X86_64_64` against `.text` — until the `@proc` case was
added to `test/test_emit_obj.pas` specifically to give the census a population
that could contain it. The comment there says so.

**i386 has no equivalent row.** So the same class of defect is unmeasured on a
target that has an object writer, which makes this a test gap first and a codegen
bug second. Adding the assertion is the cheap half and should probably come
first; it will name the sites.

## Re-scoped 2026-09-01 after censusing it

I filed this as "convert the offending sites". It is not that.

    .rel.text, Pascal i386 object   518 R_386_32, nothing else
    .rel.text, C i386 object        566 R_386_32, nothing else

Every relocation in `.text` is absolute. So the work is the i386 twin of
`feature-a-x86-64-object-output-is-position-dependent` — a backend model change,
which that ticket did in three phases.

**And i386 is the harder of the two.** x86-64 had `rip`-relative addressing to
convert to, so the fix was largely a different encoding for the same operand.
i386 has no PC-relative data addressing at all: position independence means
establishing a GOT base in a register (conventionally `ebx`, via the
`call/pop` thunk idiom) and addressing through it, which touches the register
allocator and the prologue rather than just the operand emitter.

**Do NOT just add the assertion to go red.** The obvious first step — mirror the
x86-64 row that asserts `.text` carries no absolute relocation — would turn
`test-emit-obj` red on a target that has never been green on this property, and
that costs Track T's signal for everyone while buying information this census
already gives. The row lands with the fix, not before it.

**A trap for whoever writes that row:** this file's own `.rel.init_array` entry
is an `R_386_32` against the `.text` SYMBOL and is not an instance of the bug —
it patches a slot in `.init_array`. The x86-64 row gets this right by scoping
with `sed -n '/rela.text/,/^$/p'` before grepping, i.e. by relocation SECTION
rather than by symbol name. Copy that shape.

Note for whoever takes it: the `.rel.init_array` entry added on 2026-09-01 is an
`R_386_32` against the `.text` symbol and is NOT an instance of this bug — it
patches a slot in `.init_array`. An assertion written as "no R_386_32 mentioning
.text anywhere" would flag it and be wrong.
