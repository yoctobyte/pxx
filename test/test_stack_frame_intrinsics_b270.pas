{ System stack-frame intrinsics: get_frame / get_pc_addr / get_caller_stackinfo.
  FPC has these in System, so they are reached with NO uses -- soft keywords, like
  Inc/Dec. fpcunit's CallerAddr (reproduced verbatim below) walks the saved-fp chain
  with them to record where an assertion failed.

  Only booleans are printed: the actual addresses differ per target, but the
  RELATIONS between them do not, so one expected output covers every backend. }
program test_stack_frame_intrinsics_b270;

{ verbatim from fpcunit.pp }
function CallerAddr: Pointer;
var bp, pcaddr: Pointer;
begin
  bp := get_frame;
  pcaddr := get_pc_addr;
  get_caller_stackinfo(bp, pcaddr);
  if bp <> nil then get_caller_stackinfo(bp, pcaddr);
  Result := pcaddr;
end;

{ stands in for fpcunit's TAssert.Fail: the frame CallerAddr must see past }
function Where: Pointer;
begin
  Result := CallerAddr;
end;

function Inner: Boolean;
var bp, pc0, pc1, pc2: Pointer;
begin
  bp := get_frame;
  pc0 := get_pc_addr;              { return address into Inner's caller }
  get_caller_stackinfo(bp, pc1);   { <- reads from Inner's OWN frame, so pc1 = pc0 }
  get_caller_stackinfo(bp, pc2);   { now one frame up: a DIFFERENT address }
  { get_pc_addr and the first get_caller_stackinfo agree by construction -- both
    read [fp + retoff] off the same frame. That is exactly why fpcunit calls
    get_caller_stackinfo TWICE to reach its caller's caller. }
  Result := (pc0 = pc1) and (pc1 <> pc2) and (pc2 <> nil);
end;

{ The intrinsics are only legal inside a ROUTINE: the program body runs at the ELF
  entry and is the outermost frame (rbp = 0), so it has nothing to read or walk.
  Using them there is a compile-time error, not a segfault. }
procedure Probe;
var a, b, c: Pointer;
begin
  writeln('frame nonnil: ', get_frame <> nil);
  writeln('pc nonnil: ', get_pc_addr <> nil);
  writeln('empty parens: ', get_frame() <> nil);
  writeln('walk: ', Inner);

  { fpcunit's real shape: TAssert.Fail calls CallerAddr, so CallerAddr walks TWO
    frames -- past Fail -- to land on the TEST METHOD's line. Where() stands in for
    Fail here, so each Where() call site must yield its own address. }
  a := Where;
  b := Where;
  c := Where;
  { A real return address, not a constant: each call site pushes its own. }
  writeln('per-site distinct: ', (a <> b) and (b <> c) and (a <> c));
  { ...and they grow with source order, because the call sites do. }
  writeln('ascending: ', (a < b) and (b < c));
end;

begin
  Probe;
end.
