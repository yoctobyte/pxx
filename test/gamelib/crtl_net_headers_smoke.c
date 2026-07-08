/* crtl networking-header surface smoke (bug-c-crtl-missing-net-headers-enet):
   netinet/tcp.h, netdb.h, poll.h, and sys/socket.h's msghdr/iovec/sendmsg/
   recvmsg must exist so C candidates (ENet) compile against crtl instead of
   leaking host headers. Exercises the declarations + the numeric-only /
   not-found impls (no live socket). Exit 42. */
#include <sys/socket.h>
#include <netinet/tcp.h>
#include <netinet/in.h>
#include <netdb.h>
#include <poll.h>
#include <string.h>

int main(void) {
    /* struct + macro surface resolves */
    if (TCP_NODELAY != 1) return 1;
    if (IPPROTO_TCP != 6) return 2;

    struct msghdr m; memset(&m, 0, sizeof m);
    struct iovec iv[2];
    char a[] = "hi", b[] = "!";
    iv[0].iov_base = a; iv[0].iov_len = 2;
    iv[1].iov_base = b; iv[1].iov_len = 1;
    m.msg_iov = iv; m.msg_iovlen = 2;
    if (m.msg_iovlen != 2 || m.msg_iov[1].iov_len != 1) return 3;

    struct pollfd pf; pf.fd = 0; pf.events = POLLIN; pf.revents = 0;
    (void)poll(&pf, 1, 0);              /* stub: no PAL readiness yet */

    /* no resolver: hostname lookups report not-found (negative), numeric paths
       use inet_* directly. */
    if (gethostbyname("nohost") != 0) return 4;
    struct addrinfo *ai = 0;
    int grc = getaddrinfo("h", "80", 0, &ai);
    if (grc >= 0) return 5;              /* no resolver: not-found = negative */
    freeaddrinfo(ai);

    return 42;
}
