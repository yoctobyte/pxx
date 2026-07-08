/* crtl IPv4 textual-conversion smoke (game-library ladder: the arpa/inet.h
   surface ENet needs). Deterministic, exit 42. inet_* return int/pointer, so
   they are unaffected by the float-return ABI gap
   (bug-c-float-single-return-zero). */
#include <arpa/inet.h>
#include <string.h>

int printf(const char *, ...);

int main(void) {
    struct in_addr a, b;
    char buf[16];
    if (!inet_aton("192.168.1.42", &a)) return 1;
    if (inet_ntop(2 /*AF_INET*/, &a, buf, sizeof(buf)) == 0) return 2;
    if (strcmp(buf, "192.168.1.42")) { printf("GOT %s\n", buf); return 3; }
    if (inet_aton("999.0.0.1", &a)) return 4;        /* octet > 255 rejected */
    if (inet_aton("1.2.3.x", &a)) return 5;          /* trailing garbage rejected */
    inet_pton(2, "8.8.8.8", &b);
    if (inet_ntop(2, &b, buf, sizeof(buf)) == 0 || strcmp(buf, "8.8.8.8")) return 6;
    if (inet_addr("255.255.255.255") != 0xFFFFFFFFU) return 7;
    return 42;
}
