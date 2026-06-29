/* Test C header for packed and aligned attributes */

/* A normal struct: laid out normally as a record */
typedef struct {
  char a;
  int b;
} NormalStruct;

/* A packed struct: field b is byte-adjacent to a, size is 5 */
typedef struct __attribute__((packed)) {
  char a;
  int b;
} PackedStruct;

/* A field-aligned struct: b moves to offset 8, total size rounds to 16 */
typedef struct {
  char a;
  int b __attribute__((aligned(8)));
} AlignedStruct;

/* A type-aligned struct: natural field offsets, type size rounds to 16 */
typedef struct __attribute__((aligned(16))) {
  char a;
  int b;
} TypeAlignedStruct;
