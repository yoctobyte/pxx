-- 200,000 rows into a file database: B-tree splits, overflow pages, indexes,
-- sorting larger than the cache, VACUUM. The database file is compared byte
-- for byte afterwards, and each build reads the other's.
PRAGMA page_size = 4096;
PRAGMA cache_size = 200;
CREATE TABLE big(id INTEGER PRIMARY KEY, k INTEGER, s TEXT, r REAL, b BLOB);
WITH RECURSIVE g(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM g WHERE i < 200000)
INSERT INTO big SELECT i, (i * 2654435761) % 1000003, printf('row-%08d-%s', i, substr('abcdefghij', 1 + i % 10)),
                       i / 7.0, CASE WHEN i % 997 = 0 THEN zeroblob(5000 + i % 3000) ELSE x'abcd' END FROM g;
CREATE INDEX big_k ON big(k);
CREATE INDEX big_s ON big(s DESC);
SELECT count(*), sum(k), min(s), max(s), printf('%.6f', sum(r)), sum(length(b)) FROM big;
SELECT k, count(*) FROM big GROUP BY k HAVING count(*) > 1 ORDER BY 2 DESC, 1 LIMIT 5;
SELECT id, k FROM big ORDER BY k DESC, id LIMIT 5;
SELECT id FROM big WHERE k BETWEEN 1000 AND 1100 ORDER BY id;
SELECT s FROM big ORDER BY s LIMIT 3 OFFSET 99999;
DELETE FROM big WHERE id % 3 = 0;
UPDATE big SET s = s || '-updated' WHERE id % 5 = 0;
SELECT count(*), sum(length(s)) FROM big;
VACUUM;
PRAGMA integrity_check;
SELECT count(*) FROM pragma_page_count();
