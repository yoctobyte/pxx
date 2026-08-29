program DynSlice;

{ Dynamic arrays on wasm32: the layout, not the heap.

  The heap arrived in Phase 6 and is not what was missing. A dynamic array is a
  HANDLE to a block whose element count sits one word below the data, and the
  four things that had to exist are the deref (IR_LEA yields the data pointer),
  the element arithmetic (IR_INDEX), the count (Length reads [data-8]), and
  SetLength, which takes the SLOT and not the handle.

  What a happy-path "SetLength then index" would not catch, and each of these
  is a way the layout can be wrong while the output looks right:

    * SLOT vs HANDLE. PXXDynSetLen treats a nil arrSlot as "nothing to do", so
      handing it the handle of a FRESH array makes SetLength silently succeed
      and allocate nothing. Every later index then reads through nil.
    * ALIASING. `b := a` shares the block — a dynamic array is a reference type
      at every depth, so a write through b must be visible through a. A build
      that copied would pass every single-variable test here.
    * THE REFCOUNT, which no diff can see. Sharing without retaining leaks
      until it frees something still in use; the arena slope is the only
      witness, and it needs two counts to separate the constant term.
    * nil IS ZERO ELEMENTS. `Length(a)` on a declared-but-never-SetLength array
      is legal and answers 0; without a guard it reads address -8. }

type
  { Named, because `const p: array of Integer` is an OPEN ARRAY parameter — a
    different feature with its own refusal. This slice is about the dynamic
    array itself, so the parameters must name a dyn-array TYPE. }
  TIntArr = array of Integer;
var
  a, b, a2: TIntArr;
  s: array of string;
  i, n: Integer;

{ A local so the SCOPE-EXIT release has something to release. Its leak is a
  different mechanism from an assignment's and check_dyn.sh probes them apart. }
{ The three parameter modes for a dynamic array. They differ only in how many
  times the callee must deref its slot, which is precisely what was wrong. }
procedure PassConst(const p: TIntArr);
begin writeln('const len=', Length(p), ' p0=', p[0], ' p2=', p[2]); end;

procedure PassValue(p: TIntArr);
begin writeln('value len=', Length(p), ' p0=', p[0], ' p2=', p[2]); end;

procedure PassVar(var p: TIntArr);
begin
  writeln('var   len=', Length(p), ' p0=', p[0], ' p2=', p[2]);
  p[0] := 99;          { by-reference: the caller must see this }
end;

procedure Local;
var t: array of Integer;
begin
  SetLength(t, 8);
  t[0] := 1;
end;

begin
  writeln('unset len=', Length(a));

  SetLength(a, 4);
  for i := 0 to 3 do a[i] := i * 11;
  writeln(a[0], ' ', a[1], ' ', a[2], ' ', a[3], ' len=', Length(a));

  { shrink keeps the head, grow zero-fills the tail }
  SetLength(a, 2);
  writeln('shrunk len=', Length(a), ' a0=', a[0], ' a1=', a[1]);
  SetLength(a, 5);
  writeln('grown len=', Length(a), ' a0=', a[0], ' a4=', a[4]);

  { ALIASING, and the write must be visible through BOTH names }
  b := a;
  b[0] := 99;
  writeln('alias a0=', a[0], ' b0=', b[0], ' blen=', Length(b));

  { SetLength on one of two aliases re-points that one only }
  SetLength(b, 2);
  writeln('after b resize: alen=', Length(a), ' blen=', Length(b),
          ' a4=', a[4], ' b0=', b[0]);

  SetLength(a, 0);
  writeln('zeroed len=', Length(a));

  { a variable index, so the element arithmetic is not constant-folded }
  SetLength(a, 6);
  for i := 0 to 5 do a[i] := 100 - i;
  n := 0;
  for i := 0 to Length(a) - 1 do n := n + a[i];
  writeln('sum=', n);

  { an array of MANAGED elements: the release walks them }
  SetLength(s, 3);
  s[0] := 'zero'; s[1] := 'one'; s[2] := 'two';
  writeln(s[0], '/', s[1], '/', s[2], ' slen=', Length(s));
  SetLength(s, 1);
  writeln('after shrink: ', s[0], ' slen=', Length(s));

  { THE RETAIN, which the arena slope cannot see. A missing IncRef makes
    refcounts too LOW, and too-low is a premature free, not a leak — the
    opposite direction from everything the leak probes measure. It is also
    invisible until the freed block is REUSED, which is why this allocates a
    same-sized array and fills it with a sentinel between the free and the
    read. Without that step the stale bytes survive and the wrong build prints
    the right answer; measured, with the retain deliberately removed: this
    prints 7777 where the native build prints 100 and 95. }
  SetLength(a, 6);
  for i := 0 to 5 do a[i] := 100 - i;
  b := a;
  SetLength(b, 2);       { drops b's reference to the block a still holds }
  SetLength(s, 0);
  SetLength(a2, 6);      { same size: reuses the block if it was wrongly freed }
  for i := 0 to 5 do a2[i] := 7777;
  writeln('after alias free: a0=', a[0], ' a5=', a[5]);

  Local;

  { PASSING ONE TO A ROUTINE — absent from this slice until 2026-08-29, and the
    omission hid a silent wrong answer for the whole of Phase 9a. `const` and
    by-value dyn-array parameters answered Length 0 and index 0 on wasm32 while
    the body reported as FULLY LOWERED; only `var` was right, because its extra
    indirection made the callee's second deref correct by accident.

    Every mode is here, because the three differ in exactly the deref depth
    that was wrong and testing one proves nothing about the others. }
  SetLength(a, 3);
  a[0] := 11; a[1] := 22; a[2] := 33;
  PassConst(a);
  PassValue(a);
  PassVar(a);
  writeln('after passvar: a0=', a[0], ' len=', Length(a));

  writeln('done');
end.
