# Expected compiler failures — adventure demo

This demo is **platonic code**: written to be idiomatic and feature-rich, NOT
yet compiled. Per project policy, where it does not yet compile the fix is to
implement the feature, not to dumb down the game. This file logs **exactly where
the compiler is predicted to fail**, so the implement-until-it-runs loop has a
checklist. Ordered by predicted severity.

Date: 2026-06-18. Files: `engine.pas`, `adventure.pas`, `world.dat`.

## 🔴 High — likely hard blockers

### F1. Text file I/O (`Assign`/`Reset`/`Rewrite`/`ReadLn(f,…)`/`Eof`/`Close`)
- **Where:** `TGame.LoadWorld`, `TGame.SaveTo`, `TGame.LoadFrom` (engine.pas).
- **Why predicted:** PXX RTL has stdin `ReadLn`/`WriteLn` (library-work-queue
  done) but file-backed `Text` I/O has not been exercised. `Assign`/`Reset`/
  `Rewrite`/`Eof`/`Close` and the `Text` type may be absent.
- **Honest fix:** implement `Text` file I/O in the RTL (open/read/write/close
  over the existing kernel-ABI file syscalls — fits the no-libc design).
- **Fallback (only if you say so):** embed `world.dat` as a const string and
  parse from memory; drop save/load. Not preferred — file I/O is the point of
  "all in config files."
- **2026-06-25 update:** Text I/O is now *implemented* (`lib/rtl/textfile`:
  `Assign`/`Reset`/`Rewrite`/`Append`/`Close`/`writeln(f,…)` all work). The actual
  blocker here is narrower and filed as
  [[bug-textfile-primitives-not-ambient-in-units]]: those procedures are ambient
  in a **program** but not inside a **unit** (engine.pas is a unit), so `Assign`
  is undefined at engine.pas:652. Adding `uses textfile` to engine compiles it,
  but that is non-platonic (FPC has these in System, ambient everywhere) — the
  honest fix is the compiler making them ambient in unit scope too.
