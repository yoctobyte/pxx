{ `Free;` with no receiver at all, inside a method — that is `Self.Free`, and it
  is the FIFTH spelling of one concept. The frontend recognises four:

      obj.Free;            { a bare symbol            }
      FField.Free;         { an implicit-Self field   }
      TObject(x).Free;     { a cast                   }
      L.Objects[i].Free;   { a general designator     }

  each of them keyed on a RECEIVER. A receiver-less `Free;` has none to
  recognise, so it fell past every door and out the far side as

    error: undefined variable (Free)

  — a message about a VARIABLE, for a call, which is why it does not read as a
  member of the family it belongs to. fcl-passrc's pastree.pp:2979 is the live
  case: `TPasElement.Release` frees the element it has just refcounted to zero.

  WHICH ROW ASSERTS WHAT, MEASURED BY DISABLING THE NEW ARM AND REBUILDING —
  not inferred, because three of these four rows were already green and a file
  where every row passes for a different reason reads as one strong test.

    bare   THE FIX. With the arm disabled this row does not compile at all:
           `undefined variable (Free)`.
    self   `Self.Free;` ALREADY WORKED — it is the sibling spelling, and it is
           in this file as a NO-REGRESSION control, not as an assertion. The two
           spellings mean the same thing and travel different paths; split
           across two files each prints a plausible count and passes alone.
    user   A class declaring its own `Free` must reach the USER method, and
           MEASURED: that is decided by an earlier arm, not by this one — the
           row is unchanged with this arm's `FindUMeth(..., 'Free') < 0`
           condition removed. The condition stays because every sibling arm
           carries it and it makes this arm correct independently of arm order,
           but it is belt-and-braces and this row does not prove it.
    alive  The UNTAKEN branch. `Free` is conditional here, so the row where the
           condition is false must leave the object fully usable — the desugar
           must not disturb `Self` on the way past. A test that only ever takes
           the branch cannot see a fix that damages the one it skips.
  bug-p-a-receiverless-free-inside-a-method-is-an-undefined-variable }
{$mode objfpc}
program test_a_receiverless_free_inside_a_method;
type
  TE = class
    N: Integer;
    procedure Release;
    destructor Destroy; override;
  end;

  TS = class
    N: Integer;
    procedure Release;
    destructor Destroy; override;
  end;

  { declares its own Free — the user method must win }
  TU = class
    N: Integer;
    procedure Free;
    procedure Release;
    destructor Destroy; override;
  end;

var
  freed, marked: Integer;

destructor TE.Destroy;
begin
  freed := freed + 1;
  inherited Destroy;
end;

procedure TE.Release;
begin
  N := N - 1;
  if N = 0 then
    Free;                     { the receiver-less spelling }
end;

destructor TS.Destroy;
begin
  freed := freed + 1;
  inherited Destroy;
end;

procedure TS.Release;
begin
  N := N - 1;
  if N = 0 then
    Self.Free;                { the sibling spelling, same meaning }
end;

destructor TU.Destroy;
begin
  freed := freed + 1;
  inherited Destroy;
end;

procedure TU.Free;
begin
  marked := marked + 1;
end;

procedure TU.Release;
begin
  N := N - 1;
  if N = 0 then
    Free;                     { must reach TU.Free, not the destructor }
end;

var
  e: TE;
  s: TS;
  u: TU;
begin
  freed := 0; marked := 0;

  e := TE.Create; e.N := 1;
  e.Release;
  WriteLn('bare      freed=', freed);

  s := TS.Create; s.N := 1;
  s.Release;
  WriteLn('self      freed=', freed);

  u := TU.Create; u.N := 1;
  u.Release;
  WriteLn('user      freed=', freed, ' marked=', marked);

  { the UNTAKEN branch: N reaches 1, not 0, so nothing is freed and the object
    must still answer for itself }
  e := TE.Create; e.N := 2;
  e.Release;
  WriteLn('alive     freed=', freed, ' n=', e.N);
end.
