---
slug: bug-p-an-open-array-literal-loses-its-length-through-a-procedural-type-call
track: P
prio: 60
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankD
blocked-by: []
summary: "ROOT CAUSE FOUND: an open-array `[...]` literal at an INDIRECT call site is parsed as a SET LITERAL, so the hidden length is never computed -- `PXXDBG=a.ir` shows `set_lit tk=21` and one argument where the direct call emits an array temp plus `const_int 3` and two. Passing an open-array LITERAL through a procedural-type variable therefore silently loses the length. `c := @Show; c([7,8,9])` for `TOpenCb = procedure(const A: array of Integer)` gives `Length(A) = 263845145632`; the same callback typed `of object` gives `Length(A) = 0`. fpc 3.2.2 prints 3 for both, and pxx itself prints 3 for the DIRECT call and for an indirect call passing a VARIABLE -- so the defect is exactly literal-plus-indirect, and the three neighbouring rows that work are what makes it invisible. THIS COMPILES TODAY WITH NO DIAGNOSTIC on ordinary `array of Integer` code, which is why it outranks the parse refusal that led me here. THE `of object` SPELLING ANSWERS 0, A LEGAL LENGTH: a probe passing `[]` sees a correct answer, and so does any caller that only checks Length > 0 before looping. It also explains why bug-p-array-of-const-in-a-method-pointer-type-is-refused-and-parsing-it-is-the-trap could not be fixed in the parser -- `array of const` is called with a literal essentially always, so making the declaration parse just routes it into this. It is a Track P call-site parse decision, not an ABI or codegen defect: the proc-type signature is registered as `$proctype`, so the question the direct path asks can be asked here. Measured on x86-64 only."
---

# An open-array literal loses its length through a procedural-type call

Measured at `d918976f8`, binary `0207010e859c`, against fpc 3.2.2 (`-Mobjfpc`).

```pascal
type
  TOpenCb = procedure(const A: array of Integer);
  TObjCb  = procedure(const A: array of Integer) of object;
```

| call shape | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `Show([7,8,9])` — literal, direct | 3 | 3 |
| `Show(v)` — variable, direct | 3 | 3 |
| `c([7,8,9])` — literal, **indirect** | **263845145632** | 3 |
| `c(v)` — variable, indirect | 3 | 3 |
| `o([7,8,9])` — literal, **indirect `of object`** | **0** | 3 |
| `o(v)` — variable, indirect `of object` | 3 | 3 |

Four of six rows agree, and the two that do not are the two nobody probes first.

## Why this is worse than a garbage number

**The `of object` row answers 0.** Zero is a legal length. A caller that does
`for i := 0 to Length(A) - 1` simply does nothing, correctly-looking; a probe
that passes `[]` to check the shape works gets the right answer for the wrong
reason. Only a non-empty literal separates them, and only on the plain
procedural type does the wrongness announce itself by being absurd.

**It needs no unusual construct.** `array of Integer` and a callback variable
are ordinary Pascal. Nothing here is a dialect corner.

## It is why the `array of const` parse fix cannot land

[[bug-p-array-of-const-in-a-method-pointer-type-is-refused-and-parsing-it-is-the-trap]]
is a refusal at declaration time. I have now written that parse fix twice and
reverted it twice. The second attempt was made on a specific hypothesis — the
procedural-type arm sets `mIsArr` but never `LastTypeRecId := TVarRecId`, which
`mPTypesRec[i]` reads for the element stride, where the method arm at ~6869 sets
both — and adding it **did** make the declaration parse and did not fix the
call: `Length` came back 0, then 4311000, then a segfault.

That hypothesis was wrong, and the way it was wrong is worth keeping: it named a
mechanism inside the parser for a defect that is not in the parser, and the
symptom it predicted (a wrong length) is the symptom this bug produces anyway.
It would have been indistinguishable from a confirmation if I had stopped at the
first row. What separated them was one probe with no `array of const` in it at
all — a plain `array of Integer` through the same procedural type, which fails
identically. **`array of const` is not the subject; the open-array literal is.**

So the parse fix stays reverted until this lands. `array of const` is called
with a literal essentially always, so parsing the declaration only moves the
failure from a clean refusal to a silent wrong number.

## Root cause: the literal is parsed as a SET

`PXXDBG=a.ir` on the two call shapes, same program, same argument:

```
DirectCall                         IndirectCall
  lea      <array temp>              set_lit  ival=1264 tk=21   <- tySet
  arg      <address>                 arg      <the set>
  const_int ival=3                   load_sym c
  arg      <the length>              call_ind
  call
```

