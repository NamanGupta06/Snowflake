--Search Optimization Service(SOS)
-- Usualy used for selective point lookup queries
CREATE DATABASE ORDERS_DB;

CREATE SCHEMA ORDERS_SCHEMA;

CREATE TABLE ORDERS_DB.ORDERS_SCHEMA.ORDERS AS
Select * from SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.ORDERS;

SHOW TABLES like 'ORDERS';

--Search optimization uses a auxiliary data sructure known as search access path which will take some space that we can measure through the column "search_optimization_bytes".
-- Also this search access path needs to be in sync with the underlying table as inserts or updates happen on that table, so this search access path also needs to be updated as well. This might sometimes end up being a lag between the updation of the original table and search access path so the column "search_optimization_progress" shows the percentage of it.

CREATE TABLE ORDERS_DB.ORDERS_SCHEMA.ORDERS_CLUSTERED AS
Select * from SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.ORDERS;

CREATE TABLE ORDERS_DB.ORDERS_SCHEMA.ORDERS_SEARCH_OPTIMIZED AS
Select * from SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.ORDERS;

SHOW TABLES like 'ORDERS%';

--Checking the cardinality of the column to select the clustering key
Select APPROX_COUNT_DISTINCT(O_CUSTKEY) from ORDERS;

Select APPROX_COUNT_DISTINCT(O_ORDERDATE) from ORDERS;

Select APPROX_COUNT_DISTINCT(O_CLERK) from ORDERS;

ALTER TABLE ORDERS_CLUSTERED
CLUSTER BY(O_ORDERDATE);

--the cost of the search optimization service and predict the cost for the table
select SYSTEM$ESTIMATE_SEARCH_OPTIMIZATION_COSTS('ORDERS_SEARCH_OPTIMIZED');

-- To add the search optimization service on table
ALTER TABLE ORDERS_DB.ORDERS_SCHEMA.ORDERS_SEARCH_OPTIMIZED ADD SEARCH OPTIMIZATION;
--After adding the SOS we have to wait sometime since it take time to apply the search access path.

SHOW TABLES like 'ORDERS%';

--To drop the search optimization service on table
-- ALTER TABLE ORDERS_DB.ORDERS_SCHEMA.ORDERS DROP SEARCH OPTIMIZATION;

-- this is how we can check on which columns the search optimization is enabled
DESCRIBE SEARCH OPTIMIZATION ON ORDERS_DB.ORDERS_SCHEMA.ORDERS_SEARCH_OPTIMIZED;


--Benchmarking three of the cases for simple table, clustered table, SOS table

--point quality check
Select * from ORDERS where O_ORDERDATE = '1992-04-29';
-- 24 partitions were scanned

Select * from ORDERS_CLUSTERED where O_ORDERDATE = '1992-04-29';
-- 3 partitions were scanned

Select * from ORDERS_SEARCH_OPTIMIZED where O_ORDERDATE = '1992-04-29';
-- 1 partitions scanned out of 232

--Range query
Select * from ORDERS where O_ORDERDATE > '1992-04-29' and O_ORDERDATE < '1992-06-29';
--47 partitions scanned out of 233

Select * from ORDERS_CLUSTERED where O_ORDERDATE > '1992-04-29' and O_ORDERDATE < '1992-06-29';
--8 partitions scanned out of 232

Select * from ORDERS_SEARCH_OPTIMIZED where O_ORDERDATE > '1992-04-29' and O_ORDERDATE < '1992-06-29';
--49 partitions scanned out of 232

--Now we are done with clustered table as we will compare with other columns than cluster key
--point lookup
Select * from ORDERS where O_CUSTKEY = 10318112;
-- 233 partitions scanned out of 233

Select * from ORDERS_SEARCH_OPTIMIZED where O_CUSTKEY = 10318112;
-- 12 parititons scanned out of 233


Select * from ORDERS where O_CLERK = 'Clerk#000002624';
-- 233 partitions scanned out of 233

Select * from ORDERS_SEARCH_OPTIMIZED where O_CLERK = 'Clerk#000002624';
-- 231 partitions scanned out of 233

-- Hypothesis is that if the cardinality of a column is low then search optimization will not work perfectly but if it is high then it's good.

--Let's check this hypothesis with one or more column having high cardinality
Select * from ORDERS where O_ORDERKEY = 483436964;
-- 233 partitions scanned out of 233

Select * from ORDERS_SEARCH_OPTIMIZED where O_ORDERKEY = 483436964;
-- 1 partitions scanned out of 232

-- NOTE:- SOS works great with columns having high cardinality.
-- We have experimenting with select queries but all of these are also similarly work with insert, update and delete queries as well

--Now checking with queries having IN operator
Select * from ORDERS where O_CUSTKEY IN ('14454412','2709988','10915135');
-- 233 partitions scanned out of 233

