program test_every_variant_arm_starts_at_the_same_offset;
{ bug-a-xtensa-variant-record-arms-start-at-different-offsets.

  ASSERTS A RELATION, NEVER AN OFFSET, which is what makes one file correct on
  six targets with three different right answers: x86-64 and aarch64 put this
  variant part at 8, i386 at 4, and xtensa/arm32/riscv32 at 8 for a different
  reason again. A per-target offset table would be six rows of bookkeeping that
  go stale the first time anyone adds a target, and it would assert the thing
  that is ALLOWED to differ while saying nothing about the thing that is not.

  What is not allowed to differ is that every arm of one variant part begins at
  the SAME offset. That is the whole meaning of the construct: a program writes
  through one arm and reads through another on purpose. Before the fix, on every
  32-bit target whose Int64 aligns to 8 as a MEMBER -- xtensa, arm32, riscv32 --
  the Int64 arm started at 8 and the Integer arm at 4, so `v.A := ...; v.L`
  returned the wrong four bytes with no diagnostic anywhere. i386 escaped only
  because TypeFieldAlign caps its scalars at 4, and x86-64 because its pointer
  is already as wide as the widest member alignment -- which is exactly the
  coincidence the old code mistook for a rule.

  THE LAST TWO ROWS ARE THE ONES THAT WOULD HAVE CAUGHT IT ANYWAY, and they are
  here because an offset relation is a claim about the layout TABLE while the
  bug people actually hit is a wrong VALUE: write through the wide arm, read the
  halves back, and check they are the halves. On a target where the arms are
  four bytes apart that reads one word of the Int64 and one word of whatever
  follows. }

type
  TVar = record
    Tag: Integer;
    case Integer of
      0: (A: Int64);
      1: (L, H: LongWord);
  end;

  { a second shape, to keep the fix from being about Int64 specifically: the
    WIDE arm is second here, and the narrow arm is the one that would have been
    laid out from the under-aligned base. }
  TVar2 = record
    Tag: Byte;
    case Byte of
      0: (Small: Word);
      1: (Wide: Double);
  end;

var
  v: TVar;
  w: TVar2;

begin
  WriteLn('arms agree: ', PtrUInt(@v.A) = PtrUInt(@v.L));
  WriteLn('second name in the arm follows the first: ',
          PtrUInt(@v.H) - PtrUInt(@v.L) = SizeOf(v.L));
  WriteLn('arms agree (wide arm second): ', PtrUInt(@w.Small) = PtrUInt(@w.Wide));

  { the tag is still in front of the union, on every target }
  WriteLn('tag precedes the arms: ', PtrUInt(@v.A) > PtrUInt(@v.Tag));

  { ...and the record is big enough to hold its widest arm from that base }
  WriteLn('size covers the widest arm: ',
          SizeOf(v) >= (PtrUInt(@v.A) - PtrUInt(@v)) + SizeOf(v.A));

  { THE VALUE ROWS. }
  v.A := $00000002FFFFFFF1;
  WriteLn('low half=', v.L, ' high half=', v.H);

  v.L := 7;
  v.H := 0;
  WriteLn('read back through the wide arm=', v.A);
end.