- **2026-06-25 RESOLVED:** Track A v62 (`8e68543` "inject textfile RTL for units
  that reference Text") makes the textfile primitives ambient in unit scope.
  `Assign` at engine.pas:652 now compiles. The compile advances to the next
  blocker below (F-Move).

### F-Move (new, surfaced after F1 cleared). Bare `Move(d)` resolves to the `Move` intrinsic
- **Where:** `TGame.Run` at engine.pas:1038 — `if NameToDir(w, d) then begin
  Move(d); Continue; end;` calling the method `TGame.Move(d: TDirection)`.
- **Symptom:** `pascal26:1038: error: no overload of Move matches these arguments`
  — the unqualified `Move(d)` binds to the memory-move intrinsic
  `Move(src,dst,count)` instead of `Self.Move`. Same family as
  [[bug-bare-read-write-in-method-hits-intrinsic]] (intrinsic shadows a same-named
  method called unqualified inside another method).
- **Note:** a reduced repro (bare method `Move(Integer)`/`Move(enum)` called from
  another method, program or unit) does **not** reproduce — it needs engine's
  fuller context, so no standalone minimal-repro ticket yet; logged on the
  bare-intrinsic ticket as a data point. Sidestep for now: qualify as `Self.Move(d)`.

### F2. `{$I-}`/`{$I+}` + `IOResult` (soft file-open check)
- **Where:** `TGame.LoadFrom` (guarding a missing save file).
- **Why predicted:** depends on F1 plus I/O-checking directive + `IOResult`
  intrinsic, which almost certainly does not exist yet.
- **Honest fix:** support `{$I-/+}` and `IOResult`. Or replace with a
  `FileExists`-style probe once one exists.

### F3. Nested procedure capturing a parent local
- **Where:** `AddVerb` nested inside `TGame.Run`, mutating the enclosing
  `verbs: array of TVerb` local.
- **Why predicted:** this is one of the structural gates flagged in
  `goal-compile-fpc-compiler` — nested-proc frame access (static link/display).
  May not be implemented.
- **Honest fix:** implement nested-proc parent-frame capture (worth having;
  FPC uses it). Cheap sidestep if needed: hoist `verbs` to a field or pass it
  `var` to a top-level `AddVerb`.

## 🟡 Medium — feature breadth, may or may not be in yet

### F4. Unit system (`unit … interface/implementation`, `uses Engine`)
- **Where:** `engine.pas` is a unit; `adventure.pas` does `uses Engine`.
- **Why predicted:** PXX supports multi-unit (RTTI multi-unit work), but a
  hand-written user unit with this surface (cross-unit classes, sets, enums in
  the interface) may trip something.
- **Honest fix:** whatever the first cross-unit error is — capture it.

### F5. `for..in` over dynamic-array-of-record / -of-class / set
- **Where:** everywhere — `for r in Rooms` (class), `for ex in r.Exits`
  (record), `for it in Player.Inventory` (record), `for sp in Player.Spells`
  (set).
- **Why predicted:** `for..in` Slice A (native arrays/sets) + Slice B
  (enumerator) landed, but element binding for **record** and **class** element
  types, and **set** iteration, need confirming. Copy-vs-alias semantics for
  record elements is the subtle bit.
- **Honest fix:** ensure native `for..in` binds record/class/set element types
  correctly (Slice A scope).

### F6. Procedural-type table + `@proc` + indirect call passing `Self`
- **Where:** `TCmd = procedure(g: TGame; const arg: AnsiString)`; `@CmdLook`;
  `v.Run(Self, rest)` in `TGame.Run`.
- **Why predicted:** procedural types Phase A done + `@proc` cross-target, but
  storing standalone-proc addresses in a record field, iterating the table with
  `for..in`, and passing `Self` (a class instance) as the first arg combine
  several paths.
- **Honest fix:** verify proc-typed record fields + indirect call ABI.

### F7. Property with getter
- **Where:** `TPlayer.Alive: Boolean read GetAlive`; used in `Run`'s
  `while … and Player.Alive`.
- **Why predicted:** properties work on the RTTI/LFM path; a plain read-getter
  property on a user class in a loop condition should be fine, but is untested
  here.
- **Honest fix:** confirm read-property lowering.

### F8. `StrToIntDef`
- **Where:** `TGame.LoadFrom` (`energy=` parse).
- **Why predicted:** may not exist in the PXX RTL.
- **Honest fix:** add `StrToIntDef`, or replace with a local int parser (we
  already hand-rolled `NumStr`; a `StrToInt` twin is trivial).

### F9. Unsigned 32-bit PRNG (`LongWord` + `shl`/`shr`/`mod` + `Integer()` cast)
- **Where:** `TGame.NextRand` (engine.pas) — xorshift32 over `Seed: LongWord`.
- **Why predicted:** needs an unsigned 32-bit type (`LongWord`/`Cardinal`) with
  logical (not arithmetic) `shr`, `shl` wrap, unsigned `mod`, and a
  `LongWord`→`Integer` cast. Native shifts landed (xtensa/rv32 work), but
  unsigned-type semantics + the cast are untested here. On 32-bit targets watch
  for sign-extension creeping into `shr`.
- **Honest fix:** ensure `LongWord`/`Cardinal` logical shifts + unsigned `mod`.
- **Note:** the PRNG is a deliberate stopgap; the `feature-random-library`
  ticket replaces it. `NextRand` is the single swap point.

### F10. Nested procedure (inside a method) touching `Self` fields
- **Where:** `AddExit` nested in `TGame.LoadWorld`, indexing `Rooms[...]`
  (i.e. `Self.Rooms`).
- **Why predicted:** like F3 (frame capture) but the captured frame is a
  *method's*, so the nested proc must also reach the enclosing `Self`. Two
  stacked challenges. If F3 works but this doesn't, that's the `Self`-in-nested
  gap specifically.
- **Honest fix:** propagate `Self` into nested procedures of methods. Sidestep:
  make `AddExit` a private method of `TGame`.

## 🟢 Low — expected to work (classes/cross already done)

- Inheritance + `virtual`/`override` (`TBoss.Taunt` over `TMonster.Taunt`),
  constructors (`TGame.Create`, `TBoss.Create`), `nil` checks — classes-on-cross
  is done.
- Sets: `+`, `in`, literals `[spNop]`, `set of` enum.
- Enums + exhaustive `case`.
- Dynamic arrays: `SetLength`/`Length`/`High`, element assignment, record
  elements by value, in-place field mutation (`Rooms[i].Exits[n].Dir := …`).
- Records with managed (`AnsiString`) fields copied in/out of arrays.
- Strings: `Copy`, `Pos`, `Length`, `s[i]`, char compare, concatenation,
  `Chr`/`Ord`.
- ANSI escape output incl. 256-color (`ESC[38;5;Nm`) — just bytes to stdout.

## Notes for the loop

- Start by compiling `adventure.pas` (pulls `engine.pas`); the **first** error
  is almost certainly F1 (file I/O) or F4 (unit). Capture it verbatim as the
  first concrete sub-ticket.
- F1 and F3 are the two genuinely structural items; the rest is breadth/RTL.
- If `for..in` over record/class elements (F5) miscompiles, suspect the same
  lost-sign-extension / element-binding landmine noted in the open-array work
  (`project_open_array_length_gap`) — keep the lowering in shared IR.
