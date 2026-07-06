/* Broad SQLite feature battery — self-contained, libc-free. Runs an embedded
 * SQL script through sqlite3_exec and prints each result row as pipe-separated
 * columns (NULL = empty), matching `sqlite3 .mode list`, for diff vs the system
 * sqlite3 oracle. Covers aggregates/GROUP BY/HAVING, joins, subqueries,
 * correlated subqueries, recursive CTEs, window functions, CASE, string/math
 * funcs, views, triggers, UPSERT, transactions+rollback, GROUP_CONCAT,
 * PRAGMA integrity_check. */
#define SQLITE_THREADSAFE 0
#define SQLITE_OMIT_LOAD_EXTENSION 1
#include <stdio.h>
#include "sqlite3.h"
#include "sqlite3.c"
static int cb(void*u,int n,char**v,char**c){
  int i;
  for(i=0;i<n;i++){ if(i) printf("|"); printf("%s", v[i]?v[i]:""); }
  printf("\n");
  return 0;
}
static const char *SCRIPT =
"CREATE TABLE emp(id INTEGER PRIMARY KEY, name TEXT, dept TEXT, sal REAL, mgr INTEGER);\n"
"INSERT INTO emp VALUES(1,'Alice','Eng',100.5,NULL),(2,'Bob','Eng',90.0,1),(3,'Carol','Sales',80.25,1),(4,'Dave','Sales',70.0,3),(5,'Eve','Eng',120.0,1),(6,'Frank','Ops',60.5,NULL);\n"
"CREATE INDEX idx_dept ON emp(dept);\n"
"-- aggregates + group by + having\n"
"SELECT dept, COUNT(*), CAST(ROUND(AVG(sal),2) AS TEXT), MIN(sal), MAX(sal), SUM(sal) FROM emp GROUP BY dept HAVING COUNT(*)>1 ORDER BY dept;\n"
"-- join (self join manager)\n"
"SELECT e.name, m.name FROM emp e JOIN emp m ON e.mgr=m.id ORDER BY e.id;\n"
"-- left join with nulls\n"
"SELECT e.name, m.name FROM emp e LEFT JOIN emp m ON e.mgr=m.id ORDER BY e.id;\n"
"-- subquery + IN\n"
"SELECT name FROM emp WHERE dept IN (SELECT dept FROM emp GROUP BY dept HAVING SUM(sal)>150) ORDER BY name;\n"
"-- correlated subquery\n"
"SELECT name, (SELECT COUNT(*) FROM emp x WHERE x.mgr=emp.id) AS reports FROM emp ORDER BY id;\n"
"-- CTE recursive (factorials 1..6)\n"
"WITH RECURSIVE c(n,f) AS (SELECT 1,1 UNION ALL SELECT n+1,f*(n+1) FROM c WHERE n<6) SELECT n,f FROM c;\n"
"-- window functions\n"
"SELECT name, dept, sal, RANK() OVER (PARTITION BY dept ORDER BY sal DESC), SUM(sal) OVER (PARTITION BY dept) FROM emp ORDER BY dept, sal DESC;\n"
"-- CASE + string funcs\n"
"SELECT name, UPPER(name), LENGTH(name), SUBSTR(name,1,2), CASE WHEN sal>=100 THEN 'high' WHEN sal>=75 THEN 'mid' ELSE 'low' END FROM emp ORDER BY id;\n"
"-- math + type\n"
"SELECT ABS(-5), 17%5, 2*3+1, 7/2, 7.0/2, ROUND(3.14159,2), TYPEOF(1), TYPEOF(1.5), TYPEOF('x'), TYPEOF(NULL);\n"
"-- distinct + order + limit\n"
"SELECT DISTINCT dept FROM emp ORDER BY dept DESC LIMIT 2;\n"
"-- view\n"
"CREATE VIEW eng AS SELECT name, sal FROM emp WHERE dept='Eng';\n"
"SELECT name FROM eng ORDER BY sal DESC;\n"
"-- trigger\n"
"CREATE TABLE audit(msg TEXT);\n"
"CREATE TRIGGER trg AFTER INSERT ON emp BEGIN INSERT INTO audit VALUES('added '||NEW.name); END;\n"
"INSERT INTO emp VALUES(7,'Grace','Ops',65.0,6);\n"
"SELECT msg FROM audit;\n"
"-- upsert\n"
"INSERT INTO emp(id,name,dept,sal,mgr) VALUES(7,'Grace2','Ops',66.0,6) ON CONFLICT(id) DO UPDATE SET sal=sal+1;\n"
"SELECT name,sal FROM emp WHERE id=7;\n"
"-- transaction rollback\n"
"BEGIN; UPDATE emp SET sal=0; ROLLBACK;\n"
"SELECT COUNT(*) FROM emp WHERE sal=0;\n"
"-- string agg + coalesce\n"
"SELECT dept, GROUP_CONCAT(name,',') FROM emp GROUP BY dept ORDER BY dept;\n"
"SELECT COALESCE(mgr,-1) FROM emp ORDER BY id;\n"
"-- integrity\n"
"PRAGMA integrity_check;\n"
"";
int main(void){
  sqlite3 *db; char *e=0;
  if(sqlite3_open(":memory:",&db)){ printf("OPEN FAIL\n"); return 1; }
  int rc = sqlite3_exec(db, SCRIPT, cb, 0, &e);
  if(rc){ printf("EXEC FAIL rc=%d %s\n", rc, e?e:"?"); return 1; }
  sqlite3_close(db);
  return 0;
}
