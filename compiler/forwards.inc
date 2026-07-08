{ SPDX-License-Identifier: MPL-2.0 }
{ FPC-seed / strict-mode forward declarations.

  FPC compiles single-pass: a call resolves only if a routine header sits ABOVE
  it in the linear (post-{$include}) text. PXX prescans every top-level header
  first, so it never needs these. This file supplies the forwards FPC (and PXX in
  --require-forward mode) requires for helpers whose bodies live in a later .inc.

  Included from compiler.pas only when PXX_NEED_FORWARDS is set (FPC defined, or
  PXX_REQUIRE_FORWARD). Signatures MUST stay byte-identical to the bodies.
  See devdocs/progress/backlog/bug-fpc-seed-helper-ordering-after-lua-c-frontend.md }

function TypeSize(tk: TTypeKind): Integer; forward;
function GenMakeSeq(stmt, next: Integer): Integer; forward;
function CNodeDecaysToPointer(node: Integer): Boolean; forward;
function IRLowerAddress(node: Integer): Integer; forward;
function IRNodePointerBase(node: Integer): Boolean; forward;
function IRPointerStride(node: Integer): Integer; forward;
