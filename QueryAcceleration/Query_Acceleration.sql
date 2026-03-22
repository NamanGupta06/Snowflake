CREATE WAREHOUSE wh_without_qas WITH
    WAREHOUSE_SIZE = 'XSMALL'
    ENABLE_QUERY_ACCELERATION = false
    INITIALLY_SUSPENDED = true
    AUTO_SUSPEND = 300;

CREATE WAREHOUSE wh_with_qas WITH
    WAREHOUSE_SIZE = 'XSMALL'
    ENABLE_QUERY_ACCELERATION = true
    QUERY_ACCELERATION_MAX_SCALE_FACTOR = 16
    INITIALLY_SUSPENDED = true
    AUTO_SUSPEND = 300;

--Checking the properties of both the warehouses created.
show warehouses;

--Case 1: using warehouse without QAS
use warehouse wh_without_qas;

--this query tells if the query is eligible for QAS or not.
-- Select PARSE_JSON(SYSTEM$ESTIMATE_QUERY_ACCELERATION('<query_id>'))

-- Use the TPCH sample schema
-- Database: SNOWFLAKE_SAMPLE_DATA
-- Schema:   TPCH_SF1
WITH params AS (
    -- Derive a dynamic 3-year window based on the data’s max order date
    SELECT
        DATEADD(year, -3, MAX(o_orderdate)) AS start_date,
        MAX(o_orderdate)                    AS end_date
    FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
),

base_sales AS (
    SELECT
        r.r_name                                           AS region,
        c.c_mktsegment                                     AS mktsegment,
        p.p_brand                                          AS brand,
        DATE_TRUNC('month', o.o_orderdate)                 AS month,
        l.l_returnflag                                     AS return_flag,
        -- Net sales (classic TPCH revenue definition)
        l.l_extendedprice * (1 - l.l_discount)             AS net_sales,
        l.l_discount                                       AS line_discount,
        o.o_orderkey                                       AS order_id,
        c.c_custkey                                        AS cust_id
    FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM  AS l
    JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS    AS o ON l.l_orderkey = o.o_orderkey
    JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER  AS c ON o.o_custkey  = c.c_custkey
    JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION    AS n ON c.c_nationkey = n.n_nationkey
    JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION    AS r ON n.n_regionkey = r.r_regionkey
    JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PART      AS p ON l.l_partkey   = p.p_partkey
    CROSS JOIN params pr
    WHERE
        -- Restrict to last 3 years of data from the dataset’s perspective
        o.o_orderdate BETWEEN pr.start_date AND pr.end_date
        -- Example data hygiene constraint: shipped on/after ordered
        AND l.l_shipdate >= o.o_orderdate
),

monthly AS (
    -- Aggregate to a monthly grain with multiple business metrics
    SELECT
        region,
        mktsegment,
        brand,
        month,
        SUM(net_sales)                                                    AS revenue,
        COUNT(DISTINCT order_id)                                          AS orders,
        COUNT(DISTINCT cust_id)                                           AS customers,
        AVG(line_discount)                                                AS avg_discount,
        -- Return analytics (TPCH l_returnflag = 'R' indicates returned)
        SUM(IFF(return_flag = 'R', net_sales, 0))                         AS returned_value,
        SUM(IFF(return_flag = 'R', 1, 0))                                 AS return_lines
    FROM base_sales
    GROUP BY 1,2,3,4
),

