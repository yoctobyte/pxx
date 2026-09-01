/* C99 5.2.4.1 requires an implementation to accept at least 127 arguments in a
   macro invocation. pxx's preprocessor reserved SIXTEEN argument slots per
   expansion level -- a stride constant, not the array size -- and past that the
   comma simply stopped being a separator: the remaining arguments fused into
   the last one and the expansion came out malformed, with no diagnostic.

   busybox's coreutils/factor.c is the file that found it. Its packed_wheel
   table calls a 20-argument macro P from inside another 20-argument macro R,
   and the compiler NEVER RETURNED -- an 8-minute hang with no output. The
   simpler shape below reported `stray token at top level: G' instead, which is
   the same defect landing somewhere a reader would never look.

   ROW 3 IS THE ORIGINAL, values checked against gcc. The others bracket the old
   limit (16 passed before, 17 did not) and reach the standard's 127.
   bug-c-a-macro-call-with-more-than-16-arguments-is-silently-mis-expanded */
#include <stdio.h>
#include <stdint.h>

#define S16(a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p) (a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p)
#define S17(a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q) \
        (a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p+q)

/* busybox's own shape: a wide macro whose arguments are themselves the
   arguments of another wide macro. */
#define R(a,b,c,d,e,f,g,h,i,j,A,B,C,D,E,F,G,H,I,J) \
	(((uint64_t)(a<<0) | (b<<3) | (c<<6) | (d<<9) | (e<<12) | (f<<15) | (g<<18) | (h<<21) | (i<<24) | (j<<27)) << 1) | \
	(((uint64_t)(A<<0) | (B<<3) | (C<<6) | (D<<9) | (E<<12) | (F<<15) | (G<<18) | (H<<21) | (I<<24) | (J<<27)) << 31)
#define P(a,b,c,d,e,f,g,h,i,j,A,B,C,D,E,F,G,H,I,J) \
	R(	(a/2),(b/2),(c/2),(d/2),(e/2),(f/2),(g/2),(h/2),(i/2),(j/2), \
		(A/2),(B/2),(C/2),(D/2),(E/2),(F/2),(G/2),(H/2),(I/2),(J/2)  )

static const uint64_t packed_wheel[] = {
	P( 4, 2, 4, 6, 2, 6, 4, 2, 4, 6, 6, 2, 6, 4, 2, 6, 4, 6, 8, 4),
	P( 2, 4, 2, 4,14, 4, 6, 2,10, 2, 6, 6, 4, 2, 4, 6, 2,10, 2, 4),
};

/* The standard's own floor, and the argument list is the point of the row. */
#define A127(p0,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11,p12,p13,p14,p15,p16,p17,p18,p19,\
             p20,p21,p22,p23,p24,p25,p26,p27,p28,p29,p30,p31,p32,p33,p34,p35,p36,p37,p38,p39,\
             p40,p41,p42,p43,p44,p45,p46,p47,p48,p49,p50,p51,p52,p53,p54,p55,p56,p57,p58,p59,\
             p60,p61,p62,p63,p64,p65,p66,p67,p68,p69,p70,p71,p72,p73,p74,p75,p76,p77,p78,p79,\
             p80,p81,p82,p83,p84,p85,p86,p87,p88,p89,p90,p91,p92,p93,p94,p95,p96,p97,p98,p99,\
             p100,p101,p102,p103,p104,p105,p106,p107,p108,p109,p110,p111,p112,p113,p114,p115,\
             p116,p117,p118,p119,p120,p121,p122,p123,p124,p125,p126) (p0+p63+p126)

int main(void) {
  printf("1 %d\n", S16(1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16));
  printf("2 %d\n", S17(1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17));
  printf("3 %llu %llu\n", (unsigned long long)packed_wheel[0],
                          (unsigned long long)packed_wheel[1]);
  printf("4 %d\n", A127(1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
                        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
                        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
                        1,1,1,7,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
                        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
                        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
                        1,1,1,1,1,1,1,1,1,1,9));
  return 0;
}
