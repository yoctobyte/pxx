{ SPDX-License-Identifier: Zlib }
unit mimic_uuid;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `uuid`, the part That Space Program calls: `uuid.uuid4()` and the
  UUID's `.hex` (tsp/universe.py names objects with `uuid4().hex[:12]`).
  `import uuid` resolves here through the NilPy import resolver's `mimic_`
  fallback, as mimic_time's header describes.

  A PASCAL unit because the randomness is a syscall: PalRandomBytes fills from
  the platform CSPRNG (getrandom on Linux), which is where CPython's uuid4 gets
  its bytes too (os.urandom). A PRNG would give ids that repeat across runs
  started from the same seed, and ids that name rows in a universe file must
  not repeat.

  The subset: uuid4, and on UUID the fields `hex` and `version` plus str() in
  the 8-4-4-4-12 form. Absent: uuid1/3/5, parsing a UUID from a string,
  `.int`/`.bytes`/`.fields`, comparison and hashing. A missing name fails at its
  call site. }

interface

uses pylib, sysutils, platform;

type
  UUID = class
  public
    { 32 lowercase hex digits, no dashes -- CPython's `UUID.hex`. }
    hex: AnsiString;
    { 4 for a uuid4. CPython answers None for a non-RFC variant; every UUID
      this unit makes is RFC 4122, so it is always an int here. }
    version: Integer;
    function __str__: AnsiString;
  end;

{ A random (version 4) UUID: 122 random bits from the platform CSPRNG, with the
  version nibble set to 4 and the variant bits to 10, as RFC 4122 lays out.
  Raises OSError if the platform cannot supply randomness, as os.urandom does. }
function uuid4: UUID;

implementation

function UUID.__str__: AnsiString;
begin
  Result := Copy(hex, 1, 8) + '-' + Copy(hex, 9, 4) + '-' + Copy(hex, 13, 4) + '-'
            + Copy(hex, 17, 4) + '-' + Copy(hex, 21, 12);
end;

function uuid4: UUID;
const
  DIGITS: AnsiString = '0123456789abcdef';
var
  b: array[0..15] of Byte;
  i: Integer;
begin
  if PalRandomBytes(@b[0], 16) <> 0 then
    raise OSError.Create('uuid4: the platform could not supply random bytes');
  b[6] := (b[6] and $0F) or $40;   { version 4 }
  b[8] := (b[8] and $3F) or $80;   { variant 10: RFC 4122 }
  Result := UUID.Create;
  Result.version := 4;
  Result.hex := '';
  for i := 0 to 15 do
    Result.hex := Result.hex + DIGITS[(b[i] shr 4) + 1] + DIGITS[(b[i] and $0F) + 1];
end;

end.
