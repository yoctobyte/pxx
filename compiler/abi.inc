{ ============================================================================
  THE ABI ORACLE — the one place that answers calling-convention questions.

  Design: `devdocs/dev/type-identity-as-substrate.md` item 4; ticket
  `feature-a-abi-oracle`.

  ## Why this file exists

  `IRTk` is a bare kind and identity rides `IRA`/`IRB`/`IRC` positionally per
  opcode. That is not enough to emit code, so every backend reached around the
  IR into frontend data and re-derived the convention for itself:

      (Syms[symIdx].Kind = skParam) and (Syms[symIdx].IsRef or ...)

  written out longhand in five backends plus `symtab.inc`. Eight copies of what
  reads like one rule. **They are not one rule**, which is the thing measurement
  established and reasoning had not (2026-08-09):

    * **slot SIZE** — how many bytes `AllocParam` reserves and `ParamSize`
      reports. `ABIParamSlotIsPointer`.
    * **callee SLOT-HOLDS** — whether the slot contains the VALUE or a POINTER
      to it, i.e. whether taking the parameter's address means "the slot's
      address" or "load the slot". `ABIParamSlotHoldsValueAddr`.

  and the caller's PASSES-BY half lives in `IRLowerCallArg`. Each backend's
  answers must agree with each other; they need NOT agree across backends, and
  they do not: riscv32 and i386 leave `tySet` out of the SLOT-HOLDS set while
  x86-64/aarch64/arm32 include it, and both arrangements are internally
  consistent (see `bug-a-set-and-shortstring-value-params-alias-the-caller`,
  which is what happens when the caller half disagrees with them).

  So the oracle is a per-target TABLE, not a portable predicate. Encoding it
  here makes the divergence deliberate and reviewable instead of accidental and
  invisible: previously nobody could say which of the eight copies was
  authoritative, and no test would have caught a ninth drifting.

  ## The invariant this file exists to enforce

  **Backends consult the oracle and never re-derive the convention from
  `Syms[]`.** That clause is greppable in review: a `Syms[...].IsRef or` chain
  inside `ir_codegen*.inc` means someone grew a ninth copy.

  ## Success metric (from the ticket)

  Adding one new pass-by-pointer type kind must take ONE edit, here, not nine.
  ============================================================================ }

{ Does a PARAMETER's stack slot hold the ADDRESS OF THE VALUE rather than the
  value itself?

  Asked by every backend when it needs the address of a parameter: if the slot
  holds the value, the answer is the slot's own address (`lea`); if the slot
  holds a pointer the caller put there, the answer is a LOAD of the slot.

  Kinds in the set on every target:
    * `IsRef`    — `var`/`out`/`const`, and records the ABI passes by reference.
    * `IsArray`  — an open array: the slot holds the caller's data pointer.
    * frozen strings — `string[N]`/`ShortString`: the caller passes a buffer.
    * `tyVariant` — the caller forwards the 16-byte slot by address.

  `tySet` is the per-target row, and it is a REAL convention difference rather
  than drift: it is in the set exactly on the targets whose argument lowering
  passes a set param's address. i386 and riscv32 pass the value, so dereferencing
  their slot would read the first 8 bytes of the set AS a pointer.

  Takes a symbol index rather than a TypeRef for now. Lane 1 of
  `feature-a-typeref-migrate-consumers` is what turns this into a query on a
  type's identity alone; the shape of the answer does not change when it does. }
function ABIParamSlotHoldsValueAddr(symIdx: Integer): Boolean;
begin
  ABIParamSlotHoldsValueAddr := False;
  if symIdx < 0 then Exit;
  if Syms[symIdx].Kind <> skParam then Exit;
  if Syms[symIdx].IsRef or Syms[symIdx].IsArray or
     TypeIsFrozenString(Syms[symIdx].TypeKind) or
     (Syms[symIdx].TypeKind = tyVariant) then
  begin
    ABIParamSlotHoldsValueAddr := True;
    Exit;
  end;
  { the per-target row }
  if Syms[symIdx].TypeKind = tySet then
    ABIParamSlotHoldsValueAddr :=
      (TargetArch = TARGET_X86_64) or (TargetArch = TARGET_AARCH64) or
      (TargetArch = TARGET_ARM32);
end;

{ Is a PARAMETER's slot pointer-SIZED — the layout question, distinct from the
  one above and answering it differently on purpose.

  A `tyClass` or `tyPointer` param's slot holds a pointer because the pointer IS
  the value: pointer-sized, and taking the parameter's address still means the
  slot's address, so it is NOT in the SLOT-HOLDS set. A `tySet` param's slot is
  the full 32-byte set on the targets that pass it by value, so it is not
  pointer-sized anywhere.

  Moved here from `symtab.inc`, unchanged. `ParamSize` and `AllocParam` both
  read it, which is what stopped THOSE two from disagreeing — they did, on
  `tyVariant` (`bug-a-param-pointer-rule-divergence`), and that fix is the
  small-scale precedent for this whole file. }
function ABIParamSlotIsPointer(tk: TTypeKind; isRef, isArray: Boolean): Boolean;
begin
  ABIParamSlotIsPointer := isRef or isArray or (tk = tyString) or
                           (tk = tyRecord) or (tk = tyVariant) or
                           (tk = tyClass) or (tk = tyPointer);
end;
