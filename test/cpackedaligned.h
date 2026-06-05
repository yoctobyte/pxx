/* Test C header for packed and aligned attributes */

/* A normal struct: laid out normally as a record */
typedef struct {
  char a;
  int b;
} NormalStruct;

/* A packed struct: falls back to opaque */
typedef struct __attribute__((packed)) {
  char a;
  int b;
} PackedStruct;

/* An aligned struct: falls back to opaque */
typedef struct {
  char a;
  int b __attribute__((aligned(8)));
} AlignedStruct;
