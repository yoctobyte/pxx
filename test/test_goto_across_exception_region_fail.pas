program test_goto_across_exception_region_fail;
{ Every `goto` marked CROSS jumps into or out of a protected region and must be
  refused with "Jump in or outside of an exception block" AT ITS OWN LINE; every
  unmarked one stays inside its region and must not be. IR lowering stops at the
  first recovered diagnostic, so each case sits behind its own define (C1..C9) and
  the Makefile row compiles them one at a time: the ONE reported line must be
  the `CROSS Cn` line, so a missed crossing and a legal goto blamed in its place
  are both red. With no define the file must compile -- the control that the
  only errors are the marked ones.

  A plain jump emits no IR_EXC_ENTER / IR_EXC_LEAVE, so jumping OUT left the
  region's frame on the chain in dead stack and the next unhandled raise
  longjmped into it (segfault, no diagnostic); jumping IN popped a frame that
  was never pushed. FPC refuses both with the same words.
  bug-a-something-in-lekkerzeilen-s-startup-still-leaves-an-exception-frame-on-the-chain }
{$mode objfpc}
uses sysutils;

{$ifdef C1}
procedure OutForward;
label l;
begin
  try
    goto l;   { CROSS C1 }
  except
  end;
  l:
end;
{$endif}

{$ifdef C2}
procedure OutBackward;
label l;
begin
  l:
  try
    goto l;   { CROSS C2 }
  except
  end;
end;
{$endif}

{$ifdef C3}
procedure IntoTry;
label l;
begin
  goto l;   { CROSS C3 }
  try
    l:
  except
  end;
end;
{$endif}

{$ifdef C4}
procedure SiblingTries;
label l;
begin
  try
    goto l;   { CROSS C4 }
  except
  end;
  try
    l:
  except
  end;
end;
{$endif}

{$ifdef C5}
procedure OutOfOnHandler;
label l;
begin
  try
    raise Exception.Create('x');
  except
    on E: Exception do
      goto l;   { CROSS C5 }
  end;
  l:
end;
{$endif}

{$ifdef C6}
procedure OutOfFinallyBody;
label l;
begin
  try
    goto l;   { CROSS C6 }
  finally
  end;
  l:
end;
{$endif}

{$ifdef C7}
{ Two forward gotos to one label: the legal one first, the crossing one second. }
procedure LegalThenCrossing;
label l;
begin
  goto l;
  try
    goto l;   { CROSS C7 }
  except
  end;
  l:
end;
{$endif}

{$ifdef C8}
{ The same pair the other way round -- the crossing one first. A check that
  remembered only the first forward goto blames the legal one here. }
procedure CrossingThenLegal;
label l;
begin
  try
    goto l;   { CROSS C8 }
  except
  end;
  goto l;
  l:
end;
{$endif}

{$ifdef C9}
{ Out of an inner try into the outer one it is nested in: one region out. }
procedure InnerToOuter;
label l;
begin
  try
    try
      goto l;   { CROSS C9 }
    except
    end;
    l:
  except
  end;
end;
{$endif}

begin
end.
