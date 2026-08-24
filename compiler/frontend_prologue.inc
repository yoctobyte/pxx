{ SPDX-License-Identifier: MPL-2.0 }

{ ===== One program-driver prologue and epilogue, instead of twelve copies =====

  Starting a program is a fixed checklist, and it is the SAME checklist for
  every language: allocate BSS_INITIAL_RSP -> entry stub -> the emitted
  AnsiString runtime -> div-by-zero stub -> signal runtime and --threadsafe I/O
  lock stubs -> System intrinsics -> (parse, lower) -> the finalizer runner body
  -> resolve forward calls. Twelve drivers performed it, and every one of them
  performed it by hand.

  The drift has a DIRECTION, which is what makes it worth deleting rather than
  auditing: a driver is missing whatever the Pascal driver gained most recently,
  because the Pascal driver is where new runtime support is written and the
  others are updated only when something breaks. So the count of missing steps
  grows with time, silently, and each one is found by a crash. Measured on the
  BASIC driver alone, six separate times:

    - --threadsafe I/O lock stubs   -> a call to code offset 0 (the ELF entry),
                                       which jumps back to main and hangs
    - the signal runtime            -> shipped with none at all
    - RegisterBuiltinTGuid/TObject  -> "unknown type: TGuid" reported inside a
                                       compiler builtin, against a program that
                                       mentions neither
    - the emitted AnsiString runtime-> the same offset-0 guard, one stub later
    - the shared ENTRY stub         -> thirteen bytes of x86-64 at the entry
                                       point of an aarch64 binary (SIGILL)
    - EmitFinalizerRunnerBody       -> a Halt-site call left pointing at nothing

  A driver that calls EmitProgramPrologue cannot forget a step, because there is
  no step for it to forget; and a new runtime stub family is added HERE and
  every frontend has it.

  Deliberately NOT a shared parser, lexer or parser helper -- see
  devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md, which is about the
  SPEC-bearing code and still holds. This is emission, which is already
  language-neutral: EmitProgramEntryForTarget, EmitProgramRuntimeStubsForTarget,
  EmitAnsiStringRuntime and the Register* routines are shared today. What was
  duplicated is the CALL SEQUENCE and its guards.
  refactor-a-one-program-driver-prologue-for-every-frontend }

procedure EmitProgramPrologue(withHeapArena, wantAnsiRuntime, wantDiv0Stub: Boolean;
                              var jmpPatch: Integer);
{ Everything a program owes before its first statement is parsed.

  `withHeapArena` is the allocator model, not a preference: True mmaps the arena
  and publishes BSS_HEAP_PTR/BSS_HEAP_END (NilPy), False leaves the break to
  grow lazily in builtinheap (Pascal, C, and every skeleton).

  `wantAnsiRuntime` and `wantDiv0Stub` are the two steps a driver may legitimately
  skip, because both cost bytes in every binary that does not need them. A driver
  that cannot cheaply tell should pass True: the stubs sit behind the entry jump
  and are reached only by call, so an unnecessary one is dead weight and never a
  wrong answer. Both are x86-64-only INSIDE this routine rather than at each call
  site -- they are emitted machine code, and the other backends call the
  builtinheap helpers directly.

  The caller must call PatchProgramEntryJump(jmpPatch) once, at the point the
  main body begins. That is the half that cannot be shared, because only the
  driver knows where its body starts. }
begin
  { The System intrinsics go FIRST: they only touch the symbol table, and a unit
    pulled during the parse (builtinheap's TInterfacedObject/IInterface
    signatures NAME TGuid and TObject) must find them already registered. Both
    are idempotent -- they return early when the row exists. }
  RegisterBuiltinTGuid;
  RegisterBuiltinTObject;

  { ParamCount/ParamStr read argv through this slot, so it is allocated for every
    program whether or not it reads its arguments. Twelve drivers allocated it by
    hand, one line above the entry stub that is its only writer. }
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  EmitProgramEntryForTarget(withHeapArena, jmpPatch);

  { Forwards first: the emitter references builtinheap bodies that unit has not
    parsed yet, so they must exist as rows before EmitAnsiStringRuntime runs. }
  if wantAnsiRuntime and (TargetArch = TARGET_X86_64) then
  begin
    RegisterEmittedStringRuntimeForwards;
    EmitAnsiStringRuntime;
  end;

  if wantDiv0Stub and (TargetArch = TARGET_X86_64) then EmitDiv0Stub;

  { THE finish-the-runtime step: signal runtime (restorer / dispatch / sethook /
    install; --no-signals opts out) plus the --threadsafe I/O lock stubs. }
  EmitProgramRuntimeStubsForTarget;
end;

procedure EmitProgramEpilogue;
{ Everything a program owes after its last statement is lowered.

  Two steps, and the second is the one that was missing everywhere. A Halt site
  emits a forward call to __pxx_run_finalizers whose body is registered lazily;
  EmitFinalizerRunnerBody supplies the body, and ApplyCallFixups is what aims
  the call at it. Only the Pascal, C and NilPy drivers ever called the second --
  DceRun's trailing ApplyCallFixups is the only one the rest could inherit, and
  it runs only under `--dce` AND x86-64 AND IsPascalFrontend, so a forward call
  in a skeleton frontend was resolved by nothing at all and kept its placeholder
  for the whole compile. That is why the placeholder had to be made a NOP on
  every non-x86-64 target rather than a branch. }
begin
  EmitFinalizerRunnerBody;
  ApplyCallFixups;
end;
