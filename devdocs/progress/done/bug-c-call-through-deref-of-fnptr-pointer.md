---
prio: 58
---

# C: call through a DEREF of a pointer-to-function-pointer drops the call

- **Type:** bug (C frontend codegen) — **Track A/C** (shared `cparser.inc` call
  lowering).
- **Status:** done
  `(**(finder_type*)pAppData)(...)`) is fixed — commit pending, regression b236.
  The **bare-identifier** form (`ft *pf; (*pf)(args)`) is still open (needs the
  declarator sig-threading below). Root-caused while bringing up file-backed
  sqlite ([[task-sqlite-libc-free-runtime-bringup]]).

## Cast form — FIXED (2026-07-10)
A cast to a POINTER-to-fn-ptr now carries the pointee fn-pointer signature on its
alias (`AliasProcSig`): a new `CTypePtrElemProcSig` global captures the sig at the
`FnPtrTypedef *` star (cparser ~2790, before `CTypeProcSig := -1`), threaded to
`castPtrElemProcSig` and stored on the cast's alias. `CNodeProcSig`'s AN_PTR_CAST
arm: when `ASTRight < 0` but the alias has `AliasProcSig >= 0` and ≥1 deref was
stripped, it keeps ONE `AN_DEREF` as the callee (so AN_CALL_IND loads `*cast` = the
fn-pointer) and takes the sig from the alias. Verified: `(*(ft*)pv)()`,
`(**(ft*)pv)()` correct; self-host byte-identical; regression b236. Unblocked the
sqlite `fillInUnixFile` finder call (the db file is now created; further file-VFS
walls remain — see the sqlite ticket).

## Bare-identifier form — FIXED for local/param/global (2026-07-10)
`ft *pf; (*pf)(args)` (pf a pointer-to-fnptr VARIABLE) now calls correctly for
**local, parameter, and global** `pf`. The pointee sig is threaded from
`CTypePtrElemProcSig` into the SYMBOL's `SymElemProcSig` channel (the `*pf` ≡
`pf[0]` channel — shared with array-element calls) at three declarator sites:
- locals: `ParseCLocalDeclAST` — capture `ptrElemSig := CTypePtrElemProcSig`
  (mutually exclusive with `procSig`), thread through the per-declarator
  `declPtrElemSig` (primary + the comma/sibling reset branches), set
  `SymElemProcSig[idx]` in the `declTk = tyPointer` block;
- params: parallel `pptrelemsig[]` array captured at the param loop +
  fn-return-param path, set `SymElemProcSig[idx]` beside the SymProcSig param loop;
- globals: `SymElemProcSig[idx] := CTypePtrElemProcSig` in the normal
  global-pointer block of `ParseCGlobalVarDecl` (`ft *gpf` fails the special
  fn-ptr-global guard — CTypeProcSig is cleared by the `*` — so it lands here).
Plus the `CNodeProcSig` AN_IDENT arm: when `SymProcSig[id] < 0` but a deref was
stripped and `SymElemProcSig[id] >= 0`, keep ONE `AN_DEREF` as the callee and take
the sig from the elem channel (twin of the AN_PTR_CAST deref arm).
**As predicted, self-host is a non-issue** (cparser C paths never run when
compiling the Pascal compiler — byte-identical trivially); the real gate is the C
corpus. Verified: c-testsuite 220/220, testmgr quick GREEN, sqlite file probe
clean, regression `test/cfnptr_deref_call_b241.c` (exit 42, covers local/param/
global + the `pf[0]` shared channel + reassign-through-pointer).

