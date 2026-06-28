#ifdef USE_SYSTEM_SQLITE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>
#else
#define SQLITE_THREADSAFE 0
#define SQLITE_OMIT_LOAD_EXTENSION 1
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "locale.c"
#include "sqlite3.c"
#endif

// Callback for sqlite3_exec
int exec_callback(void *NotUsed, int argc, char **argv, char **azColName) {
  for (int i = 0; i < argc; i++) {
    printf("%s = %s\n", azColName[i], argv[i] ? argv[i] : "NULL");
  }
  printf("----------\n");
  return 0;
}

int main(void) {
  sqlite3 *db = 0;
  char *errmsg = 0;
  int rc;

  rc = sqlite3_open(":memory:", &db);
  if (rc != SQLITE_OK) {
    printf("Failed to open DB: %d\n", rc);
    return 1;
  }
  printf("DB opened successfully\n");

  // 1. Create table and index
  rc = sqlite3_exec(db, 
    "CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT, age INTEGER, balance REAL);"
    "CREATE INDEX idx_users_name ON users(name);", 
    0, 0, &errmsg);
  if (rc != SQLITE_OK) {
    printf("Create error: %s\n", errmsg);
    sqlite3_free(errmsg);
    return 2;
  }
  printf("Table and index created\n");

  // 2. Insert values using exec
  rc = sqlite3_exec(db, 
    "INSERT INTO users VALUES(1, 'Alice', 30, 1500.50);"
    "INSERT INTO users VALUES(2, 'Bob', 25, 2000.00);", 
    0, 0, &errmsg);
  if (rc != SQLITE_OK) {
    printf("Insert error: %s\n", errmsg);
    sqlite3_free(errmsg);
    return 3;
  }
  printf("Initial inserts done\n");

  // 3. Insert values using prepared statements (testing binds)
  sqlite3_stmt *stmt = 0;
  rc = sqlite3_prepare_v2(db, "INSERT INTO users VALUES(?, ?, ?, ?);", -1, &stmt, 0);
  if (rc != SQLITE_OK) {
    printf("Prepare error: %d\n", rc);
    return 4;
  }

  // Row 3: Charlie, NULL age, 0.00 balance
  sqlite3_bind_int(stmt, 1, 3);
  sqlite3_bind_text(stmt, 2, "Charlie", -1, SQLITE_STATIC);
  sqlite3_bind_null(stmt, 3);
  sqlite3_bind_double(stmt, 4, 0.00);
  rc = sqlite3_step(stmt);
  if (rc != SQLITE_DONE) {
    printf("Step 3 error: %d\n", rc);
  }
  sqlite3_reset(stmt);

  // Row 4: David, 40 age, NULL balance
  sqlite3_bind_int(stmt, 1, 4);
  sqlite3_bind_text(stmt, 2, "David", -1, SQLITE_STATIC);
  sqlite3_bind_int(stmt, 3, 40);
  sqlite3_bind_null(stmt, 4);
  rc = sqlite3_step(stmt);
  if (rc != SQLITE_DONE) {
    printf("Step 4 error: %d\n", rc);
  }
  sqlite3_finalize(stmt);
  printf("Prepared statement inserts done\n");

  // 4. Select and print all using exec
  printf("=== Users list ===\n");
  rc = sqlite3_exec(db, "SELECT * FROM users ORDER BY id ASC;", exec_callback, 0, &errmsg);
  if (rc != SQLITE_OK) {
    printf("Select error: %s\n", errmsg);
    sqlite3_free(errmsg);
  }

  // 5. Run a transaction with updates and deletes
  rc = sqlite3_exec(db, "BEGIN TRANSACTION;", 0, 0, 0);
  rc = sqlite3_exec(db, "UPDATE users SET balance = balance + 500.25 WHERE id = 1;", 0, 0, 0);
  rc = sqlite3_exec(db, "DELETE FROM users WHERE id = 2;", 0, 0, 0);
  rc = sqlite3_exec(db, "COMMIT;", 0, 0, 0);
  printf("Transaction completed\n");

  // 6. Select again to verify changes
  printf("=== Users list after transaction ===\n");
  rc = sqlite3_exec(db, "SELECT * FROM users ORDER BY id ASC;", exec_callback, 0, &errmsg);
  if (rc != SQLITE_OK) {
    printf("Select error: %s\n", errmsg);
    sqlite3_free(errmsg);
  }

  // 7. Test aggregate queries using prepared statement
  printf("=== Aggregates ===\n");
  rc = sqlite3_prepare_v2(db, "SELECT COUNT(*), SUM(balance), AVG(age) FROM users;", -1, &stmt, 0);
  if (rc == SQLITE_OK) {
    if (sqlite3_step(stmt) == SQLITE_ROW) {
      int count = sqlite3_column_int(stmt, 0);
      double sum = sqlite3_column_double(stmt, 1);
      double avg_age = sqlite3_column_double(stmt, 2);
      printf("Count: %d\n", count);
      printf("Sum of balance: %.2f\n", sum);
      printf("Average age: %.2f\n", avg_age);
    }
    sqlite3_finalize(stmt);
  } else {
    printf("Aggregate prepare error: %d\n", rc);
  }

  sqlite3_close(db);
  printf("DB closed successfully\n");
  return 0;
}
