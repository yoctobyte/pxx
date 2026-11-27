/* crtl: getifaddrs lists an interface by its link (AF_PACKET), not only by an
   IPv4 address; open_memstream has a position (ftell, rewind, fseek).
   bug-c-crtl-getifaddrs-misses-an-interface-without-an-address,
   bug-c-crtl-open-memstream-has-no-position. Expected output is glibc's. */
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <netpacket/packet.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <string.h>

int main(void) {
  struct ifaddrs *a, *p;
  int lo_link = 0, lo_v4 = 0;
  char *b = 0;
  size_t n = 0;
  FILE *f;
  int round;

  if (getifaddrs(&a) != 0) { perror("getifaddrs"); return 1; }
  for (p = a; p; p = p->ifa_next) {
    if (strcmp(p->ifa_name, "lo") != 0 || !p->ifa_addr) continue;
    if (p->ifa_addr->sa_family == AF_PACKET) {
      struct sockaddr_ll *l = (struct sockaddr_ll *)p->ifa_addr;
      lo_link = l->sll_ifindex > 0 && (p->ifa_flags & IFF_LOOPBACK) && p->ifa_data != 0;
    } else if (p->ifa_addr->sa_family == AF_INET && p->ifa_netmask) {
      char x[32], m[32];
      inet_ntop(AF_INET, &((struct sockaddr_in *)p->ifa_addr)->sin_addr, x, sizeof x);
      inet_ntop(AF_INET, &((struct sockaddr_in *)p->ifa_netmask)->sin_addr, m, sizeof m);
      lo_v4 = strcmp(x, "127.0.0.1") == 0 && strcmp(m, "255.0.0.0") == 0;
    }
  }
  freeifaddrs(a);
  printf("lo link entry %d, lo 127.0.0.1/255.0.0.0 %d\n", lo_link, lo_v4);

  f = open_memstream(&b, &n);
  if (!f) { perror("open_memstream"); return 1; }
  for (round = 0; round < 3; round++) {
    if (round) rewind(f);
    fprintf(f, "PATH=%s", round ? "/bin" : "/usr/bin:/bin");
    fputc('\0', f);
    fprintf(f, "pid=%d", 42 + round);
    fputc('\0', f);
    fflush(f);
    printf("round %d: ftell %ld size %zu [%s|%s]\n", round, ftell(f), n, b, b + strlen(b) + 1);
  }
  fseek(f, 4, SEEK_SET);
  fputs("XY", f);
  fflush(f);
  printf("fseek 4: ftell %ld size %zu [%.4s|%.2s]\n", ftell(f), n, b, b + 4);
  fseek(f, 0, SEEK_END);
  printf("SEEK_END: ftell %ld\n", ftell(f));
  fseek(f, 3, SEEK_CUR);
  fputc('Z', f);
  fflush(f);
  printf("past the end: ftell %ld size %zu gap %d %d %d last %c\n", ftell(f), n, b[17], b[18], b[19], b[20]);
  fclose(f);
  printf("closed: size %zu\n", n);
  return 0;
}
