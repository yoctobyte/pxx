/* definition half of c_static_proto_in_header.c: a .c file #included by another
   .c, defining a static function whose prototype the includer read from a
   header. bug-c-a-static-defined-in-an-included-c-file-is-never-emitted */
static int sph_times6(int x) { return x * 6; }
