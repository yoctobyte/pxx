program test_const_array_align;
{ A typed const array must start on a boundary its ELEMENT TYPE requires.

  bug-a-a-double-typed-const-misaligns-the-next-const-array-in-the-data-section

  THE ADDRESS IS TWO TERMS AND THIS TEST GUARDS THE SECOND ONE.
  A typed const array's address is `dataBase + offset`:

    - `dataBase` was the broken half. Every ELF writer places data straight
      after code (`LOAD_ADDR + codeOffset + CodeLen`), so the section started
      wherever the last instruction ended -- an arbitrary byte residue that
      moved with every byte of emitted code. Held now by AlignCodeForData
      (df98fea47) and asserted, on the one executable path where it can still
      fail, by the esp-bare-*-data-align8 rows in test-esp.

    - `offset` is what THIS test guards: TryBakeConstArrayIntoData's
      `base := AlignTo(DataLen, TypeAlign(elemTk))` in symtab.inc. Nothing
      asserted it, and it is one line from a silent regression -- a new
      bakeable element type whose TypeAlign is wrong, or an edit that advances
      the cursor after aligning it.

  It is a test that can FAIL, which is the only kind worth adding here. On a
  hosted image the data section is a PT_LOAD boundary and therefore page-
  aligned, so `dataBase mod 8` is 0 by construction and every residue this
  program can observe belongs to the offset term. Break the AlignTo and these
  assertions go red; break the base instead and the test-esp rows go red.
  Verified against pin v394 (`53800fbeb0b6`), which predates the fix: all six
  rows report MISALIGNED there and the OK token is absent.

  EACH ARRAY IS ASSERTED TO ITS OWN ELEMENT ALIGNMENT, NOT UNIFORMLY TO 8.
  An `array of Cardinal` is contracted to 4, and it lands on 8 today only
  because of what precedes it. Asserting 8 for it would be asserting luck --
  the exact error the ticket warns about, where every 0 in a grid reads as
  correctness and some of them are arithmetic. A row here fails only when the
  compiler breaks a promise it actually made.

  WHY THE WIDTHS MATTER: xtensa's l32i FAULTS on a misaligned word rather than
  absorbing it -- 41 windowed programs died on exactly this. x86-64 and riscv32
  tolerate it, which is why it survived: on five of six targets an under-aligned
  const array returns the right answer and looks fine.

  ONE RESIDUE, NOT SEVEN: a shifted section shifts everything in it equally, so
  the defect this replaces gave every array in a program the SAME residue
  (measured 7/7/7 across two element types against pin v394). A single-array
  test would have passed on any binary whose section happened to land right,
  which is why there are several arrays here at several positions.

  NO FLOAT-ELEMENT ARRAY, DELIBERATELY: `@C[0]` where C is an `array of Double`
  does not COMPILE on i386/arm32/riscv32 -- `unsupported float operator`, with
  no float operation in the program. That is a separate defect in address
  computation, filed as
  bug-a-taking-the-address-of-a-float-array-element-is-a-float-operator-on-32-bit.
  A Double element needs the same 8 that Int64 needs, so no alignment coverage
  is lost by using Int64 here; add the float rows when that ticket closes. }

const
  { first in the section -- the case with nothing of ours before it }
  A: array[0..3] of Int64 = (1, 2, 3, 4);
  { a scalar Double between two arrays: the shape the original ticket named.
    Declaring it is fine on every target; only INDEXING a float array is not. }
  Pi: Double = 3.14159;
  B: array[0..3] of Int64 = (5, 6, 7, 8);
  { 4-byte elements: contracted to 4, and asserted at 4 for that reason }
  D: array[0..3] of Cardinal = (1, 2, 3, 4);
  { an odd-length byte array leaves the cursor odd for whatever follows it }
  F: array[0..2] of Byte = (1, 2, 3);
  G: array[0..3] of Int64 = (9, 10, 11, 12);
  H: array[0..3] of Cardinal = (5, 6, 7, 8);

var
  bad, checked: Integer;

procedure Check(const nm: AnsiString; p: PtrUInt; need: Integer);
begin
  Inc(checked);
  if (p mod PtrUInt(need)) <> 0 then
  begin
    writeln('MISALIGNED ', nm, ' needs ', need, ' @ mod ', need, ' = ',
            p mod PtrUInt(need));
    Inc(bad);
  end;
end;

begin
  bad := 0;
  checked := 0;
  Check('A', PtrUInt(@A[0]), 8);
  Check('B', PtrUInt(@B[0]), 8);
  Check('G', PtrUInt(@G[0]), 8);
  Check('D', PtrUInt(@D[0]), 4);
  Check('H', PtrUInt(@H[0]), 4);
  { read the data too, so the arrays cannot be optimised out of .data and
    leave the alignment assertions checking addresses nothing uses }
  if (A[3] + B[3] + G[3]) <> (4 + 8 + 12) then
  begin
    writeln('WRONG VALUES');
    Inc(bad);
  end;
  if (D[3] + H[3] + F[2]) <> (4 + 8 + 3) then
  begin
    writeln('WRONG VALUES 32');
    Inc(bad);
  end;
  { A positive token the subject itself emits, never a bare exit status: a
    status can be produced by something other than this program running. The
    count is the variable, not a literal, so dropping a Check cannot leave the
    token claiming coverage that is no longer there. }
  if bad = 0 then writeln('CONST-ARRAY-ALIGN OK checked=', checked);
end.
