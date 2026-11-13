{ ===== Linux arm64's ABI in front of an x86-64 translator =====
  Included by the BSD translators (fbsdabi, nbsdabi) under CPU_AARCH64. The
  RTL and the compiler speak Linux's asm-generic syscall table on arm64. It
  names the same calls as x86-64's under other numbers, so the front maps the
  number and hands the call to the including unit's LxX64Call -- its x86-64
  dispatch, which already knows the BSD. What differs in the arguments is
  converted here:
  struct stat (128 B, nlink and mode swapped in size and place), epoll_event
  (16 B, not packed), struct sigaction (no sa_restorer, so the mask is at 16),
  four open(2) flag bits, and clone, which is how arm64 forks. Everything else
  -- errno, signals, mmap, sockets, termios, poll, timers -- is the same on
  both. feature-port-freebsd-native }
const
  A64ToX64: array[0..293] of SmallInt = (
    206, 207, 209, 210, 208, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198,
    199, 79, 212, 290, 291, 233, 281, 32, 292, 72, 294, 254, 255, 16, 251, 252,
    73, 259, 258, 263, 266, 265, 264, 166, 165, 155, -1, 137, 138, 76, 77, 285,
    269, 80, 81, 161, 91, 268, 260, 93, 257, 3, 153, 293, 179, 217, 8, 0,
    1, 19, 20, 17, 18, 295, 296, 40, 270, 271, 289, 278, 275, 276, 267, 262,
    5, 162, 74, 75, 277, 283, 286, 287, 280, 163, 125, 126, 135, 60, 231, 247,
    218, 272, 202, 273, 274, 35, 36, 38, 246, 175, 176, 222, 224, 225, 223, 226,
    227, 228, 229, 230, 103, 101, 142, 144, 145, 143, 203, 204, 24, 146, 147, 148,
    219, 62, 200, 234, 131, 130, 13, 14, 127, 128, 129, 15, 141, 140, 169, 114,
    106, 113, 105, 117, 118, 119, 120, 122, 123, 100, 109, 121, 124, 112, 115, 116,
    63, 170, 171, 97, 160, 98, 95, 157, 309, 96, 164, 159, 39, 110, 102, 107,
    104, 108, 186, 99, 240, 241, 242, 243, 244, 245, 68, 71, 70, 69, 64, 66,
    220, 65, 29, 31, 30, 67, 41, 53, 49, 50, 43, 42, 51, 52, 44, 45,
    54, 55, 48, 46, 47, 187, 12, 11, 25, 248, 249, 250, 56, 59, 9, 221,
    167, 168, 10, 26, 149, 150, 151, 152, 27, 28, 216, 237, 239, 238, 256, 279,
    297, 298, 288, 299, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, 61, 302, 300, 301, 303, 304, 305, 306, 308, 307, 310, 311,
    312, 313, 314, 315, 316, 317, 318, 319, 321, 322, 323, 324, 325, 326, 327, 328,
    329, 330, 331, 332, 333, 334);

{ O_DIRECTORY/O_NOFOLLOW/O_DIRECT/O_LARGEFILE: arm64's 0x4000/0x8000/
  0x10000/0x20000 are x86-64's 0x10000/0x20000/0x4000/0x8000. The map is its
  own inverse. }
function A64OpenFlags(f: Int64): Int64;
begin
  Result := f and not Int64($3C000);
  if (f and $4000) <> 0 then Result := Result or $10000;
  if (f and $8000) <> 0 then Result := Result or $20000;
  if (f and $10000) <> 0 then Result := Result or $4000;
  if (f and $20000) <> 0 then Result := Result or $8000;
end;

procedure X64StatToA64(x, a: Int64);
var i: Integer;
begin
  PInt64(a)^ := PInt64(x)^;                                 { st_dev }
  PInt64(a + 8)^ := PInt64(x + 8)^;                         { st_ino }
  PInteger(a + 16)^ := PInteger(x + 24)^;                   { st_mode }
  PInteger(a + 20)^ := Integer(PInt64(x + 16)^);            { st_nlink }
  PInteger(a + 24)^ := PInteger(x + 28)^;                   { st_uid }
  PInteger(a + 28)^ := PInteger(x + 32)^;                   { st_gid }
  PInt64(a + 32)^ := PInt64(x + 40)^;                       { st_rdev }
  PInt64(a + 40)^ := 0;
  PInt64(a + 48)^ := PInt64(x + 48)^;                       { st_size }
  PInteger(a + 56)^ := Integer(PInt64(x + 56)^);            { st_blksize }
  PInteger(a + 60)^ := 0;
  for i := 8 to 14 do                                       { st_blocks, the three times }
    PInt64(a + 8 * i)^ := PInt64(x + 8 * i)^;
  PInt64(a + 120)^ := 0;
