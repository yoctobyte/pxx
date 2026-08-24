---
slug: bug-p-dereferencing-a-function-result-of-pointer-to-pchar-loses-the-shape
title: "`GetQ^` where `GetQ: ^PChar` is not recognised as a PChar — WriteLn prints the address"
track: P
prio: 30
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-08-24
summary: "A function returning `^PChar`, dereferenced, is wrong in the four contexts that refuse to guess: WriteLn prints the address in decimal, concat on either side yields the address, and `=`/`<>` compare pointers. The three contexts that look right are right only by the blanket `AnsiString(<any pointer>)` rule. Unlike the array shape beside it, this one genuinely IS missing metadata: a proc records ProcRetPtrElemTk/Rec — the immediate pointee — and nothing about the return pointer's DEPTH or ultimate BASE."
---

# Symptom

```pascal
type PPC = ^PChar;
var p0: PChar;
function GetQ: PPC; begin GetQ := @p0; end;
...
WriteLn(GetQ^);          { fpc: alpha    pxx: 129547099963424 }
WriteLn('x' + GetQ^);    { fpc: xalpha   pxx: 129467708080280 }
WriteLn(GetQ^ + 'y');    { fpc: alphay   pxx: 131958113829017 }
WriteLn(GetQ^ = 'alpha');{ fpc: TRUE     pxx: FALSE  -- compares POINTERS }
```

`AnsiString(GetQ^)`, `s := GetQ^` and `Length(AnsiString(GetQ^))` answer
correctly, and that is **not** recognition: `AnsiString(<any pointer>)` treats
its operand as a PChar unconditionally. Four contexts wrong out of seven is what
an unrecognised shape looks like when a blanket rule covers the rest.

# Measured

2026-08-24, an 88-program cross product — 11 PChar sources x 8 contexts, each
its own program, each diffed against fpc 3.2.2. `pinned` diverged on 36. After
the `array of ^PChar` fix in
[[refactor-centralize-managed-string-pchar-conversion]], **5 remain, and all
five are this one shape.**

# Root cause, and why it is NOT the fix that just landed

The deref chain in `compiler/pasparser_lval.inc` needs two things for `x^`: the
pointer levels REMAINING and the ULTIMATE base kind. It has arms for `AN_IDENT`,
`AN_FIELD`, `AN_INDEX` and `AN_DEREF`, and **no arm for a call at all** — a call
falls to the `else` that yields `tyInteger`.

