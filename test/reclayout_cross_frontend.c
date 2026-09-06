/* One of THREE spellings of the same two aggregates, compiled by pxx's C,
   Pascal and NilPy frontends and compared against each other by
   test-record-layout-cross-frontend.

   The comparison is a RELATION and never a constant: the byte DISTANCE from the
   first member to the second must be the same in all three, whatever the target
   makes it. So this file carries no expected width, is correct on every target,
   and prints a different correct number on each.

   Distances rather than offsets, because a NilPy instance carries an 8-byte
   header in front of its first field and a C struct does not. Comparing raw
   offsets would report a difference that is not a disagreement.

   WHY THE MEMBERS ARE 1 BYTE THEN 8. A 4-byte-then-8 shape does NOT
   discriminate for NilPy -- every NilPy integer is a 64-bit type, so the second
   member lands at the same place under both the member rule and the storage
   rule, and the row would pass while measuring nothing. The four shapes
   test/record_abi_mixed_link_pxx.c uses are all of that kind. A one-byte first
   member is what separates them: member alignment puts the double at +4 on
   i386, storage alignment at +8.
   bug-a-pascal-nilpy-rust-and-zig-over-align-an-8-byte-member-on-i386 */
struct BOOLD { char b; double y; };
struct BYTEQ { char c; long long q; };

int main(void)
{
  struct BOOLD u;
  struct BYTEQ v;
  u.b = 1; u.y = 2.0;
  v.c = 3; v.q = 4;
  return (int)(u.b + v.c);
}
