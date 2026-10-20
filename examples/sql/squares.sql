-- The capsule's data: x and its square, 1 to 3, as CSV on standard output (sqlite3).
.headers on
.mode list
.separator ,
WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 3)
SELECT x, x * x AS y FROM n;