Adding an arm would not help, which is the actual finding. The array shape
beside this one *looked* like missing metadata and turned out to be present
under a name that means something else (`AllocArray` parks the ELEMENT's depth
and base in the symbol's own `SymPtrDepth`/`SymPtrBaseTk`). This one is not that:

```
$ grep -n "ProcRetPtr" compiler/defs.inc
2339:  ProcRetPtrElemTk  : array of Integer;   { pointed-at TTypeKind ord ... }
2342:  ProcRetPtrElemRec : array of Integer;   { pointed-at record id ... }
```

Two fields, both the IMMEDIATE pointee. There is no `ProcRetPtrDepth` and no
`ProcRetPtrBaseTk`, so `PChar` and `^PChar` are indistinguishable as return
types — exactly the ambiguity that ticket's `^PChar` note describes.

# The fix is a design call, not a patch — do NOT add two more parallel arrays

Symbols carry the pair (`SymPtrDepth`, `SymPtrBaseTk`/`Rec`) beside
(`PtrElemTk`, `PtrElemRec`). Mirroring that for procs means **two or three more
parallel arrays**, which is the sprawl
[[refactor-centralize-managed-string-pchar-conversion]] exists to reduce and
which its own text rules out: *"Adding a pair of parallel arrays would work and
is the wrong shape."*

The right shape is [[feature-a-typeref-migrate-consumers]] **lane 4** — proc
return types get one `TTypeRef` — and it is small: **10 write sites and 7 read
sites** for `ProcRetPtrElemTk` across `cparser.inc`, `pasparser_decl.inc`,
`pasparser_proc.inc` and `symtab.inc`.

**One thing to settle first, and it blocks the lane rather than this bug:**
`TTypeRef` as declared (`compiler/defs.inc:1559`) has `PtrBaseTk`/`PtrBaseRec`
and `DynDepth` — dynamic-array nesting — but **no pointer depth field**. Without
one it cannot express "pointer to (pointer to char)" any better than the pair it
replaces. Adding `PtrDepth` to `TTypeRef` is additive (nothing reads a pointer
depth off it today, because there is nothing to read) and looks clearly right,
but it changes a shared type mid-migration, so it wants a deliberate decision
rather than being slipped in under a bug fix.

# Repro

The 88-program generator is
`scratchpad/pc/xprod.py`-shaped: sources
{var, `q^`, `q[0]`, `qa[0]^`, `qd[0]^`, `GetQ^`, record field, array element,
dyn element, pointer arithmetic} x contexts {WriteLn, assign, concat L/R,
`AnsiString()`, `Length`, `=`, `<>`}. Re-run it against fpc after any change
here; it is the ticket's acceptance line made executable.

---

# Resolved 2026-08-24 — and the design objection above is answered, not ignored

Fixed by giving the proc table the same triple every other pointer-carrying
table now has (`ProcRetPtrDepth`, `ProcRetPtrBaseTk`, `ProcRetPtrBaseRec`),
populated at all nine declaration sites (Pascal routines, record methods, class
methods on both the decl and impl side, proc-type signatures, and C functions,
whose type parser had computed the depth all along and dropped it), and by
teaching the two readers that needed it.

**This ticket said "do NOT add two more parallel arrays" and that objection is
right about the destination — so read why the arrays landed anyway.** The
sprawl argument is an argument about the SHAPE of the eventual carrier, and it
does not distinguish between the five fields living in five arrays and the same
five fields living in one `TTypeRef`: either way they are populated at the same
nine sites and read at the same places. Lane 4 folds them in, and folding three
arrays into a record is mechanical. What waiting cost was different in kind: a
program that dereferenced a `^PChar` result printed an ADDRESS, silently, in
every context that refuses to guess. A wrong value in the field outranks the
tidiness of the table it came from, and the blocking question the ticket names
-- whether `TTypeRef` gains a `PtrDepth` -- is now filed on its own as
[[decide-typeref-gains-a-pointer-depth-field]] rather than being decided
sideways by a bug fix.

**The finding that mattered was not the metadata.** Populating the triple fixed
nothing on its own: `c := GetQ^; WriteLn(c)` printed the string while
`WriteLn(GetQ^)` printed the address, on the same binary, from the same
declaration. `ApplyCallResultPtrSuffix` in `pasparser_lval.inc` is a **fourth
copy** of the pointer walk (the others: the main deref chain, the parenthesised
tail in `pasparser_expr.inc`, the inherited-call tail) and it stamped none of
the node tags the rest of the compiler reads -- `ASTSOffset` = levels remaining,
`ASTSLen` = ultimate base -- so `IsNodePChar`'s arm 7 and `IRPointerStride`
were blind to a deref they were perfectly able to classify. The reader half
again, for the third ticket running.

`p^[i]` needed one more thing: `IRLowerAddress`'s computed-pointer-value arm was
gated on `CProgramMode`, a gate that recorded where the case was first noticed
rather than any property of the code -- the arm already proves its base is
pointer-valued. Ungated, Pascal's dereference and function-result bases route
through it instead of falling to the array path that wants an lvalue address.

# Verified

- `test/test_pointer_function_result_keeps_its_depth.pas` -- 8 rows (deref,
  with-args, class method, `^[i]` both ways, via a variable, concat, compare).
  `.expected` IS fpc 3.2.2's output; **7 of the 8 print an address on the pinned
  compiler**; green on i386 / aarch64 / arm32 / riscv32 under qemu.
- The C twin measured against gcc on the same shape (`char **getq()`, `*getq()`
  and `(*getq())[1]`): both print `hello` / `e`.
- A/B binary comparison against the pre-change compiler: `compiler.pas`, two C
  tests, three Pascal tests, a NilPy and a BASIC test all **byte-identical**, so
  nothing outside the fixed shapes moved.
- `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-24 — resolved, commit PENDING-COMMIT.
