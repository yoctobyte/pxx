-- the shell's own commands and output modes; run with the cwd set to the
-- test's scratch directory, which holds data.csv
CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT, score REAL, note BLOB);
INSERT INTO t VALUES (1, 'alpha', 1.5, NULL), (2, 'beta, "quoted"', -2.25, x'00ff10'), (3, 'gamma
line', 1e10, 'text');
.headers on
.mode list
SELECT * FROM t;
.mode csv
SELECT * FROM t;
.mode tabs
SELECT * FROM t;
.mode line
SELECT * FROM t WHERE id = 2;
.mode column
SELECT * FROM t;
.mode box
SELECT * FROM t;
.mode table
SELECT id, name FROM t;
.mode markdown
SELECT id, score FROM t;
.mode json
SELECT * FROM t;
.mode insert t2
SELECT * FROM t;
.mode quote
SELECT * FROM t;
.mode html
SELECT id, name FROM t WHERE id < 3;
.mode ascii
SELECT id, name FROM t WHERE id = 1;
.mode list
.separator |
.nullvalue <null>
SELECT * FROM t;
.headers off
.import --csv data.csv imported
SELECT count(*), sum(b), max(c) FROM imported;
.schema
.tables
.indexes
.output out.txt
SELECT 'to a file', 42;
.output stdout
.read out.txt
.print a printed line
.echo on
SELECT 'echoed';
.echo off
.show
.dump t
.sha3sum
.dbconfig defensive
.limit length
.parameter init
.parameter set @x 41
SELECT @x + 1;
.changes on
UPDATE t SET score = score * 2 WHERE id < 3;
.changes off
SELECT 1/0, 'after';
.bail off
SELECT * FROM nosuchtable;
SELECT 'still going';
