/* SPDX-License-Identifier: Zlib */
/* TWO CONFLICTING TYPEDEFS FOR ONE NAME. C11 6.7p3 permits a repeated typedef
 * only when it names the SAME type; these do not, and gcc rejects it:
 *
 *     error: conflicting types for 'T'; have 'long int'
 *
 * pxx used to accept this silently and let the LAST one win.
 *
 * IT MUST BE REFUSED ON A 64-BIT TARGET TOO, and that is the whole difficulty.
 * TTypeKind collapses `long` and `long long` onto tyInt64 wherever a pointer is
 * eight bytes, so a check that compared only the resolved kind would refuse
 * this on i386 and accept it here — passing exactly where everyone tests, which
 * is the failure mode the ticket is about. The typedef row therefore carries a
 * long RANK beside the kind, the same distinction SymCLongRank already keeps
 * for _Generic.
 *
 * WHAT THE SILENCE COST, and it is why this is a refusal rather than a warning:
 * <time.h> declared `typedef long long time_t` with a comment promising 64-bit
 * on every target so Y2038 never appears, while <sys/types.h> had
 * `typedef __time_t time_t` with __time_t == long. Including <time.h>
 * auto-pulls crtl/src/time.c, which reaches <sys/types.h>, so `long` arrived
 * last and won. The damage was not the width — it was that the width became a
 * function of what ELSE the translation unit happened to pull in. On i386 one
 * TU gave two answers for one type: sizeof(time_t)=4 while a static time_t was
 * laid out at 8.
 *
 * bug-c-the-frontend-takes-the-last-of-two-conflicting-typedefs-silently
 */
typedef long long T;
typedef long T;
int main(void){ return (int)sizeof(T); }
