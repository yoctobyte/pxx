{ Companion unit for test_p_a_conditional_directive_can_read_a_source_const.
  It declares nothing but a few constants and a two-hop type alias chain, and
  it exists so the CROSS-UNIT rows in that file are answered by the probe that
  lexes a used unit, not by the in-file walk. }
unit condsrc_unit;

interface

const
  UCONST = 8;
  UNEG   = -3;
  UHEX   = $20;

type
  TUAlias1 = qword;       { one hop to a builtin }
  TUAlias2 = TUAlias1;    { two hops }

implementation

end.
