-- ---------------------------------------------------------------------
-- 1. Top 3 Most Sold Items by Year-Month, assuming data is clean
-- Assumes data has been validated in Q5 (no major quality issues affecting aggregation)
-- ---------------------------------------------------------------------
WITH highest_total_quantity_sold_each_year_and_month AS (
    SELECT
        DATE_PART('year',  sale_date)  AS sale_year,      -- STEP 1: extract year
        DATE_PART('month', sale_date)  AS sale_month,     -- STEP 1: extract month
        article                        AS item_name,      -- STEP 1: get item name
        SUM(quantity)                  AS total_sales,    -- STEP 1: total units sold per year-month
        SUM(quantity * unit_price)     AS total_revenue,  -- STEP 2 total revenue per year-month and article
        COUNT(DISTINCT ticket_number)  AS total_unique_tickets, -- STEP 3: unique tickets per year-month and article
        DENSE_RANK() OVER (                               -- STEP 4: DENSE_RANK() every element, Rank items by total quantity sold within each year-month
            PARTITION BY
                DATE_PART('year',  sale_date),            -- STEP 4: reset rank each year
                DATE_PART('month', sale_date)             -- STEP 4: reset rank each month
            ORDER BY SUM(quantity) DESC                   -- STEP 4: rank 1 = highest quantity sold
            ) AS highest_sales_rank
    FROM assignment01.bakery_sales
    GROUP BY
        DATE_PART('year',  sale_date), -- STEP 1, 2 & 3: group by year
        DATE_PART('month', sale_date), -- STEP 1, 2 & 3: then by month within each year
        article                        -- STEP 1, 2 & 3: then by item within each month
)
SELECT
    CONCAT(sale_year, '-', LPAD(sale_month::text, 2, '0')) AS sale_year_month,
    item_name,
    total_sales,
    total_revenue,
    total_unique_tickets,
    highest_sales_rank
FROM highest_total_quantity_sold_each_year_and_month
WHERE highest_sales_rank <= 3                                     -- STEP 5 filter from highest_sales_rank: keep only top 3 per month
ORDER BY sale_year DESC, sale_month DESC, highest_sales_rank ASC; -- STEP 5 sort final output: recent year, month, highest sales


-- ---------------------------------------------------------------------
-- 2. Tickets with 5 or More Unique Articles, assuming data is clean
-- ---------------------------------------------------------------------
WITH ticket_number_and_unique_article_count AS (
    SELECT
        ticket_number,
        COUNT(DISTINCT article) AS unique_article_count -- “Unique articles” refers to distinct item types in a ticket, not quantity
    FROM assignment01.bakery_sales
    WHERE
        DATE_PART('year', sale_date) = 2021             -- Identify all sales tickets in December 2021
    AND DATE_PART('month', sale_date) = 12
    GROUP BY ticket_number                              -- Groups by ticket_number
)
SELECT *
FROM ticket_number_and_unique_article_count
WHERE unique_article_count >= 5                         -- 5 or more unique articles
ORDER BY unique_article_count DESC
;

SELECT
    ticket_number,
    COUNT(DISTINCT article) AS unique_article_count -- Counts distinct articles (unique item types, not quantity)
FROM assignment01.bakery_sales
WHERE
      DATE_PART('year', sale_date) = 2021           -- Filters for December 2021
  AND DATE_PART('month', sale_date) = 12
GROUP BY ticket_number                              -- Groups by ticket_number
HAVING COUNT(DISTINCT article) >= 5                 -- Returns only tickets with 5 or more unique articles
ORDER BY unique_article_count DESC
;

-- ---------------------------------------------------------------------
-- 3. Most Popular Hour for Traditional Baguette Sales, assuming data is clean
-- ---------------------------------------------------------------------
SELECT
    date_part('hour', sale_datetime) AS sale_hour, -- Determine the hour of the day
    SUM(quantity) AS total_quantity_sold           -- Highest quantity sold and not how many transactions
FROM assignment01.bakery_sales
WHERE
    UPPER(article) = 'TRADITIONAL BAGUETTE'        -- Filter for sales of “Traditional Baguette”
AND date_part('month', sale_date) = 7              -- during July (across all years)
GROUP BY sale_hour                                 -- Group by hour (e.g., 14 for 2 PM)
ORDER BY
    total_quantity_sold DESC,                      -- most frequently purchased, Return the hour with the highest quantity sold
    sale_hour ASC                                  -- earliest hour of the day in case of equal sales
LIMIT 1                                            -- Return the hour with the highest quantity sold
;

-- The most popular hour for Traditional Baguette sales during July was
-- 11 AM (hour 11), with a total of 4,060 units sold.
-- In the event of ties, the query was designed to return the earliest hour of the day.

