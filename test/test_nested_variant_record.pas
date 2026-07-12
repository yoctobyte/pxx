program test_nested_variant_record;
type
  sa_family_t = word;
  TInAddr = packed record
    s_addr: longword;
  end;
  TInAddr6 = packed record
    u6_addr8: array[0..15] of byte;
  end;
const
  AF_INET = 2;
  AF_INET6 = 10;
type
  TVarSin = packed record
    case integer of
      0: (AddressFamily: sa_family_t);
      1: (
        case sin_family: sa_family_t of
          AF_INET:  (sin_port: word;
                     sin_addr: TInAddr;
                     sin_zero: array[0..7] of byte);
          AF_INET6: (sin6_port: word;
                     sin6_flowinfo: longword;
                     sin6_addr: TInAddr6;
                     sin6_scope_id: longword);
          );
  end;
var
  v: TVarSin;
begin
  writeln(SizeOf(TVarSin));
  v.sin_family := AF_INET;
  writeln(v.AddressFamily);
  v.sin_port := 8080;
  writeln(v.sin6_port);
  v.sin_addr.s_addr := $AABBCCDD;
  writeln(v.sin6_flowinfo = $AABBCCDD);
  v.sin_zero[0] := 7;
  writeln(v.sin6_addr.u6_addr8[0]);
end.