Select * from ORDERS_SEARCH_OPTIMIZED where O_CUSTKEY IN ('14454412','2709988','10915135');
-- 61 partitions scanned out of 232 

--Now checking with queries having AND(Conjunction)
Select * from ORDERS where O_CUSTKEY = 2709988 and O_ORDERPRIORITY = '4-NOT SPECIFIED';
-- 233 partitions scanned out of 233

Select * from ORDERS_SEARCH_OPTIMIZED where O_CUSTKEY = 2709988 and O_ORDERPRIORITY = '4-NOT SPECIFIED'; --Since one of the perdicate in the where clause have high cardinality i.e. O_CUSTKEY would have been benefitted by SOS but O_ORDERPRIORITY having less cardinality will not benefitted so overall performance was great.
-- 28 partitions scanned out of 232 

--OR(disjucntion) operation
Select * from ORDERS where O_CUSTKEY = 2709988 OR O_ORDERPRIORITY = '4-NOT SPECIFIED';
-- 233 partitions scanned out of 233

Select * from ORDERS_SEARCH_OPTIMIZED where O_CUSTKEY = 2709988 OR O_ORDERPRIORITY = '4-NOT SPECIFIED';
-- However in the OR clause both the predicates should have high cardinality to be benefitted from the SOS but since O_ORDERPRIORITY is having less cardinality so overall performace degraded.
-- 232 partitions scanned out of 232

--Now checking query with AND clause where both the predicates having high cardinality
SELECT * from ORDERS where O_CUSTKEY = 2709988 and O_ORDERKEY = 565857732;
-- 233 partitions scanned out of 233

SELECT * from ORDERS_SEARCH_OPTIMIZED where O_CUSTKEY = 2709988 and O_ORDERKEY = 565857732;
-- 1 partitions scanned out of 232

ALTER TABLE ORDERS_DB.ORDERS_SCHEMA.ORDERS_SEARCH_OPTIMIZED DROP SEARCH OPTIMIZATION;

SHOW TABLES LIKE 'ORDERS%';

--Applying SOS on specifc columns 
ALTER TABLE ORDERS_DB.ORDERS_SCHEMA.ORDERS_SEARCH_OPTIMIZED ADD SEARCH OPTIMIZATION ON EQUALITY(O_ORDERKEY, O_CUSTKEY, O_ORDERDATE);


SHOW TABLES LIKE 'ORDERS%';

Select * from ORDERS where O_CUSTKEY = 88286;
-- 233 partitions scanned out of 233

Select * from ORDERS_SEARCH_OPTIMIZED where O_CUSTKEY = 88286;
-- 10 partitions scanned out of 233


Select * from ORDERS where O_CLERK = 'Clerk#000080581';
-- 233 partitions scanned out of 233

Select * from ORDERS_SEARCH_OPTIMIZED where O_CLERK = 'Clerk#000080581'; --not a column having search access path
--Table scan has been done because for this column SOS was not turned ON.

--Now we will turn ON two different type of Search optimization
ALTER TABLE ORDERS_SEARCH_OPTIMIZED ADD SEARCH OPTIMIZATION
ON EQUALITY(O_ORDERKEY, O_CUSTKEY, O_ORDERDATE), SUBSTRING(O_COMMENT);

--Now we can run substring command on the specified column
SELECT * FROM ORDERS_SEARCH_OPTIMIZED where O_COMMENT LIKE '%sly%';
-- if we see the query profile SOS didn't work as we can see the table scan because snowflake do the optimization when the substring is >= 5 characters.

SELECT * FROM ORDERS_SEARCH_OPTIMIZED where O_COMMENT LIKE '%instructions%'; -- now it worked

SELECT * FROM ORDERS_SEARCH_OPTIMIZED 
where O_COMMENT LIKE ALL ( '%deposits%','%haggle%'); --working

SELECT * FROM ORDERS_SEARCH_OPTIMIZED where ENDSWITH(O_COMMENT, 'even'); -- not working

SELECT * FROM ORDERS_SEARCH_OPTIMIZED where O_COMMENT RLIKE '^(.*slyly.*slyly)'; --working

--Search Optimization with VARIANT data type
CREATE DATABASE CARSDB;

CREATE SCHEMA CARSSCHEMA;

CREATE OR REPLACE TABLE CARS (
    car_details VARIANT
);

Select * from cars;

Select car_details:brand, car_details:engine from cars;

Select car_details:brand, car_details:engine:type from cars;

Select car_details:brand, car_details:features:safety from cars;

Select car_details:brand, car_details:features:safety[0] from cars;

-- ALTER TABLE CARS ADD SEARCH OPTIMIZATION
--this doesn't work at the table level in variant data type

ALTER TABLE CARS ADD SEARCH OPTIMIZATION ON
EQUALITY(car_details:brand, car_details:model, car_details:id);

SHOW TABLES LIKE 'CARS';

Select * from cars where car_details:id = 3;


