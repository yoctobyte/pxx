-- recursive CTEs, window functions, floating point accumulated in loops
WITH RECURSIVE fib(n, a, b) AS (SELECT 1, 0, 1 UNION ALL SELECT n + 1, b, a + b FROM fib WHERE n < 92)
SELECT n, a FROM fib WHERE n % 10 = 0 OR n > 88;
WITH RECURSIVE x(i) AS (SELECT 0.0 UNION ALL SELECT i + 0.1 FROM x WHERE i < 2.0) SELECT i, printf('%.17g', i) FROM x;
WITH RECURSIVE s(i, acc) AS (SELECT 1, 0.0 UNION ALL SELECT i + 1, acc + 1.0 / i FROM s WHERE i < 100000)
SELECT acc, printf('%.17g', acc) FROM s WHERE i = 100000;
WITH RECURSIVE
  xaxis(x) AS (VALUES(-2.0) UNION ALL SELECT x + 0.05 FROM xaxis WHERE x < 1.2),
  yaxis(y) AS (VALUES(-1.0) UNION ALL SELECT y + 0.1 FROM yaxis WHERE y < 1.0),
  m(iter, cx, cy, x, y) AS (
    SELECT 0, x, y, 0.0, 0.0 FROM xaxis, yaxis
    UNION ALL
    SELECT iter + 1, cx, cy, x * x - y * y + cx, 2.0 * x * y + cy FROM m
     WHERE (x * x + y * y) < 4.0 AND iter < 28),
  m2(iter, cx, cy) AS (SELECT max(iter), cx, cy FROM m GROUP BY cx, cy),
  a(t) AS (SELECT group_concat(substr(' .+*#', 1 + min(iter / 7, 4), 1), '') FROM m2 GROUP BY cy)
SELECT group_concat(rtrim(t), x'0a') FROM a;
WITH RECURSIVE tree(id, parent, depth, path) AS (
  SELECT 1, NULL, 0, '1'
  UNION ALL
  SELECT t.id * 2 + c.k, t.id, t.depth + 1, t.path || '/' || (t.id * 2 + c.k)
    FROM tree t, (SELECT 0 AS k UNION ALL SELECT 1) c WHERE t.depth < 4)
SELECT depth, count(*), max(path) FROM tree GROUP BY depth;
CREATE TABLE sales(region TEXT, month INTEGER, amount REAL);
WITH RECURSIVE g(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM g WHERE i < 59)
INSERT INTO sales SELECT char(65 + i % 3), 1 + i / 3 % 12, round((i * 7919 % 1000) / 7.0, 2) FROM g;
SELECT region, month, amount,
       sum(amount) OVER (PARTITION BY region ORDER BY month, amount ROWS UNBOUNDED PRECEDING) AS running,
       rank() OVER (PARTITION BY region ORDER BY amount DESC) AS rk,
       dense_rank() OVER w, row_number() OVER w, percent_rank() OVER w, cume_dist() OVER w,
       ntile(4) OVER w, lag(amount, 1, -1) OVER w, lead(amount) OVER w,
       first_value(amount) OVER w, last_value(amount) OVER w, nth_value(amount, 3) OVER w
  FROM sales WINDOW w AS (PARTITION BY region ORDER BY amount, month)
 ORDER BY region, amount, month;
SELECT month, avg(amount) OVER (ORDER BY month RANGE BETWEEN 1 PRECEDING AND 1 FOLLOWING),
       count(*) OVER (ORDER BY month GROUPS BETWEEN CURRENT ROW AND 1 FOLLOWING EXCLUDE TIES)
  FROM sales WHERE region = 'B' ORDER BY month, amount;
SELECT region, sum(amount) FILTER (WHERE month <= 6), sum(amount) FILTER (WHERE month > 6),
       group_concat(month, ',' ORDER BY amount DESC)
  FROM sales GROUP BY region;
SELECT region, total(amount), avg(amount), printf('%.10f', avg(amount * amount) - avg(amount) * avg(amount))
  FROM sales GROUP BY region ORDER BY 1;
SELECT * FROM (VALUES (3, 'c'), (1, 'a'), (2, 'b')) ORDER BY column1;