### Remaining sub-case: STRUCT MEMBER `(*s.pf)(args)` — OPEN
A struct field that is itself a POINTER-to-fnptr (`struct S { ft *pf; }`) then
`(*s.pf)()`. Rare (the corpus doesn't hit it). Recipe when wanted: a parallel
`UFldElemProcSig` field array (defs.inc) beside `UFldProcSig`, copied in the
field-copy loop (symtab.inc ~575) and set from a `LastTypePtrElemProcSig` global
(~605); a `RecFieldElemProcSig(rec,field)` accessor; capture
`CTypePtrElemProcSig` at the struct field builder (cparser ~8558) and thread it
through the `bfProcSig`-parallel bitfield path (~8574/8769/8823); then a
`CNodeProcSig` AN_FIELD arm mirroring the AN_IDENT one (derefCount≥1 +
RecFieldElemProcSig → keep one deref). Direct fnptr fields (`ft f; s.f()`)
already work via `RecFieldProcSig`.
- **Blocks:** file-backed sqlite VFS. `sqlite3_open("/tmp/x.db")` now reaches
  `unixOpen`/`posixOpen` (fd obtained, after the crtl errno fix 495a989a) but then
  segfaults in `fillInUnixFile` at the locking-style finder call.

## Symptom
`(*pf)(args)` where `pf` is a POINTER-TO-function-pointer compiles to just the
dereference `*pf` — the CALL is dropped (no `call`, no argument marshalling).
The expression yields the function-pointer value, which the caller then uses as
data (garbage / segfault).

Minimal repros (gcc correct, pxx wrong):
```c
typedef long (*ft)(long);
static long impl(long x){ return x+100; }
static ft theF = impl;
long via_direct(ft f)   { return f(5);      }  /* OK  -> emits `call r11` */
long via_deref (ft *pf) { return (*pf)(5);  }  /* BUG -> `mov rax,[pf]; mov rax,[rax]; ret` */
/* sqlite's exact shape (void* -> ptr-to-fnptr cast, double deref): */
void *pv = (void*)&theF;
long via_cast()         { return (**(ft*)pv)(5); }  /* BUG */
```
`via_direct` (callee = a fn-pointer VARIABLE) emits `call r11`. `via_deref` /
`via_cast` (callee = a DEREF of a pointer-to-fn-pointer) drop the call.

Array element calls already work: `ft arr[3]; arr[1](5)` is correct (the
`SymElemProcSig` / `AN_INDEX` channel in `CNodeProcSig`).

## sqlite trigger (verified by instrumentation)
`fillInUnixFile` (os_unix.c) does
`pLockingStyle = (**(finder_type*)pVfs->pAppData)(zFilename, pNew);`. Instrumented,
the returned `pLockingStyle` = `0x20ec8148e5894855` — that byte string is an x86
function PROLOGUE (`55 48 89 e5 48 81 ec 20` = push rbp; mov rbp,rsp; sub rsp,0x20),
i.e. the call was replaced by a data read of the finder's own code, then used as a
pointer → segfault when `pLockingStyle->xLock` is dereferenced.

## Root cause
`compiler/cparser.inc` `CNodeProcSig` (the call-signature resolver used by the
`(expr)(args)` postfix-call arm, ParseCPostfixTail ~line 2242):
```pascal
inner := node;
while ASTKind[inner] = AN_DEREF do inner := ASTLeft[inner];   { strips ALL derefs }
callee := inner;
if ASTKind[inner] = AN_IDENT then Result := SymProcSig[ASTIVal[inner]]  { -1 for a ptr-to-fnptr }
...
else if ASTKind[inner] = AN_PTR_CAST then Result := ASTRight[inner];    { -1 for a ptr-to-fnptr cast }
```
The strip loop removes EVERY `AN_DEREF`. For a fn-pointer designator (`(*fp)`,
`(**fp)` where `fp` is a fnptr) that is correct — C treats the derefs as redundant,
and `SymProcSig[fp] >= 0`. But for a POINTER-to-fnptr (`ft *pf`), the first deref
`*pf` is a REAL LOAD that yields the fn-pointer; stripping it lands on `pf` whose
`SymProcSig` is -1 (set deliberately: cparser line ~2767 `CTypeProcSig := -1;
'FnPtrTypedef * = pointer-to-fn-ptr, not directly callable'`). `CNodeProcSig`
returns -1, the tkLParen call arm is skipped, and the trailing `(args)` is dropped.
The pointee fn-pointer signature is thrown away at declaration/cast time and is
not recoverable at the call site.

## Fix design
Preserve the pointee fn-pointer signature for a pointer-to-fnptr, and keep exactly
ONE deref (the real load) as the AN_CALL_IND callee:
1. **Declarator** (`ft *pf`, cparser ~2767): before `CTypeProcSig := -1`, stash the
   pointee sig; thread it into the symbol as `SymElemProcSig[idx]` (the same
   channel `ft arr[N]` uses — `*pf` ≡ `pf[0]`), for params (~7155) and locals/
   globals/struct-members.
2. **Cast** (`(ft*)x`, AN_PTR_CAST ~1877): stash the pointee sig on the cast node
   (a spare slot; note sig 0 is valid, so store sig+1 or use a dedicated parallel
   array with -1 default and reset-on-alloc — mind the AllocNode reset landmine).
3. **CNodeProcSig**: after locating the base, distinguish
   - a fn-pointer DESIGNATOR (SymProcSig>=0 / cast-fnptr-sig>=0) → all derefs
     redundant, callee = base (existing behaviour); vs
   - a POINTER-to-fnptr (SymElemProcSig>=0 / cast-ptr-elem-sig>=0) → wrap the base
     in a single `AN_DEREF` for the callee (so AN_CALL_IND evaluates `*base` = the
     loaded fn-pointer), sig = the pointee sig.

## Gate
`make test` + self-host byte-identical + `make test-c-conformance` 220/220.
Regression: add the three-shape repro as `test/cfnptr_call_via_pointer_bNNN.c`
(exit 42). Re-verify file-backed sqlite advances past `fillInUnixFile` afterwards
(there may be further VFS walls — fcntl locking next).

## Landmines
The call path is hot and self-host uses fn-pointer calls heavily — keep every
existing `CNodeProcSig` arm intact and only ADD the pointer-to-fnptr handling.
Verify self-host byte-identical (expect a 2-step reseed if codegen shifts).

[[task-sqlite-libc-free-runtime-bringup]]

## Log
- 2026-07-10 — resolved, commit 9e068f38.
