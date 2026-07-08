/* b202: a struct-tag REDEFINITION (as when a host header leaks in and redefines
   a crtl-defined struct) must not re-lay the populated record and misfile a
   following struct's member into it — that produced a self-referential record
   that hung RecordHasManagedFields and SIGSEGV'd the compiler
   (bug-c-tag-redef-misfiles-field-selfref-segv, found via the ENet candidate).
   The first definition is kept; the duplicate body is skipped. */

struct in_addr { unsigned int s_addr; };
struct in_addr { unsigned int s_addr; };          /* redefinition */
struct ip_opts { struct in_addr ip_dst; char pad[40]; };

int main(void) {
    struct ip_opts x;
    x.ip_dst.s_addr = 5;
    x.pad[0] = 'A';
    if (x.ip_dst.s_addr != 5) return 1;
    if (x.pad[0] != 'A') return 2;
    if (sizeof(struct in_addr) != 4) return 3;
    return 42;
}
