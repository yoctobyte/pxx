{ `x in [constants]` is a BOOLEAN.

  The constant-set `in` node carried NO TYPE at all -- it defaulted to tyUnknown and was
  treated as an integer:

      writeln(e in [a, b])                          printed 1, not TRUE
      (e in [a, b]) and (ch in ['a'..'z'])          did a BITWISE integer `and` of two
                                                    booleans -- numerically right only because
                                                    the operands happen to be 0/1

  The RUNTIME-set path (an ordinary binop) has always been typed tyBoolean, so the SAME
  expression behaved differently depending on which path it took. That asymmetry is the tell,
  and it is why nobody noticed: assigning it to a Boolean coerced fine, and `if x in [..]`
  worked, so only printing it -- or reasoning about its type -- exposed it. }
program test_in_is_boolean_b301;
type TE = (a, b, c, d);
var e: TE; ch, q: Char; r: Boolean;
begin
  e := b; ch := 'x'; q := 'x';
  writeln('const enum : ', e in [a, b]);
  writeln('const char : ', ch in ['a'..'z']);
  writeln('runtime    : ', ch in [q]);
  r := e in [a, b];
  writeln('via bool   : ', r);
  writeln('combined   : ', (e in [a, b]) and (ch in ['a'..'z']));
end.
