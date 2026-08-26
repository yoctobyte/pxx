{ A subrange bound is an ORDINAL, so it is parsed at the simple-expression
  level — below the relational one.

  It was not, and the `=` that starts a typed constant's initialiser got eaten
  as an equality operator:

    const t: array[0..3] of 0..15 = (%0000, %1000, %0100, %1100);

  parsed the high bound as `15 = (0`, then demanded a ')' and found a ','. The
  same declaration with a NAMED subrange element (`of TNibble`) was fine, and
  so was the array with no initialiser, which is what made it look like a
  typed-const bug rather than a bound-precedence one. ConstEval only grew its
  relational level recently (for `const Is64 = SizeOf(Pointer) = 8`), and every
  spelling of `lo..hi` had been calling it.

  reverse_byte is FPC's own, from fpc-source compiler/cutils.pas:303 — the
  declaration that found this, and the reason it matters: it sits in the second
  unit of the FPC compiler, so everything behind it was unreachable.

  All four sites that parse a bound go through one function now, because they
  are one construct: the anonymous subrange, the named `T = lo..hi`, the
  element of `set of lo..hi`, and an array dimension. The last two rows keep
  the operators a bound genuinely contains working — ZenGL's
  `High(LongWord) shr 1 - 1` is the real one. }
program test_subrange_bound_stops_at_the_initialiser;

type
  TNibble = 0..15;
  TLetter = 'a'..'z';

const
  { the one that failed: anonymous subrange element + an initialiser }
  reverse_nible: array[0..15] of 0..15 =
    (%0000,%1000,%0100,%1100,%0010,%1010,%0110,%1110,
     %0001,%1001,%0101,%1101,%0011,%1011,%0111,%1111);

  { the same shape at every other spelling of a bound }
  named:   array[0..3] of TNibble = (1, 2, 3, 4);
  letters: array[0..2] of 'a'..'z' = ('x', 'y', 'z');
  scalar:  0..15 = 9;
  chr:     'a'..'z' = 'q';
  bits:    set of 0..15 = [1, 3, 5];

  { a bound that really does hold an expression — term and additive level }
  big: array[0..High(LongWord) shr 30 - 1] of Byte = (7, 8, 9);

var
  v: array[0..3] of 0..15 = (0, 8, 4, 12);
  lt: TLetter;

function reverse_byte(b: Byte): Byte;
begin
  reverse_byte := (reverse_nible[b and $f] shl 4) or reverse_nible[b shr 4];
end;

begin
  writeln(reverse_byte(1), ' ', reverse_byte(2), ' ', reverse_byte($a5));
  writeln(named[0], named[1], named[2], named[3]);
  writeln(letters[0], letters[1], letters[2]);
  writeln(scalar, ' ', chr);
  writeln(3 in bits, ' ', 4 in bits);
  writeln(High(big) - Low(big) + 1);
  writeln(big[0], big[1], big[2]);
  writeln(v[1], ' ', v[3]);
  lt := 'k';
  writeln(lt);
end.