win AS (
    -- Add rolling and YoY window metrics
    SELECT
        region,
        mktsegment,
        brand,
        month,
        revenue,
        orders,
        customers,
        avg_discount,
        returned_value,
        return_lines,
        -- Rolling 3-month revenue per region/segment/brand
        SUM(revenue) OVER (
            PARTITION BY region, mktsegment, brand
            ORDER BY month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS rev_rolling_3mo,
        -- YoY comparator (same month in prior year)
        LAG(revenue, 12) OVER (
            PARTITION BY region, mktsegment, brand
            ORDER BY month
        ) AS revenue_prev_year
    FROM monthly
),

ranked AS (
    -- Compute YoY growth, and rank brands by revenue within region/month
    SELECT
        *,
        100 * (revenue - revenue_prev_year)
            / NULLIFZERO(revenue_prev_year)                                 AS yoy_growth_pct,
        DENSE_RANK() OVER (
            PARTITION BY region, month
            ORDER BY revenue DESC
        ) AS brand_rank_in_region
    FROM win
)

-- Keep top 5 brands per region per month
SELECT
    month,
    region,
    mktsegment,
    brand,
    revenue,
    rev_rolling_3mo,
    yoy_growth_pct,
    orders,
    customers,
    avg_discount,
    returned_value,
    return_lines
FROM ranked
QUALIFY brand_rank_in_region <= 5
ORDER BY month, region, revenue DESC;

--checking if this query if eligible for not
--this query tells if the query is eligible for QAS or not.
Select PARSE_JSON(SYSTEM$ESTIMATE_QUERY_ACCELERATION('01c31de8-3202-74e2-0014-93e60002e83e'));
-- {
--   "estimatedQueryTimes": {},
--   "ineligibleReason": "NO_LARGE_ENOUGH_SCAN",
--   "originalQueryTime": 5.154,
--   "queryUUID": "01c31de8-3202-74e2-0014-93e60002e83e",
--   "status": "ineligible",
--   "upperLimitScaleFactor": 0
-- }


-- Use the TPC‑DS 10TB schema (switch to TPCDS_SF100TCL if you have it)
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL;

-- Optional: avoid cached results for a fair test
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

CREATE OR REPLACE TABLE SNOWFLAKE_LEARNING_DB.PUBLIC.DEMO_QAS_SALES_AGG AS
WITH base AS (
  SELECT
      d.d_date                                AS sold_date,
      d.d_year,
      i.i_item_id,
      i.i_brand,
      i.i_category,
      s.s_store_id,
      s.s_state,
      c.c_customer_sk,
      cd.cd_gender,
      cd.cd_marital_status,
      p.p_promo_id,
      ss.ss_quantity,
      ss.ss_ext_sales_price,
      ss.ss_net_profit
  FROM STORE_SALES            ss
  JOIN DATE_DIM               d  ON ss.ss_sold_date_sk = d.d_date_sk
  JOIN ITEM                   i  ON ss.ss_item_sk      = i.i_item_sk
  JOIN STORE                  s  ON ss.ss_store_sk     = s.s_store_sk
  JOIN CUSTOMER               c  ON ss.ss_customer_sk  = c.c_customer_sk
  JOIN CUSTOMER_DEMOGRAPHICS  cd ON c.c_current_cdemo_sk = cd.cd_demo_sk
  LEFT JOIN PROMOTION         p  ON ss.ss_promo_sk     = p.p_promo_sk
  WHERE
      -- Scan multiple years (large scan) with some selectivity
      d.d_year BETWEEN 2000 AND 2002
      -- Selective item categories (still scans a lot across 3 years)
      AND i.i_category IN ('Electronics', 'Books', 'Home')
      -- Selective demographics filters
      AND cd.cd_gender = 'F'
      AND cd.cd_marital_status IN ('M','S')
),
monthly AS (
  SELECT
      DATE_TRUNC('month', sold_date)          AS month,
      i_category,
      i_brand,
      s_state,
      APPROX_COUNT_DISTINCT(c_customer_sk)    AS customers,
      COUNT(*)                                AS lines,
      SUM(ss_quantity)                        AS units,
      SUM(ss_ext_sales_price)                 AS revenue,
      SUM(ss_net_profit)                      AS profit
  FROM base
  GROUP BY 1,2,3,4
)
SELECT
    month, i_category, i_brand, s_state,
    customers, lines, units, revenue, profit,
    -- rolling 3‑month profit per brand/state
    SUM(profit) OVER (
      PARTITION BY i_brand, s_state
      ORDER BY month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_profit_3m
FROM monthly
QUALIFY rolling_profit_3m IS NOT NULL
ORDER BY revenue DESC;

--Getting the last query id
Select LAST_QUERY_ID(); --01c31df0-3202-74e2-0014-93e60002e98a


--checking if this query if eligible for not
--this query tells if the query is eligible for QAS or not.
Select PARSE_JSON(SYSTEM$ESTIMATE_QUERY_ACCELERATION('01c31df0-3202-74e2-0014-93e60002e98a'));
-- {
--   "estimatedQueryTimes": {
--     "1": 333, // if we have 1 scale factor then it will take around 333 seconds
--     "2": 292,
--     "4": 258,
--     "8": 236,
--     "9": 233
--   },
--   "ineligibleReason": null,
--   "originalQueryTime": 452.293, //original time which the query took
--   "queryUUID": "01c31df0-3202-74e2-0014-93e60002e98a",
--   "status": "eligible",
--   "upperLimitScaleFactor": 9 // showing the highest scale factor from estimatedQueryTimes
-- }

-- Case 2: Trying the same query with another warehouse
use warehouse wh_with_qas;

--setting the cached result to false so that we can compare between these warehouses
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

--running the same query
CREATE OR REPLACE TABLE SNOWFLAKE_LEARNING_DB.PUBLIC.DEMO_QAS_SALES_AGG AS
WITH base AS (
  SELECT
      d.d_date                                AS sold_date,
      d.d_year,
      i.i_item_id,
      i.i_brand,
      i.i_category,
      s.s_store_id,
      s.s_state,
      c.c_customer_sk,
      cd.cd_gender,
      cd.cd_marital_status,
      p.p_promo_id,
      ss.ss_quantity,
      ss.ss_ext_sales_price,
      ss.ss_net_profit
  FROM STORE_SALES            ss
  JOIN DATE_DIM               d  ON ss.ss_sold_date_sk = d.d_date_sk
  JOIN ITEM                   i  ON ss.ss_item_sk      = i.i_item_sk
  JOIN STORE                  s  ON ss.ss_store_sk     = s.s_store_sk
  JOIN CUSTOMER               c  ON ss.ss_customer_sk  = c.c_customer_sk
  JOIN CUSTOMER_DEMOGRAPHICS  cd ON c.c_current_cdemo_sk = cd.cd_demo_sk
  LEFT JOIN PROMOTION         p  ON ss.ss_promo_sk     = p.p_promo_sk
  WHERE
      -- Scan multiple years (large scan) with some selectivity
      d.d_year BETWEEN 2000 AND 2002
      -- Selective item categories (still scans a lot across 3 years)
      AND i.i_category IN ('Electronics', 'Books', 'Home')
      -- Selective demographics filters
      AND cd.cd_gender = 'F'
      AND cd.cd_marital_status IN ('M','S')
),
monthly AS (
  SELECT
      DATE_TRUNC('month', sold_date)          AS month,
      i_category,
      i_brand,
      s_state,
      APPROX_COUNT_DISTINCT(c_customer_sk)    AS customers,
      COUNT(*)                                AS lines,
      SUM(ss_quantity)                        AS units,
      SUM(ss_ext_sales_price)                 AS revenue,
      SUM(ss_net_profit)                      AS profit
  FROM base
  GROUP BY 1,2,3,4
)
SELECT
    month, i_category, i_brand, s_state,
    customers, lines, units, revenue, profit,
    -- rolling 3‑month profit per brand/state
    SUM(profit) OVER (
      PARTITION BY i_brand, s_state
      ORDER BY month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_profit_3m
FROM monthly
QUALIFY rolling_profit_3m IS NOT NULL
ORDER BY revenue DESC;

--Now we will compare both the queries
Select query_id, query_text, warehouse_name, total_elapsed_time
from TABLE(snowflake.information_schema.query_history())
where query_id IN ('01c31dfd-3202-75ef-0014-93e60002f066','01c31df0-3202-74e2-0014-93e60002e98a');

--Now comparing the cost usage
Select start_time,
end_time,
warehouse_name,
credits_used,
credits_used_compute,
credits_used_cloud_services,
(credits_used + credits_used_compute + credits_used_cloud_services) AS credits_used_total
FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
    DATE_RANGE_START => DATEADD('days',-1,CURRENT_TIMESTAMP()),
    warehouse_name => 'wh_without_qas'
))
UNION 
Select start_time,
end_time,
warehouse_name,
credits_used,
credits_used_compute,
credits_used_cloud_services,
(credits_used + credits_used_compute + credits_used_cloud_services) AS credits_used_total
FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
    DATE_RANGE_START => DATEADD('days',-1,CURRENT_TIMESTAMP()),
    warehouse_name => 'wh_with_qas'
));

-- START_TIME	                    END_TIME	                    WAREHOUSE_NAME	CREDITS_USED	 CREDITS_USED_COMPUTE	CREDITS_USED_CLOUD_SERVICES	                                                                                                                                                    CREDITS_USED_TOTAL
-- 2026-03-18 12:29:12.000 -0700	2026-03-18 13:29:12.000 -0700	WH_WITH_QAS	    0.143333333	     0.143333333	        0.000000000	        0.286666666
-- 2026-03-18 12:29:12.000 -0700	2026-03-18 13:29:12.000 -0700	WH_WITHOUT_QAS	0.318611111	     0.318611111	         0.000000000	    0.637222222
