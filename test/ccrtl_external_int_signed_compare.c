/* Guard: bug-c-crtl-pulled-fn-inline-signed-compare.
   An EXTERNAL crtl int function (getaddrinfo returns -2 = EAI_NONAME) used
   directly in a signed `>= 0` compare must read as negative. Before the fix the
   32-bit return left RAX's upper half undefined, so the value model's 64-bit
   signed compare saw a large positive and took the branch. Exits 42 on success. */
#include <sys/socket.h>
#include <netdb.h>

int main(void)
{
    struct addrinfo *ai = 0;
    /* inline: the failing form */
    if (getaddrinfo("nonexistent.invalid", "80", 0, &ai) >= 0)
        return 1;                 /* BUG: -2 read as positive */
    /* stored-to-int: always worked (the load sign-extends) — sanity check */
    int rc = getaddrinfo("nonexistent.invalid", "80", 0, &ai);
    if (rc >= 0)
        return 2;
    return 42;
}
