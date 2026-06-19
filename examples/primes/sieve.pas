program PrimeSieve;
uses strutils;   { IntToStr }
{ Sieve of Eratosthenes with manual bit packing.

  Platonic test app: it does the bit-twiddling by hand on a plain
  `array of Integer`, treating each 32-bit word as 32 flags. There is NO
  TBitArray / TBitSet dependency on purpose — the reusable bit-set type is a
  later stage; this program is the thing that *motivates* it and exercises the
  raw `shl / and / or / not` codegen on every target.

  Convention: a set bit means "composite". So a number is prime iff its bit is
  clear (and it is >= 2). Only the integers 0..LIMIT are tracked.

  Exercises: div/mod by a power of two, 1 shl b for b up to 31 (sign bit), the
  `not` mask for clearing, nested loops, and managed-string number formatting. }

const
  LIMIT     = 1000000;             { sieve numbers 0..LIMIT            }
  WORDBITS  = 32;
  WORDCOUNT = (LIMIT div WORDBITS) + 1;
  SHOWFIRST = 25;                  { print this many primes at the start }

type
  TBitWords = array[0..WORDCOUNT - 1] of Integer;

var
  bits: TBitWords;                 { bit[n] set => n is composite }

procedure SetComposite(n: Integer);
var w, b: Integer;
begin
  w := n div WORDBITS;
  b := n mod WORDBITS;
  bits[w] := bits[w] or (1 shl b);
end;

function IsComposite(n: Integer): Boolean;
var w, b: Integer;
begin
  w := n div WORDBITS;
  b := n mod WORDBITS;
  IsComposite := (bits[w] and (1 shl b)) <> 0;
end;

procedure Sieve;
var i, j: Integer;
begin
  { clear all words -> everything starts "prime" }
  for i := 0 to WORDCOUNT - 1 do bits[i] := 0;

  { 0 and 1 are not prime }
  SetComposite(0);
  SetComposite(1);

  i := 2;
  while i * i <= LIMIT do
  begin
    if not IsComposite(i) then
    begin
      { mark multiples starting at i*i (smaller multiples already marked) }
      j := i * i;
      while j <= LIMIT do
      begin
        SetComposite(j);
        j := j + i;
      end;
    end;
    i := i + 1;
  end;
end;

var
  n, count, lastPrime, shown: Integer;
  line: AnsiString;
begin
  Sieve;

  writeln('Sieve of Eratosthenes up to ', LIMIT,
          ' (', WORDCOUNT, ' words, ', WORDCOUNT * 4, ' bytes packed).');

  count := 0;
  lastPrime := 0;
  shown := 0;
  line := '';
  for n := 2 to LIMIT do
    if not IsComposite(n) then
    begin
      count := count + 1;
      lastPrime := n;
      if shown < SHOWFIRST then
      begin
        if line <> '' then line := line + ' ';
        line := line + IntToStr(n);
        shown := shown + 1;
      end;
    end;

  writeln('First ', SHOWFIRST, ' primes: ', line);
  writeln('Total primes <= ', LIMIT, ': ', count);
  writeln('Largest prime <= ', LIMIT, ': ', lastPrime);
end.
