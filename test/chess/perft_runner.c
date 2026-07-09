/* pxx chess perft runner (used by `make test-chess-perft`, NOT the base gate).
 *
 * Unity build: amalgamates crtl + the VICE engine's perft-relevant translation
 * units from library_candidates/chess (gitignored 3rd-party scratch), then runs
 * legal-move perft over the canonical test positions. The oracle is NOT gcc: the
 * perft counts (chessprogramming.org, startpos + Kiwipete + positions 3-6) are
 * COMPILER-INDEPENDENT known-answer values baked in below — the numbers ARE
 * truth. A wrong count is a pxx miscompile (movegen / 64-bit bitboard mask /
 * bit-shift / deep recursion / array-of-struct movelist), never the engine.
 *
 * Stays out of `make test` so the base gate carries no 3rd-party dependency;
 * the Makefile target skips gracefully when the tree is absent.
 *
 * crtl units first (so the engine sources see our libc-free headers/impls),
 * then the VICE translation units, then perft.c, then the driver. */
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"

/* VICE engine — perft path only. We omit uci.c / search.c / vice.c /
 * evaluate.c / pvtable.c / tinycthread.c (search + threads, not needed).
 * validate.c carries the on-board predicates board.c needs (SqOnBoard, …) plus
 * DEBUG-only helpers that reference the search/eval engine; those three symbols
 * are stubbed below and never called on the perft path. */
#include "data.c"
#include "init.c"
#include "bitboards.c"
#include "hashkeys.c"
#include "board.c"
#include "attack.c"
#include "movegen.c"
#include "makemove.c"
#include "io.c"
#include "misc.c"
#include "polykeys.c"
#include "polybook.c"
#include "validate.c"
#include "perft.c"

/* Stubs for validate.c's DEBUG-helper references into the un-linked search/eval
 * engine. Never reached on the perft path. */
void SearchPosition(S_BOARD *pos, S_SEARCHINFO *info, S_HASHTABLE *table) {
    (void)pos; (void)info; (void)table;
}
int EvalPosition(const S_BOARD *pos) { (void)pos; return 0; }
void ClearHashTable(S_HASHTABLE *table) { (void)table; }

static long perft_count(int depth, S_BOARD *pos) {
    leafNodes = 0;
    Perft(depth, pos);
    return leafNodes;
}

typedef struct {
    const char *name;
    char *fen;
    int ndepth;              /* number of expected entries (perft 1..ndepth) */
    long expect[6];
} TC;

int main(void) {
    /* Only the inits the perft path needs (board geometry + Zobrist keys).
     * Skips InitEvalMasks/InitMvvLva (search/eval) and InitPolyBook (opening
     * book file I/O, which prints "Book File Not Read"). */
    InitSq120To64();
    InitBitMasks();
    InitHashKeys();
    InitFilesRanksBrd();
    static S_BOARD pos[1];

    /* Depth budget: default gate is perft(1..DEPTH). DEPTH=4 keeps the run to a
     * few seconds; build with -DPERFT_DEEP=5 for the heavy depth-5 sweep
     * (startpos(5)=4.8M, kiwipete(5)=194M, ~tens of seconds). */
#ifdef PERFT_DEEP
    int cap = PERFT_DEEP;
#else
    int cap = 4;
#endif

    static TC cases[] = {
      { "startpos", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        5, { 20, 400, 8902, 197281, 4865609, 0 } },
      { "kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0",
        5, { 48, 2039, 97862, 4085603, 193690690, 0 } },
      { "position3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0",
        5, { 14, 191, 2812, 43238, 674624, 0 } },
      { "position4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0",
        5, { 6, 264, 9467, 422333, 15833292, 0 } },
      { "position5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 0",
        5, { 44, 1486, 62379, 2103487, 89941194, 0 } },
      { "position6", "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0",
        5, { 46, 2079, 89890, 3894594, 164075551, 0 } },
    };

    int ncases = (int)(sizeof(cases) / sizeof(cases[0]));
    int fails = 0;
    int i, d;
    for (i = 0; i < ncases; ++i) {
        int nd = cases[i].ndepth < cap ? cases[i].ndepth : cap;
        ParseFen(cases[i].fen, pos);
        for (d = 1; d <= nd; ++d) {
            long got = perft_count(d, pos);
            long want = cases[i].expect[d - 1];
            const char *tag = (got == want) ? "ok" : "FAIL";
            printf("%s perft%d %ld %s\n", cases[i].name, d, got, tag);
            if (got != want) {
                printf("  expected %ld got %ld\n", want, got);
                ++fails;
            }
        }
    }
    printf("%s\n", fails == 0 ? "ALL OK" : "MISMATCH");
    return fails == 0 ? 42 : 1;
}
