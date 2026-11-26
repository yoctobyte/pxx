-- tables, constraints, joins, aggregates, views, triggers, upsert, RETURNING
PRAGMA foreign_keys = ON;
CREATE TABLE dept(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
CREATE TABLE emp(id INTEGER PRIMARY KEY, name TEXT, dept INTEGER REFERENCES dept(id),
                 salary REAL CHECK (salary > 0), hired TEXT,
                 tax REAL GENERATED ALWAYS AS (round(salary * 0.21, 2)) VIRTUAL);
CREATE TABLE audit(at INTEGER, what TEXT);
CREATE TRIGGER emp_ins AFTER INSERT ON emp BEGIN
  INSERT INTO audit VALUES ((SELECT count(*) FROM audit) + 1, 'hired ' || new.name);
END;
INSERT INTO dept(name) VALUES ('eng'), ('ops'), ('sales'), ('empty');
INSERT INTO emp(name, dept, salary, hired) VALUES
  ('ada', 1, 120000, '2019-03-01'), ('bob', 1, 95000.5, '2021-07-15'),
  ('cyd', 2, 70000, '2018-11-30'), ('dee', 3, 65000.25, '2022-01-03'),
  ('eve', 3, 88000, '2020-05-20'), ('fay', NULL, 50000, '2023-09-09');
INSERT INTO emp(name, dept, salary) VALUES ('bad', 99, 1);
INSERT INTO emp(name, dept, salary) VALUES ('neg', 1, -5);
SELECT * FROM audit ORDER BY at;
SELECT d.name, count(e.id), sum(e.salary), avg(e.salary), min(e.hired), max(e.tax)
  FROM dept d LEFT JOIN emp e ON e.dept = d.id GROUP BY d.id ORDER BY d.name;
SELECT name FROM emp WHERE dept IS NULL;
SELECT e.name, d.name FROM emp e RIGHT JOIN dept d ON e.dept = d.id ORDER BY 2, 1;
SELECT e.name, d.name FROM emp e FULL JOIN dept d ON e.dept = d.id ORDER BY 2 NULLS LAST, 1;
SELECT dept, group_concat(name, '+') FROM (SELECT * FROM emp ORDER BY name) GROUP BY dept HAVING count(*) > 1;
SELECT name, salary FROM emp WHERE salary > (SELECT avg(salary) FROM emp) ORDER BY salary DESC;
SELECT name FROM emp WHERE dept IN (SELECT id FROM dept WHERE name LIKE '%s%') ORDER BY name;
SELECT name FROM emp e WHERE EXISTS (SELECT 1 FROM emp f WHERE f.dept = e.dept AND f.salary > e.salary) ORDER BY 1;
CREATE VIEW rich AS SELECT name, salary FROM emp WHERE salary >= 88000;
SELECT * FROM rich ORDER BY salary;
SELECT name, salary FROM emp ORDER BY salary DESC LIMIT 2 OFFSET 1;
CREATE TABLE kv(k TEXT PRIMARY KEY, v INTEGER) WITHOUT ROWID;
INSERT INTO kv VALUES ('a', 1), ('b', 2);
INSERT INTO kv VALUES ('a', 10), ('c', 3) ON CONFLICT(k) DO UPDATE SET v = v + excluded.v;
SELECT * FROM kv ORDER BY k;
UPDATE kv SET v = v * 2 WHERE k <> 'b' RETURNING k, v;
DELETE FROM kv WHERE v > 20 RETURNING *;
CREATE TABLE s(i INTEGER, t TEXT) STRICT;
INSERT INTO s VALUES (1, 'one');
INSERT INTO s VALUES ('x', 2);
SELECT * FROM s;
SELECT name, CASE WHEN salary > 90000 THEN 'high' WHEN salary > 60000 THEN 'mid' ELSE 'low' END FROM emp ORDER BY id;
SELECT name FROM emp UNION SELECT name FROM dept ORDER BY 1;
SELECT dept FROM emp INTERSECT SELECT id FROM dept ORDER BY 1;
SELECT id FROM dept EXCEPT SELECT dept FROM emp ORDER BY 1;
SELECT DISTINCT dept FROM emp ORDER BY dept;
SELECT typeof(tax), tax FROM emp WHERE name = 'bob';
EXPLAIN QUERY PLAN SELECT * FROM emp WHERE dept = 1;
CREATE INDEX emp_dept ON emp(dept, salary);
EXPLAIN QUERY PLAN SELECT * FROM emp WHERE dept = 1 ORDER BY salary;
PRAGMA integrity_check;
PRAGMA foreign_key_check;
