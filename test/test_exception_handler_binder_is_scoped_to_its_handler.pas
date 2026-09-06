program test_exception_handler_binder_is_scoped_to_its_handler;
{ `on E: TClass do` declares E for the duration of THAT handler and no longer.

  We used to allocate the binder in the enclosing scope and never unhash it, so
  it stayed visible for the rest of the routine or program. That was invisible
  while name lookup preferred an exact-case match: a later `e` found the outer
  `e` and the leaked `E` was merely dead weight. Once a nearer declaration
  correctly outranked an exact-case one (99c416b54), the same `e` resolved to
  the binder instead -- which holds the exception object the handler has already
  destroyed -- and reading it SEGFAULTED.

  So the rows that matter are the ones that read the outer variable AFTER the
  handler has finished. A test that only reads E inside the handler passes with
  the binder leaking and is what let this sit undetected;
  test_class_inherits_from_tobject has the colliding shape three times over and
  is green for exactly that reason.

  EVERY LINE BELOW IS FPC 3.2.2's, byte for byte.

  The last two rows are the controls that make the first ones mean something:
  a binder that does NOT collide with anything must still work, and the binder
  must still be readable INSIDE its own handler. A fix that unhashed too eagerly
  breaks those and passes the rest. }
{$mode objfpc}{$H+}
uses sysutils;

var
  e: TObject;          { collides with the binder `E` case-insensitively }
  outer: string;

procedure InRoutine;
var e2: string;
begin
  e2 := 'routine-outer';
  try
    raise Exception.Create('boom');
  except
    on E2: Exception do WriteLn('  routine binder: ', E2.Message);
  end;
  WriteLn('  routine outer after: ', e2);
end;

begin
  e := TObject.Create;
  outer := 'program-outer';

  WriteLn('-- read the outer var AFTER the handler --');
  try
    raise Exception.Create('one');
  except
    on E: Exception do WriteLn('  binder: ', E.Message);
  end;
  WriteLn('  outer e is still: ', e.ClassName);

  WriteLn('-- same, inside a routine --');
  InRoutine;

  WriteLn('-- nested handlers, then read the outer --');
  try
    raise Exception.Create('outerraise');
  except
    on E: Exception do
    begin
      try
        raise Exception.Create('innerraise');
      except
        on E: Exception do WriteLn('  inner binder: ', E.Message);
      end;
      WriteLn('  outer binder still: ', E.Message);
    end;
  end;
  WriteLn('  outer e is still: ', e.ClassName);

  WriteLn('-- controls --');
  try
    raise Exception.Create('two');
  except
    on Distinct: Exception do WriteLn('  non-colliding binder: ', Distinct.Message);
  end;
  WriteLn('  outer string untouched: ', outer);
  WriteLn('-- done --');
end.
