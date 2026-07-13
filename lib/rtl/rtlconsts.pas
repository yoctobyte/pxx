{ SPDX-License-Identifier: Zlib }
unit rtlconsts;
{ FPC-compat: the message-string constants FPC keeps in RtlConsts. Plain string
  consts here (FPC uses resourcestring; this RTL has no resource tables, and
  nothing in the corpus rebinds them at runtime). Texts match FPC's
  rtl/objpas/rtlconst.inc verbatim so error-message oracles line up. Grown on
  demand — rtl-generics pulls SSortedListError; add more as corpora ask. }

interface

const
  SArgumentOutOfRange     = 'Argument out of range';
  SAssignError            = 'Cannot assign a %s to a %s.';
  SDuplicateItem          = 'Duplicates not allowed in this list ($0%x)';
  SErrFindNeedsSortedList = 'Cannot use find on unsorted list';
  SIndexOutOfRange        = 'Grid index out of range';
  SInvalidName            = 'Invalid component name: "%s"';
  SListCapacityError      = 'List capacity (%d) exceeded.';
  SListCountError         = 'List count (%d) out of bounds.';
  SListIndexError         = 'List index (%d) out of bounds';
  SListItemSizeError      = 'Incompatible item size in source list';
  SMapKeyError            = 'Map key (address $%x) does not exist';
  SReadOnlyProperty       = 'Property is read-only';
  SSortedListError        = 'Operation not allowed on sorted list';

implementation

end.
