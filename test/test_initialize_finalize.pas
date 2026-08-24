program test_initialize_finalize;
{ Initialize(x) / Finalize(x) over the ARC helpers.

  Both were no-ops. `Finalize(s)` on an AnsiString left `len=5 [hello]` where
  FPC prints `len=0 []` — FPC-shaped code that compiles, runs, and silently does
  not do what it says. Output below is byte-identical to FPC 3.x -Mobjfpc.

  Why the pair exists at all: scope-exit cleanup only covers variables the
  COMPILER declared. A record conjured from GetMem is just bytes to it, so its
  AnsiString field holds whatever the allocator last left there. Assigning to it
  would decrement a refcount through that garbage — an access violation — and
  FreeMem'ing without Finalize drops the references without decrementing — a
  leak. Both halves are exercised here.

  The two properties every check below is really about:
    - Finalize NILS after releasing, so a second Finalize decrements nothing.
      Lose this and the obvious double-Finalize is a heap corruption instead of
      a no-op. Checked for both a string and a record.
    - It releases a REFERENCE, not the object. `keep` is taken before each
      Finalize and must still print — a bespoke free would take it with it.

  n stays 3 after Finalize on purpose: unmanaged members are untouched, as in
  FPC. That is the line between Finalize and FillChar, and FillChar over managed
  fields is the hazard this intrinsic exists to replace.

  A BARE Variant was a compile error until
  feature-a-finalize-for-bare-dynarray-and-variant landed its separable half:
  Finalize(v) is PXXVarClear through the slot address, which reads the tag,
  releases what that tag says is a reference and writes VT_EMPTY — idempotent
  by construction, so it gets the second property above for free rather than by
  nil'ing afterwards. Initialize(v) is a 16-byte zero, because VT_EMPTY is 0 and
  Initialize must NOT release (its incoming bytes are not references).
  A bare dynamic array is still an error and still has the ticket. }

type
  TRec = record
    Name: AnsiString;
    Nums: array of Integer;
    N: Integer;
  end;
  PRec = ^TRec;
  TPlain = record A, B: Integer; end;

var
  s, keep: AnsiString;
  p: PRec;
  r: TPlain;
  i: Integer;
  v: Variant;

begin
  s := 'hello';
  Finalize(s);
  Writeln('len=', Length(s), ' [', s, ']');
  Finalize(s);                          { idempotent }
  Writeln('again len=', Length(s));

  s := 'world';
  keep := s;                            { refcount 2 }
  Finalize(s);
  Writeln('s len=', Length(s), ' keep=[', keep, ']');

  { the case scope-exit cleanup cannot reach: raw bytes from GetMem }
  p := GetMem(SizeOf(TRec));
  Initialize(p^);
  p^.Name := 'from-heap';               { safe ONLY because the field was nil'd }
  SetLength(p^.Nums, 3);
  p^.Nums[0] := 7;
  p^.N := 3;
  Writeln('rec [', p^.Name, '] n=', p^.N, ' nums0=', p^.Nums[0], ' len=', Length(p^.Nums));
  Finalize(p^);
  Writeln('after fin: namelen=', Length(p^.Name), ' numslen=', Length(p^.Nums), ' n=', p^.N);
  Finalize(p^);
  Writeln('after fin2: namelen=', Length(p^.Name));
  FreeMem(p);

  { no managed members, and a plain ordinal: legal and does nothing, as in FPC.
    A generic container that finalizes every element type has to compile for
    these too, so they must not be errors. }
  r.A := 1; r.B := 2;
  Finalize(r);
  Initialize(r);
  i := 5;
  Finalize(i);
  Writeln('plain ', r.A, ' ', r.B, ' ', i);

  { bare Variant. The string rows are the ones that matter — a variant holding
    an AnsiString owns a reference, and this is where a wrong clear either leaks
    it or takes `keep` with it. }
  v := 'hello';
  Finalize(v);
  Writeln('var [', v, ']');
  Finalize(v);                          { idempotent, as for the string above }
  Writeln('var again [', v, ']');
  keep := 'world';
  v := keep;                            { refcount 2 }
  Finalize(v);
  Writeln('var [', v, '] keep=[', keep, ']');
  v := 42;                              { an unmanaged tag: clears, releases nothing }
  Finalize(v);
  Writeln('var int [', v, ']');
  v := 7;
  Initialize(v);
  Writeln('var init [', v, ']');

  Writeln('done 0');
end.
