/* Global union initializer materialised via PendingInit (constant, written to the
   first member at offset 0) — lua lstrlib `static const union {int dummy; char
   little;} nativeendian = {1}` read as `.little` for endianness. Exit 42. */
union { int dummy; char bytes[4]; } ne = {1};
union { int v; } single = {42};
int main(void) {
  /* little-endian host: low byte of dummy==1 */
  return (ne.bytes[0] == 1) ? single.v : 0;   /* 42 */
}