-- ---------------------------------------------------------------------
-- 4. Busiest Two-Hour Window for Sales, assuming data is clean
-- ---------------------------------------------------------------------
WITH hourly_sales AS (
    -- core query to get hourly sales (group by hour)
    -- total quantity (sum quantity per hour) and total revenue (revenue her hour)
    SELECT
        date_part('hour', bs.sale_time)::INT       AS sales_hour,                     -- get it as int & not decimal, to format 07:00 or 11:00,
        SUM(bs.quantity)                           AS total_quantity,
        SUM(bs.quantity * bs.unit_price)           AS total_revenue
    FROM assignment01.bakery_sales bs
    WHERE bs.unit_price IS NOT NULL               -- skip junk rows
    GROUP BY sales_hour
)
-- combine current hour data and next hour data
-- best 2-hour window = hour H + hour H+1
SELECT
    LPAD(current_hour.sales_hour::TEXT, 2, '0') || ':00 - ' ||
    LPAD((next_hour.sales_hour + 1)::TEXT, 2, '0') || ':00'  AS window_hour,           -- total length 2 hours (7(current) - 9(next) hour)
    current_hour.total_quantity + next_hour.total_quantity   AS window_total_quantity,
    current_hour.total_revenue  + next_hour.total_revenue    AS window_total_revenue
FROM hourly_sales AS current_hour                                                      -- 7, current hour data, 7 to 8 = 1 hour
JOIN hourly_sales AS next_hour                                                         -- join: i.e plus 1 hour, 7+1= 8, next hour data, 8 to 9 = 1 hour
        ON next_hour.sales_hour = current_hour.sales_hour + 1                          --           joining with next hour so 7 (current), 8 (next) hour details in one row
ORDER BY window_total_quantity DESC                                                    -- sort: to get highest total quantity of items were sold
LIMIT 1;


-- ---------------------------------------------------------------------
-- 5. Data Quality Checks
-- ---------------------------------------------------------------------
-- just for overview, get invalid records
SELECT *
FROM (
         SELECT *,
                COUNT(*) OVER (
                    PARTITION BY sale_date, sale_time, article, quantity, unit_price
                ) AS duplicate_count
         FROM assignment01.bakery_sales
     ) t
WHERE
    duplicate_count > 1

    -- invalid unit price
   OR unit_price IS  NULL
   OR unit_price <= 0

   -- invalid article
   OR trim(article) = ''
   OR trim(article) = '.'

   -- invalid quantity
   OR quantity IS NULL
   OR quantity <= 0

   -- invalid sale
   OR sale_time IS NULL
   OR sale_date IS NULL
;

-- ---------------------------------------------------------------------
-- 1. MISSING VALUES REPORT
-- ---------------------------------------------------------------------
-- WHERE  : filters rows BEFORE aggregation; excluded rows are gone for the whole query.
-- FILTER : applies per-aggregate AFTER row selection; excluded rows still exist in the
--          result set and still count toward other aggregates in the same SELECT.
SELECT
    COUNT(*)                                                   AS total_rows,
    COUNT(*) FILTER (WHERE sale_date     IS NULL)              AS null_sale_date,
    COUNT(*) FILTER (WHERE sale_time     IS NULL)              AS null_sale_time,
    COUNT(*) FILTER (WHERE sale_datetime IS NULL)              AS null_sale_datetime,
    COUNT(*) FILTER (WHERE ticket_number IS NULL)              AS null_ticket_number,
    COUNT(*) FILTER (WHERE article       IS NULL
                        OR TRIM(article) = ''
                        OR article = '.')                      AS missing_article,
    COUNT(*) FILTER (WHERE quantity      IS NULL)              AS null_quantity,
    COUNT(*) FILTER (WHERE unit_price    IS NULL)              AS null_unit_price
FROM assignment01.bakery_sales;


-- ---------------------------------------------------------------------
-- 2. DUPLICATE RECORDS
-- ---------------------------------------------------------------------

-- 2a. Fully-duplicate rows (every column identical).
SELECT
    sale_datetime, ticket_number, article, quantity, unit_price,
    COUNT(*) AS dup_count
FROM assignment01.bakery_sales
GROUP BY sale_datetime, ticket_number, article, quantity, unit_price
HAVING COUNT(*) > 1
ORDER BY dup_count DESC;

-- 2b. Same article appearing twice on the same ticket.
-- Could be legitimate (cashier re-scanned) or a data-entry error.
SELECT
    ticket_number, article, COUNT(*) AS line_count
FROM assignment01.bakery_sales
GROUP BY ticket_number, article
HAVING COUNT(*) > 1
ORDER BY line_count DESC;


-- ---------------------------------------------------------------------
-- 3. OUTLIERS & INVALID VALUES
-- ---------------------------------------------------------------------

-- 3a. Negative or zero quantities (refunds? bad data?).
SELECT COUNT(*) AS non_positive_quantity
FROM assignment01.bakery_sales
WHERE quantity <= 0;