The direct call materialises an array temp, stores 7/8/9 into it, and passes
TWO arguments — the address and the hidden length 3. The indirect call emits
`set_lit ... tk=21` and passes ONE. The length is not lost in marshalling; it
was never computed, because **`[7,8,9]` was parsed as a set literal.**

This is the mechanism `ParamIsVarRecArray`'s own comment describes for the
`array of const` case: *"This decision is made BEFORE overload resolution — the
parser has to know whether `[...]` is a TVarRec vector or a set literal in order
to parse it at all."* At an indirect call site there is no `procIdx`, so the
question is never asked and `[...]` defaults to a set.

**The confirmation is in the wrong value itself.** The garbage element read
`A[0] = 896`, and 896 is `1 shl 7 or 1 shl 8 or 1 shl 9` — the set bitmask for
{7,8,9}. The failing program is printing its own misparse.

So this is a Track P call-site parse decision, not an ABI or codegen defect, and
it is fixable in principle: the procedural type's signature IS known — the
parser registers it as `$proctype` via `RegisterProc` — so the same question
the direct path asks can be asked of the proc-type's parameter list.

**The fix site is exact.** `BuildIndirectCallAST` (`pasparser_lval.inc:54`)
parses every argument with a bare `ParseExpr`:

```pascal
  while CurTok.Kind <> tkRParen do
  begin
    ParseExpr;                       { <- `[...]` becomes a set, always }
```

The direct path asks first (`pasparser_expr.inc:7686`):

```pascal
  if (CurTok.Kind = tkLBrack) and ParamIsVarRecArray(procIdx, slotIdx) then
    CurASTNode := ParseVarRecLiteralAST
  else
    ParseExpr;
```

`sigPi` is a `Procs[]` index and `nArgs` is the slot number, so the same
question is answerable here with what the function already holds — this
function's own comment forty lines down makes exactly that argument for the
suffix handoff (*"It takes a Procs[] index and a signature row IS one"*), and
the argument loop is the case it did not carry across. That comment also says
this helper exists "to stop the argument loop being written a fourth time",
which makes it the right and only place to add the question.

**The other half, now read.** The direct path's decision is four-way, not two
(`pasparser_expr.inc:7688`):

```pascal
  if (CurTok.Kind = tkLBrack) and ParamIsVarRecArray(procIdx, slotIdx) then
    CurASTNode := ParseVarRecLiteralAST
  else if (CurTok.Kind = tkLBrack) and ParamIsOpenArrayScalar(procIdx, slotIdx) then
    CurASTNode := ParseArrayCtorAST(Procs[procIdx].Params[slotIdx].TypeKind,
      OpenArrayCtorRowLen(procIdx, slotIdx),
      ProcParamElemRowLo[procIdx * MAX_PROC_PARAMS + slotIdx])
  else
  begin
    node := TryDelphiBareProcArg;
    if node >= 0 then CurASTNode := node else ParseArgExpr;
  end;
  SetLitCheckArg(CurASTNode, procIdx, slotIdx);
```

`ParamIsOpenArrayScalar` → `ParseArrayCtorAST` is the arm that serves
`array of Integer`; `ParamIsVarRecArray` → `ParseVarRecLiteralAST` serves
`array of const`. `BuildIndirectCallAST` has neither, and no
`TryDelphiBareProcArg` and no `SetLitCheckArg` either — it calls `ParseExpr`
and nothing else. So the indirect path is missing the whole decision, and the
two bugs this ticket covers are two arms of it.

**Fix it by extracting, not by copying the block.** Four behaviours keyed on
`(procIdx, slotIdx)` in one path and zero in the other is the shape
`devdocs/dev/normalise-dont-special-case.md` exists to refuse, and copying the
block makes a second copy that will drift — `TryDelphiBareProcArg` and
`SetLitCheckArg` are exactly the kind of later addition that lands in one copy
only. One helper taking `(procIdx, slotIdx)` and returning the parsed node,
called from both loops.

Note what this predicts and what should be checked before fixing: any callee
parameter whose `[...]` argument needs a non-set reading has the same hole at an
indirect call site, `array of const` included. That makes this the single fix
for both, and it is why
[[bug-p-array-of-const-in-a-method-pointer-type-is-refused-and-parsing-it-is-the-trap]]
should not be approached from the declaration end.

## Not established

- **Target.** x86-64 only. Anything about the hidden length's width or position
  could differ on i386/arm32/riscv32, and that is where the dev loop cannot see.
- Whether an open-array literal through a procedural type in a RECORD or as a
  field behaves the same.
- Whether the `0` and the garbage are two bugs or one — they are different
  wrong answers from two spellings of the same shape.