end;

function LxA64Front(nr, a0, a1, a2, a3, a4, a5: Int64): Int64;
var xs: array[0..17] of Int64;        { x86-64 struct stat, 144 B }
    sa, so: array[0..3] of Int64;     { x86-64 struct sigaction }
    ev: array[0..1] of Int64;         { a packed 12-byte epoll_event }
    x, d, e: Int64;
    i: Integer;
begin
  if (nr >= 0) and (nr <= 293) then x := A64ToX64[Integer(nr)]
  else if nr >= 403 then x := nr
  else x := -1;
  if x < 0 then begin Result := -LX_ENOSYS; Exit; end;
  case Integer(nr) of
    56: Result := LxX64Call(257, a0, a1, A64OpenFlags(a2), a3, 0, 0);   { openat }
    25: if a1 = 4 then                                                  { fcntl F_SETFL }
          Result := LxX64Call(72, a0, 4, A64OpenFlags(a2), 0, 0, 0)
        else
        begin
          Result := LxX64Call(72, a0, a1, a2, 0, 0, 0);
          if (a1 = 3) and (Result >= 0) then Result := A64OpenFlags(Result);   { F_GETFL }
        end;
    79: begin                                                           { newfstatat }
          Result := LxX64Call(262, a0, a1, Int64(@xs[0]), a3, 0, 0);
          if Result = 0 then X64StatToA64(Int64(@xs[0]), a2);
        end;
    80: begin                                                           { fstat }
          Result := LxX64Call(5, a0, Int64(@xs[0]), 0, 0, 0, 0);
          if Result = 0 then X64StatToA64(Int64(@xs[0]), a1);
        end;
    21: if a3 = 0 then Result := LxX64Call(233, a0, a1, a2, 0, 0, 0)  { epoll_ctl }
        else
        begin
          ev[0] := 0; ev[1] := 0;
          PInteger(@ev[0])^ := PInteger(a3)^;
          PInt64(Int64(@ev[0]) + 4)^ := PInt64(a3 + 8)^;
          Result := LxX64Call(233, a0, a1, a2, Int64(@ev[0]), 0, 0);
        end;
    22: begin                                                           { epoll_pwait }
          Result := LxX64Call(281, a0, a1, a2, a3, a4, a5);
          { packed into the caller's own array; widen in place from the
            last entry down, each read before its slot is overwritten }
          i := Integer(Result) - 1;
          while i >= 0 do
          begin
            e := PInteger(a1 + 12 * i)^;
            d := PInt64(a1 + 12 * i + 4)^;
            PInt64(a1 + 16 * i + 8)^ := d;
            PInt64(a1 + 16 * i)^ := e and $FFFFFFFF;
            Dec(i);
          end;
        end;
    134: begin                                                          { rt_sigaction }
          if a1 <> 0 then
          begin
            sa[0] := PInt64(a1)^; sa[1] := PInt64(a1 + 8)^;
            sa[2] := 0; sa[3] := PInt64(a1 + 16)^;
          end;
          so[0] := 0; so[1] := 0; so[2] := 0; so[3] := 0;
          if a1 <> 0 then d := Int64(@sa[0]) else d := 0;
          if a2 <> 0 then e := Int64(@so[0]) else e := 0;
          Result := LxX64Call(13, a0, d, e, a3, 0, 0);
          if (Result = 0) and (a2 <> 0) then
          begin
            PInt64(a2)^ := so[0]; PInt64(a2 + 8)^ := so[1]; PInt64(a2 + 16)^ := so[3];
          end;
        end;
    220: if ((a0 and not Int64($FF)) = 0) and (a1 = 0) then            { clone(SIGCHLD): fork }
           Result := LxX64Call(57, 0, 0, 0, 0, 0, 0)
         else                                     { arm64 passes tls before ctid; a5 rides along }
           Result := LxX64Call(56, a0, a1, a2, a4, a3, a5);
  else
    Result := LxX64Call(x, a0, a1, a2, a3, a4, a5);
  end;
end;