-- 3b. Negative or zero prices.
SELECT COUNT(*) AS non_positive_price
FROM assignment01.bakery_sales
WHERE unit_price <= 0;

-- 3c. Quantity outliers — anything more than 3 standard deviations
-- above the mean is worth eyeballing.
WITH stats AS (
    SELECT AVG(quantity) AS mu, STDDEV(quantity) AS sigma
    FROM assignment01.bakery_sales
    WHERE quantity > 0
)
SELECT bs.*
FROM assignment01.bakery_sales bs, stats
WHERE bs.quantity > stats.mu + 3 * stats.sigma
ORDER BY bs.quantity DESC;

-- 3d. Price outliers — same idea for unit_price.
WITH stats AS (
    SELECT AVG(unit_price) AS mu, STDDEV(unit_price) AS sigma
    FROM assignment01.bakery_sales
    WHERE unit_price > 0
)
SELECT bs.*
FROM assignment01.bakery_sales bs, stats
WHERE bs.unit_price > stats.mu + 3 * stats.sigma
ORDER BY bs.unit_price DESC;

-- 3e. Consistency check: does sale_datetime match sale_date + sale_time?
-- Mismatches suggest the columns were populated from different sources.
SELECT COUNT(*) AS datetime_mismatches
FROM assignment01.bakery_sales
WHERE sale_datetime <> (sale_date + sale_time);

-- 3f. Date range sanity check — any timestamps in the future or
-- absurdly far in the past?
SELECT MIN(sale_datetime) AS earliest,
       MAX(sale_datetime) AS latest
FROM assignment01.bakery_sales;

-- ---------------------------------------------------------------------
-- FINAL DATA QUALITY SUMMARY (STRUCTURED VIEW)
-- ---------------------------------------------------------------------

-- SECTION BREAKDOWN
-- ---------------------------------------------------------------------
-- Section | Purpose
-- ---------------------------------------------------------------------
-- 1a | Count missing values in critical columns (NULLs, blanks, invalid text)
-- 1b | Identify nulls in transaction identifiers and pricing fields
-- 1c | Detect incomplete or malformed article values (e.g., '.', empty strings)
-- ---------------------------------------------------------------------
-- 2a | Find fully duplicate rows (identical transactions across all columns)
-- 2b | Detect repeated items within the same ticket (possible duplicates or multi-scans)
-- ---------------------------------------------------------------------
-- 3a | Identify invalid quantities (≤ 0) such as returns or data errors
-- 3b | Identify invalid prices (≤ 0) such as missing or corrupted pricing
-- 3c | Detect unusually high quantities using statistical outlier method (mean + 3σ), anything beyond(mean + 3σ) is unusual
-- 3d | Detect unusually high prices using statistical outlier method (mean + 3σ), anything beyond(mean + 3σ) is unusual
-- 3e | Check consistency between timestamp fields (sale_datetime vs date + time) - sanity check
-- 3f | Validate dataset time range (earliest and latest transaction dates, no future dates) - sanity check
-- ---------------------------------------------------------------------

-- Key Findings (brief interpretation)
-- ---------------------------------------------------------------------
-- Out of 234005 total records, missing_article_count = 5, missing_unit_price_count = 5,
-- 500 duplicate data, negativity_quantity_count = 1295, negativity_price_count = 27, 500 quanity wise outliers, 500 price wise outliers,
-- date, time columns are consistent and valid, no major issues found, early and latest sales date are in range 2021-01  to 2022-09
-- ---------------------------------------------------------------------
-- ---------------------------------------------------------------------
-- FINAL DATA QUALITY SUMMARY
-- ---------------------------------------------------------------------

-- Dataset Overview:
-- Total records: 234,005

-- SECTION | FINDINGS
-- ---------------------------------------------------------------------
-- Missing Values:
-- article missing: 5 records
-- unit_price missing: 5 records
-- →Missing data is minimal and unlikely to impact analysis

-- Duplicates:
-- Fully duplicate records: ~500
-- → Indicates possible repeated ingestion or duplicate transactions

-- Invalid Values:
-- Negative/zero quantity: 1,295 records
-- Negative/zero price: 27 records
-- → Likely refunds, corrections, or data entry errors

-- Outliers:
-- Quantity outliers: ~500 records (beyond 3σ threshold)
-- Price outliers: ~500 records (beyond 3σ threshold)
-- → May represent bulk purchases or pricing anomalies

-- Data Consistency:
-- Date/time columns: consistent and valid
-- → No major timestamp inconsistencies found

-- Time Range:
-- Earliest sale: 2021-01
-- Latest sale: 2022-09
-- → Dataset covers a valid and continuous time period

-- ---------------------------------------------------------------------
-- OVERALL CONCLUSION:
-- The dataset is largely clean with minor issues in duplicates, invalid values, and statistical outliers. 
-- It is suitable for analysis after optional filtering depending on business needs.
-- ---------------------------------------------------------------------

