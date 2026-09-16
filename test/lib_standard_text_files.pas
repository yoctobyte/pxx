{ FPC's five standard text files exist as Text, and can be PASSED.

  `StdErr` existed only as an integer CONSTANT (the fd) that the parser
  special-cases in the Write/WriteLn file-target position. That makes
  `WriteLn(StdErr, s)` work and nothing else -- an fd is not a Text, so it
  cannot bind to a `var f: Text` parameter and cannot reach `Flush`. FPC's own
  compiler does both, three lines apart (comphook.pas:397 and :399):

      WriteMsgTypeColored(StdErr, MsgTypeStr);
      flush(StdErr);

  THE ROWS THAT MATTER ARE THE ONES THAT PASS A FILE, NOT THE ONES THAT WRITE
  TO IT. Every direct `WriteLn(Std..., s)` spelling below already worked
  through the parser's fd path before this change, so a fixture built out of
  those rows would have been green on the unfixed RTL -- they are here as the
  control that the fd path still works, not as the subject.

  `Output` is the second control and it is the sharper one: passing IT to a
  `var f: Text` parameter has always worked, which is what establishes that the
  mechanism was never missing and only three of the five files were.

  WHAT THIS CANNOT ASSERT FROM INSIDE ONE PROCESS is which descriptor each
  write landed on -- both fds are this program's own and WriteLn reports
  nothing back. The Makefile row is what separates them: it runs this program
  with stdout and stderr captured SEPARATELY and diffs each, so a change that
  routed stderr to stdout would pass every Chk here and still go red there. }
program lib_standard_text_files;

uses textfile;

var
  ok, total: LongInt;

procedure Chk(cond: Boolean; const what: string);
begin
  total := total + 1;
  if cond then ok := ok + 1
  else WriteLn('FAIL: ', what);
end;

{ the whole point: a Text you can hand to someone else }
procedure WriteVia(var f: Text; const s: string);
begin
  WriteLn(f, s);
end;

function HandleVia(var f: Text): LongInt;
begin
  HandleVia := f.Handle;
end;

begin
  ok := 0; total := 0;

  { the five files exist and carry the descriptors FPC gives them }
  Chk(Input.Handle = 0, 'Input is fd 0');
  Chk(Output.Handle = 1, 'Output is fd 1');
  Chk(StdOut.Handle = 1, 'StdOut is fd 1');
  Chk(ErrOutput.Handle = 2, 'ErrOutput is fd 2');
  Chk(StdErr.Handle = 2, 'StdErr is fd 2');

  { ...and are PASSABLE, which is the thing that was missing. Reading the
    handle back through a var parameter proves the callee got that very
    record and not a copy of some other one. }
  Chk(HandleVia(Output) = 1, 'Output passes to a var Text parameter');
  Chk(HandleVia(StdOut) = 1, 'StdOut passes to a var Text parameter');
  Chk(HandleVia(ErrOutput) = 2, 'ErrOutput passes to a var Text parameter');
  Chk(HandleVia(StdErr) = 2, 'StdErr passes to a var Text parameter');

  { Flush accepts them -- comphook.pas:399. PXX text writes go straight to the
    fd, so Flush only has to exist and accept the file. }
  Flush(StdErr); Flush(ErrOutput); Flush(StdOut); Flush(Output);
  Chk(True, 'Flush accepts all four output files');

  { stdout and stderr are SEPARATE records, so assigning one must not move the
    other -- they are two names for a descriptor, not one variable }
  Chk(StdOut.Handle <> StdErr.Handle, 'StdOut and StdErr are different fds');
  Chk(@StdOut <> @ErrOutput, 'StdOut and ErrOutput are distinct records');
  Chk(@StdErr <> @ErrOutput, 'StdErr and ErrOutput are distinct records');

  { the routing rows. Read by the Makefile from two captured streams, not from
    here -- see the header. }
  WriteVia(StdErr, 'E1 via var param');
  WriteVia(ErrOutput, 'E2 via var param');
  WriteLn(StdErr, 'E3 direct');
  WriteVia(StdOut, 'O1 via var param');
  WriteLn(StdOut, 'O2 direct');
  WriteLn('O3 plain');

  WriteLn('total ok ', ok, ' / ', total);
end.
