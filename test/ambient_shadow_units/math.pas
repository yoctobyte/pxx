{ SPDX-License-Identifier: MPL-2.0 }
unit math;
{ The second impostor. `math` is injected by pasparser_prog.inc when the token
  stream contains sqrt/exp/ln/sin/cos/arctan followed by '(' — so prog.pas pulls
  it without ever writing `uses math`, and `math.pas` is a far more likely
  filename to find beside somebody's program than `builtinheap.pas` is.
  If this one is loaded, Sqrt is unresolved. }
interface
implementation
end.
