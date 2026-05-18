
------------------------------------------------------------correcting the dates(orders table)-------------------------------------------------------------
---------------##########******I IMPORTED Bill_date_timestamp AS VARCHAR *********##########--------------------------------------------------------
----to check

SELECT
  COALESCE(
    TRY_CONVERT(datetime2, Bill_date_timestamp, 101),  -- MM/DD/YYYY
    TRY_CONVERT(datetime2, Bill_date_timestamp, 103),  -- DD/MM/YYYY
    TRY_CONVERT(datetime2, Bill_date_timestamp, 120),  -- YYYY-MM-DD HH:MI:SS
    TRY_CONVERT(datetime2, Bill_date_timestamp, 126)   -- ISO 8601
  ) AS ConvertedDateTime
FROM Orders

----to update
ALTER TABLE Orders
ADD CorrectDate datetime2

UPDATE Orders
SET CorrectDate = COALESCE(
                       TRY_CONVERT(datetime2, Bill_date_timestamp, 101),  -- MM/DD/YYYY
                       TRY_CONVERT(datetime2, Bill_date_timestamp, 103),  -- DD/MM/YYYY
                       TRY_CONVERT(datetime2, Bill_date_timestamp, 120),  -- YYYY-MM-DD HH:MI:SS
                       TRY_CONVERT(datetime2, Bill_date_timestamp, 126)   -- ISO 8601
                       )

--------------------------------------------removing records which are not in 2021-09-01 and 2023-10-31(orders table)-------------------------------------
----to check 

select * from Orders
where correctdate < '2021-09-01' or correctdate > '2023-12-31'


----to update(04 row affected)
DELETE FROM Orders
where correctdate < '2021-09-01' or correctdate > '2023-12-31'


--------------------------------------------removing duplicate in store table(1 row changed)------------------------------------------------------------------------
----to check
WITH CTE AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY StoreID ORDER BY (SELECT 0)) AS rn  -- to identify duplicates per StoreID
    FROM 
        stores_info
)
SELECT *
FROM CTE
WHERE rn > 1

----to update
WITH CTE AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY StoreID ORDER BY (SELECT 0)) AS rn  ---to remove store 
    FROM 
        stores_info
)
DELETE FROM CTE 
WHERE rn > 1


---------------------------------------------replacing #N/A in products table--------------------------------------------------------
----to check


select distinct (a.Category) from Product_info as a

----to update
UPDATE Product_info
SET Category = REPLACE(Category, '#N/A', 'Others')
WHERE Category = '#N/A'


------------------------------------------------tranpose order payment table---------------------------------------------------------

SELECT
    order_id,
    SUM(CASE WHEN payment_type = 'Voucher' THEN payment_value ELSE 0 END) AS Voucher,
    SUM(CASE WHEN payment_type = 'UPI/Cash' THEN payment_value ELSE 0 END) AS [UPI/Cash],
    SUM(CASE WHEN payment_type = 'Credit_card' THEN payment_value ELSE 0 END) AS [Credit card],
    SUM(CASE WHEN payment_type = 'Debit_card' THEN payment_value ELSE 0 END) AS [Debit card],
    SUM(payment_value) AS Total_Amount
    INTO ordpay_summary
FROM OrderPayments
GROUP BY order_id
ORDER BY order_id

select * from ordpay_summary


-------------------------------------------adding average score (customer review table)---------------------

----TO CHECK

select b.order_id,avg(b.Customer_Satisfaction_Score) average_rating from OrderReview_Ratings as b
group by b.order_id

----to upate
SELECT 
    a.order_id,
    AVG(a.Customer_Satisfaction_Score) AS average_score
INTO rev_avg_score
FROM OrderReview_Ratings AS a
GROUP BY a.order_id



---------------------------------------------ADDING NEW TOTAL AMOUNT-------------------------------------------------------------------

ALTER TABLE Orders
ADD new_total_amount FLOAT

UPDATE Orders
SET new_total_amount = Quantity*(MRP-Discount)


----------------------------------------missmatched amount with old total amount-------------------------------------------------

with x as (
           select order_id,cast(SUM(total_amount) AS decimal(10,2)) as sum_ta from Orders group by order_id
)
select o.*,cast(p.[Total_Amount] AS decimal(10,2)) as pd_amt,ABS(cast(p.[Total_Amount] AS decimal(10,2))-sum_ta) as diff 
from x as o inner join ordpay_summary p on p.order_id=o.order_id
where cast(p.[Total_Amount] AS decimal(10,2))<>sum_ta and ABS(cast(p.[Total_Amount] AS decimal(10,2))-sum_ta)>1
order by diff desc


----------------------------------- removing cummulative orders(10223 row changes) ---------------------------------------------

----to check
WITH RankedOrders AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY order_id, product_id ORDER BY quantity DESC) AS rn
    FROM Orders
)
SELECT *
FROM RankedOrders
WHERE rn > 1

----to update  (10223 rows affected)
  WITH RankedOrders AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY order_id, product_id ORDER BY quantity DESC) AS rn
    FROM Orders
)
DELETE FROM RankedOrders
WHERE rn > 1


---------------------------------------------------updating storeids -----------------------------------------------------------------

-- Preview what will change:
WITH Ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id, order_id
               ORDER BY Total_Amount DESC, Quantity DESC ) AS rn
    FROM Orders
    WHERE channel = 'instore'),

Preferred AS (
    SELECT customer_id, order_id, Delivered_StoreID AS PreferredStore
    FROM Ranked
    WHERE rn = 1)

SELECT o.*, p.PreferredStore
FROM Orders o
JOIN Preferred p
  ON o.customer_id = p.customer_id
 AND o.order_id = p.order_id
WHERE o.Delivered_StoreID <> p.PreferredStore
  AND o.channel = 'instore'

---------making the change permanent(1003 row changed)

  WITH Ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id, order_id
               ORDER BY Total_Amount DESC, Quantity DESC
           ) AS rn
    FROM Orders
    WHERE channel = 'instore'
),
Preferred AS (
    SELECT customer_id, order_id, Delivered_StoreID AS PreferredStore
    FROM Ranked
    WHERE rn = 1
)
  UPDATE o
SET Delivered_StoreID = p.PreferredStore
FROM Orders o
JOIN Preferred p
  ON o.customer_id = p.customer_id
 AND o.order_id = p.order_id
WHERE o.Delivered_StoreID <> p.PreferredStore
      AND o.channel = 'instore'



--------------------------------------------------changing the date stamp-----------------------------------------------------------
------------Preview what will change:

WITH FirstTS AS (
    SELECT customer_id,
           order_id,
           MIN(CorrectDate) AS FirstBillTS
    FROM Orders
    WHERE Channel = 'Instore'  -- only consider Instore orders when finding the first timestamp
    GROUP BY customer_id, order_id
)
SELECT o.*,
       f.FirstBillTS
FROM Orders o
JOIN FirstTS f
  ON o.customer_id = f.customer_id
 AND o.order_id = f.order_id
WHERE o.CorrectDate <> f.FirstBillTS
  AND o.Channel = 'Instore'   -- only show Instore rows
ORDER BY o.customer_id, o.order_id

-----applying the changes(335 rows affected)

WITH FirstTS AS (
    SELECT customer_id,
           order_id,
           MIN(CorrectDate) AS FirstBillTS
    FROM Orders
    WHERE Channel = 'Instore'  
    GROUP BY customer_id, order_id
)
UPDATE o
SET CorrectDate = f.FirstBillTS
FROM Orders o
JOIN FirstTS f
  ON o.customer_id = f.customer_id
 AND o.order_id = f.order_id
WHERE o.CorrectDate <> f.FirstBillTS
  AND o.Channel = 'Instore'


-------------------------- dropping order_id in orderpay table that are not in order table----------------------------------------

----to check
select * FROM ordpay_summary AS a
LEFT JOIN Orders AS b
    ON a.order_id = b.order_id
WHERE b.order_id IS NULL

----to update   (778 rows affected)
DELETE a
FROM ordpay_summary AS a
LEFT JOIN Orders AS b
    ON a.order_id = b.order_id
WHERE b.order_id IS NULL


-----------------------------------------------------changing customer_ids -----------------------------------------------------------

----to check
WITH x AS (
    SELECT 
        order_id, customer_id AS m_custid,rn_check
    FROM (SELECT *,ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY quantity DESC) AS rn_check
        FROM Orders
        WHERE order_id IN (SELECT order_id FROM Orders GROUP BY order_id HAVING COUNT(DISTINCT customer_id) > 1)
        )t
    WHERE rn_check = 1)
SELECT 
    o.order_id,
    o.customer_id AS old_customer_id,
    x.m_custid AS new_customer_id
FROM Orders o
INNER JOIN x
    ON o.order_id = x.order_id

----to update  (2 rows affected)
with x as (
select order_id, customer_id as m_custid,rn_check
from (select *,
ROW_NUMBER() over (partition by order_id order by quantity desc) as rn_check
from Orders where order_id in (SELECT order_id FROM Orders GROUP BY order_id HAVING COUNT(DISTINCT customer_id) > 1)
)t
where rn_check = 1)

update o
set o.customer_id = x.m_custid
from Orders o
INNER JOIN X
on o.order_id = x.order_id


------------------------------------------------------------------------------------------------------------------------
---------------------------############# stores360 ###############------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

WITH StoreBase AS (
    SELECT 
        s.storeid,
        s.seller_city AS Location,
        COUNT(DISTINCT o.order_id) AS No_of_Orders,
        COUNT(DISTINCT o.product_id) AS No_of_Items,
        SUM(o.quantity) AS Total_Qty,
        SUM(o.new_total_amount) AS Total_Amount,
        SUM(o.discount) AS Total_Discount,
        SUM(CASE WHEN o.discount > 0 THEN 1 ELSE 0 END) AS Items_With_Discount,
        SUM(o.quantity * o.cost_per_unit) AS Total_Cost,
        SUM(o.new_total_amount - (o.quantity * o.cost_per_unit)) AS Total_Profit,
        COUNT(DISTINCT p.category) AS Distinct_Categories,
        MAX(o.correctdate) AS Last_Order_Date
    FROM Orders o
    LEFT JOIN Product_info p ON o.product_id = p.product_id
    LEFT JOIN stores_info s ON o.delivered_storeid = s.storeid
    GROUP BY s.storeid, s.seller_city
),
ProfitFlags AS (
    SELECT 
        sb.*,
        CASE WHEN sb.Total_Profit < 0 THEN 1 ELSE 0 END AS Flag_Loss_Making,
        CASE 
            WHEN sb.Total_Profit >= PERCENTILE_CONT(0.75) 
                 WITHIN GROUP (ORDER BY sb.Total_Profit) OVER () THEN 1 
            ELSE 0 
        END AS Orders_with_High_Profit
    FROM StoreBase sb
),
WeekendFlags AS (
    SELECT 
        pf.storeid,
        pf.Location,
        pf.No_of_Orders,
        pf.No_of_Items,
        pf.Total_Qty,
        pf.Total_Amount,
        pf.Total_Discount,
        pf.Items_With_Discount,
        pf.Total_Cost,
        pf.Total_Profit,
        pf.Flag_Loss_Making,
        pf.Orders_with_High_Profit,
        pf.Distinct_Categories,
        CASE 
            WHEN DATENAME(WEEKDAY, pf.Last_Order_Date) IN ('Saturday', 'Sunday') THEN 1 
            ELSE 0 
        END AS Weekend_Trans_Flag
    FROM ProfitFlags pf
),
OrderBase AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.delivered_storeid,
        o.correctdate,
        SUM(o.new_total_amount) AS Order_Amount,
        SUM(o.discount) AS Total_Discount,
        SUM(o.quantity * o.cost_per_unit) AS Total_Cost,
        SUM(o.new_total_amount - (o.quantity * o.cost_per_unit)) AS Profit
    FROM Orders o
    GROUP BY o.order_id, o.customer_id, o.delivered_storeid, o.correctdate
),
TimeFlags AS (
    SELECT
        ob.*,
        CASE 
            WHEN DATEPART(HOUR, ob.correctdate) BETWEEN 6 AND 11 THEN 'Morning'
            WHEN DATEPART(HOUR, ob.correctdate) BETWEEN 12 AND 17 THEN 'Afternoon'
            WHEN DATEPART(HOUR, ob.correctdate) BETWEEN 18 AND 23 THEN 'Evening'
            ELSE 'Night'
        END AS Hours_Flag,
        CASE 
            WHEN DATENAME(WEEKDAY, ob.correctdate) IN ('Saturday','Sunday') THEN 'Weekend'
            ELSE 'Weekday'
        END AS Day_Type
    FROM OrderBase ob
),
Ratings AS (
    SELECT
        r.order_id,
        r.average_score
    FROM dbo.rev_avg_score r
),
Joined AS (
    SELECT 
        tf.*,
        r.average_score
    FROM TimeFlags tf
    LEFT JOIN Ratings r ON tf.order_id = r.order_id
)
SELECT 
    -- Store level columns
    sf.storeid,
    sf.Location,
    sf.No_of_Orders, 
    sf.No_of_Items,
    sf.Total_Qty,
    sf.Total_Amount,
    sf.Total_Discount,
    sf.Items_With_Discount,
    sf.Total_Cost,
    sf.Total_Profit,
    sf.Flag_Loss_Making,
    sf.Orders_with_High_Profit,
    sf.Distinct_Categories,
    sf.Weekend_Trans_Flag,

    -- Order level columns
    SUM(CASE WHEN jf.Day_Type = 'Weekend' THEN jf.Order_Amount ELSE 0 END) AS Weekend_Sales,
    SUM(CASE WHEN jf.Day_Type = 'Weekday' THEN jf.Order_Amount ELSE 0 END) AS Weekday_Sales,
    AVG(jf.Order_Amount) AS Average_Order_Value,
    AVG(jf.Profit) AS Average_Profit_Per_Transaction,
    SUM(jf.Profit) / COUNT(DISTINCT jf.customer_id) AS Average_Profit_Per_Customer,
    CAST(COUNT(jf.order_id) AS FLOAT) / COUNT(DISTINCT jf.customer_id) AS Average_Customer_Visits,
    AVG(jf.average_score) AS Average_Rating_Per_Customer

FROM WeekendFlags sf
LEFT JOIN Joined jf ON sf.storeid = jf.delivered_storeid
GROUP BY 
    sf.storeid, 
    sf.Location,
    sf.No_of_Orders, 
    sf.No_of_Items,
    sf.Total_Qty,
    sf.Total_Amount,
    sf.Total_Discount,
    sf.Items_With_Discount,
    sf.Total_Cost,
    sf.Total_Profit,
    sf.Flag_Loss_Making,
    sf.Orders_with_High_Profit,
    sf.Distinct_Categories,
    sf.Weekend_Trans_Flag
ORDER BY 
    sf.storeid



----------------------------------------------------------------------------------------------------------------------
---------------------------############# Orders360 ###############----------------------------------------------------
----------------------------------------------------------------------------------------------------------------------

WITH OrderDetails AS (
    SELECT 
        o.order_id,
        COUNT(DISTINCT o.product_id)               AS No_of_items,
        SUM(o.quantity)                            AS Total_Qty,
        SUM(o.new_total_amount)                    AS Total_Amount,
        SUM(o.discount)                            AS Total_Discount,
        SUM(CASE WHEN o.discount > 0 THEN 1 ELSE 0 END) AS Items_with_Discount,
        SUM(o.quantity * o.cost_per_unit)         AS Total_Cost,
        SUM(o.new_total_amount - (o.quantity * o.cost_per_unit)) AS Total_Profit
    FROM Orders o
    GROUP BY o.order_id
),
BaseOrder AS (
    SELECT 
        o.order_id,
        SUM(o.new_total_amount - (o.quantity * o.cost_per_unit)) AS Total_Profit,
        COUNT(DISTINCT p.category) AS Distinct_Categories,
        MAX(o.correctdate) AS Order_DateTime
    FROM Orders o
    LEFT JOIN Product_info p ON o.product_id = p.product_id
    GROUP BY o.order_id
),
DateFlags AS (
    SELECT
        b.order_id,
        b.Total_Profit,
        b.Distinct_Categories,
        b.Order_DateTime,
        CASE 
            WHEN DATENAME(WEEKDAY, b.Order_DateTime) IN ('Sunday') THEN 'Sunday'
            WHEN DATENAME(WEEKDAY, b.Order_DateTime) IN ('Saturday') THEN 'Saturday'
            ELSE 'Weekday'
        END AS Weekend_Trans_Flag,
        CASE 
            WHEN DATEPART(HOUR, b.Order_DateTime) BETWEEN 6 AND 11 THEN 'Morning'
            WHEN DATEPART(HOUR, b.Order_DateTime) BETWEEN 12 AND 16 THEN 'Afternoon'
            WHEN DATEPART(HOUR, b.Order_DateTime) BETWEEN 17 AND 21 THEN 'Evening'
            ELSE 'Night'
        END AS Hours_Flag
    FROM BaseOrder b
),
ProfitFlags AS (
    SELECT 
        d.*,
        CASE WHEN d.Total_Profit < 0 THEN 'Negative' ELSE 'Positive' END AS Flag_Loss_Making,
        CASE 
            WHEN d.Total_Profit >= PERCENTILE_CONT(0.75) 
                 WITHIN GROUP (ORDER BY d.Total_Profit) OVER () THEN 'High' 
            ELSE 'Moderate' 
        END AS Orders_with_High_Profit
    FROM DateFlags d
)
SELECT 
    od.order_id,
    od.No_of_items,
    od.Total_Qty,
    od.Total_Amount,
    od.Total_Discount,
    od.Items_with_Discount,
    od.Total_Cost,
    od.Total_Profit,
    pf.Flag_Loss_Making,
    pf.Orders_with_High_Profit,
    pf.Distinct_Categories,
    pf.Weekend_Trans_Flag,
    pf.Hours_Flag
FROM OrderDetails od
JOIN ProfitFlags pf ON od.order_id = pf.order_id
ORDER BY od.order_id




----------------------------------------------------------------------------------------------------------------------
---------------------------############# Customer360 ###############--------------------------------------------------
----------------------------------------------------------------------------------------------------------------------




WITH TransactionDetails AS (
    SELECT 
        c.custid, 
        c.customer_city, 
        c.customer_state, 
        c.gender,
        o.order_id,
        o.correctdate,
        o.quantity,
        o.new_total_amount,
        o.discount,
        o.cost_per_unit,
        o.channel,
        o.delivered_storeid,
        o.product_id,
        p.category,
        op.voucher, 
        op.[upi/cash], 
        op.[Credit card], 
        op.[Debit card], 
        op.total_amount AS payment_total,
        s.seller_city, 
        s.seller_state,
        r.customer_satisfaction_score
    FROM 
        Customers c
    LEFT JOIN Orders o ON c.custid = o.customer_id
    LEFT JOIN Product_info p ON o.product_id = p.product_id
    LEFT JOIN ordpay_summary op ON o.order_id = op.order_id
    LEFT JOIN stores_info s ON o.delivered_storeid = s.storeid
    LEFT JOIN OrderReview_Ratings r ON o.order_id = r.order_id
),

CustomerMetrics AS (
    SELECT 
        c.custid, 
        c.customer_city, 
        c.customer_state, 
        c.gender,
        MIN(o.correctdate) AS First_Transaction_Date,
        MAX(o.correctdate) AS Last_Transaction_Date,
        DATEDIFF(DAY, MAX(o.correctdate), (SELECT MAX(correctdate) FROM Orders)) AS Inactive_Days,
        COUNT(DISTINCT o.order_id) AS Frequency,
        SUM(o.new_total_amount) AS Monetary,
        SUM(o.new_total_amount - o.quantity * o.cost_per_unit) AS Profit,
        SUM(o.discount) AS Discount,
        SUM(o.quantity) AS Total_Quantity,
        COUNT(DISTINCT o.product_id) AS Distinct_Items_Purchased
    FROM 
        Customers c
    LEFT JOIN 
        Orders o ON c.custid = o.customer_id
    GROUP BY 
        c.custid, 
        c.customer_city, 
        c.customer_state, 
        c.gender
),

-- ✅ Find the most purchased category per customer
TopCategory AS (
    SELECT 
        custid,
        category,
        ROW_NUMBER() OVER (PARTITION BY custid ORDER BY COUNT(*) DESC) AS rn
    FROM TransactionDetails
    WHERE category IS NOT NULL
    GROUP BY custid, category
),

AggregatedMetrics AS (
    SELECT 
        custid,
        COUNT(DISTINCT category) AS Distinct_Categories_Purchased,
        COUNT(CASE WHEN discount > 0 THEN 1 END) AS Transactions_with_Discount,
        COUNT(CASE WHEN new_total_amount < quantity * cost_per_unit THEN 1 END) AS Transactions_with_Loss,
        COUNT(DISTINCT channel) AS Channels_Used,
        COUNT(DISTINCT delivered_storeid) AS Distinct_Stores,
        COUNT(DISTINCT seller_city) AS Distinct_Cities,
        COUNT(DISTINCT CASE 
                        WHEN voucher > 0 THEN 'Voucher'
                        WHEN [upi/cash] > 0 THEN 'UPI/Cash'
                        WHEN [Credit card] > 0 THEN 'Credit Card'
                        WHEN [Debit card] > 0 THEN 'Debit Card'
                     END) AS Different_Payment_Types,
        COUNT(CASE WHEN voucher > 0 THEN 1 END) AS Transactions_Paid_with_Voucher,
        COUNT(CASE WHEN [Credit card] > 0 THEN 1 END) AS Transactions_Paid_with_Credit_Card,
        COUNT(CASE WHEN [Debit card] > 0 THEN 1 END) AS Transactions_Paid_with_Debit_Card,        
        COUNT(CASE WHEN [upi/cash] > 0 THEN 1 END) AS Transactions_Paid_with_UPI,
        CASE 
            WHEN COUNT(CASE WHEN voucher > 0 THEN 1 END) > 
                 COUNT(CASE WHEN [Credit card] > 0 THEN 1 END) 
                 AND COUNT(CASE WHEN voucher > 0 THEN 1 END) > 
                 COUNT(CASE WHEN [Debit card] > 0 THEN 1 END) 
                 AND COUNT(CASE WHEN voucher > 0 THEN 1 END) > 
                 COUNT(CASE WHEN [upi/cash] > 0 THEN 1 END) 
            THEN 'Voucher'
            WHEN COUNT(CASE WHEN [Credit card] > 0 THEN 1 END) > 
                 COUNT(CASE WHEN [Debit card] > 0 THEN 1 END) 
                 AND COUNT(CASE WHEN [Credit card] > 0 THEN 1 END) > 
                 COUNT(CASE WHEN [upi/cash] > 0 THEN 1 END) 
            THEN 'Credit Card'
            WHEN COUNT(CASE WHEN [Debit card] > 0 THEN 1 END) > 
                 COUNT(CASE WHEN [upi/cash] > 0 THEN 1 END) 
            THEN 'Debit Card'
            ELSE 'UPI'
        END AS Preferred_Payment_Method
    FROM 
        TransactionDetails
    GROUP BY 
        custid
),

FirstPurchaseInfo AS (
    SELECT 
        c.custid,
        MIN(o.correctdate) AS First_Transaction_Date,
        SUM(o.quantity) AS First_Purchase_Qty,
        SUM(o.new_total_amount) AS First_Purchase_Amount,
        COUNT(DISTINCT o.product_id) AS Distinct_Items_Purchased,
        COUNT(DISTINCT p.category) AS Distinct_Categories_Purchased,
        AVG(r.customer_satisfaction_score) AS Average_Satisfaction_Score
    FROM 
        Customers c
    LEFT JOIN Orders o ON c.custid = o.customer_id
    LEFT JOIN Product_info p ON o.product_id = p.product_id
    LEFT JOIN OrderReview_Ratings r ON o.order_id = r.order_id
    GROUP BY 
        c.custid
),

CustomerSpend AS (
    SELECT 
        c.custid,
        SUM(o.new_total_amount) AS Total_Spend
    FROM 
        Customers c
    LEFT JOIN Orders o ON c.custid = o.customer_id
    GROUP BY c.custid
),

SpendPercentiles AS (
    SELECT 
        custid,
        NTILE(3) OVER (ORDER BY Total_Spend) AS Spend_Segment
    FROM CustomerSpend
)

SELECT 
    cm.custid,
    cm.customer_city,
    cm.customer_state,
    cm.gender,
    tc.category AS Top_Category,       -------------------------------------------------------------------------------------------------------------- -- top purchased category added here
    cm.First_Transaction_Date,
    cm.Last_Transaction_Date,
    cm.Inactive_Days,
    cm.Frequency,
    cm.Monetary,
    cm.Profit,
    cm.Discount,
    cm.Total_Quantity,
    cm.Distinct_Items_Purchased,
    am.Distinct_Categories_Purchased,
    am.Transactions_with_Discount,
    am.Transactions_with_Loss,
    am.Channels_Used,
    am.Distinct_Stores,
    am.Distinct_Cities,
    am.Different_Payment_Types,
    am.Transactions_Paid_with_Voucher,
    am.Transactions_Paid_with_Credit_Card,
    am.Transactions_Paid_with_Debit_Card,
    am.Transactions_Paid_with_UPI,
    am.Preferred_Payment_Method,
    fpi.First_Purchase_Qty,
    fpi.First_Purchase_Amount,
    fpi.Distinct_Items_Purchased AS First_Purchase_Distinct_Items,
    fpi.Distinct_Categories_Purchased AS First_Purchase_Distinct_Categories,
    fpi.Average_Satisfaction_Score,
    CASE 
        WHEN sp.Spend_Segment = 1 THEN 'Low'
        WHEN sp.Spend_Segment = 2 THEN 'Medium'
        WHEN sp.Spend_Segment = 3 THEN 'High'
    END AS Customer_Segment
FROM 
    CustomerMetrics cm
LEFT JOIN 
    AggregatedMetrics am ON cm.custid = am.custid
LEFT JOIN 
    TopCategory tc ON cm.custid = tc.custid AND tc.rn = 1   ------------------------------------------------------------------------------------------ only top category per customer
LEFT JOIN 
    FirstPurchaseInfo fpi ON cm.custid = fpi.custid
LEFT JOIN 
    SpendPercentiles sp ON cm.custid = sp.custid
WHERE 
    fpi.First_Purchase_Qty IS NOT NULL
ORDER BY 
    cm.custid





       --===============   1. Perform Detailed exploratory analysis ==--

-- Total No. Of Orders

SELECT 
    COUNT(DISTINCT order_id) AS Total_Orders
FROM Orders

-- Total Discount 

SELECT 
    ROUND(SUM(discount), 2) AS Total_Discount
FROM Orders

-- Average Discount per Customer

SELECT 
    ROUND(SUM(discount) / COUNT(DISTINCT customer_id), 2) AS Average_Discount_Per_Customer
FROM Orders

-- Average Discount per Order

SELECT 
    ROUND(AVG(discount), 2) AS Average_Discount_Per_Order
FROM Orders

-- Average Order Value (AOV) / Average Bill Value

SELECT 
    ROUND(SUM(new_total_amount) / COUNT(DISTINCT order_id), 2) AS Average_Order_Value
FROM Orders

-- Average Sales per Customer

SELECT 
    ROUND(SUM(new_total_amount) / COUNT(DISTINCT customer_id), 2) AS Average_Sales_Per_Customer
FROM Orders

-- Average Profit per Customer

SELECT 
    ROUND(SUM(new_total_amount - (quantity * cost_per_unit)) / COUNT(DISTINCT customer_id), 2) AS Average_Profit_Per_Customer
FROM Orders

-- Average Number of Categories per Order

;WITH OrderCategoryCount AS (
    SELECT 
        o.order_id,
        COUNT(DISTINCT p.category) AS Category_Count
    FROM Orders o
    JOIN Product_info p 
        ON o.product_id = p.product_id
    GROUP BY o.order_id
)
SELECT 
    ROUND(AVG(Category_Count), 2) AS Avg_Categories_Per_Order
FROM OrderCategoryCount

-- Average Number of Items per Order

;WITH OrderItemCount AS (
    SELECT 
        order_id,
        SUM(quantity) AS Item_Count
    FROM Orders
    GROUP BY order_id
)
SELECT 
    ROUND(AVG(Item_Count), 2) AS Avg_Items_Per_Order
FROM OrderItemCount

-- Number of Customers

SELECT 
    COUNT(DISTINCT customer_id) AS Total_Customers
FROM Orders

-- Transactions per Customer

;WITH CustomerOrderCount AS (
    SELECT 
        customer_id,
        COUNT(DISTINCT order_id) AS Total_Orders
    FROM Orders
    GROUP BY customer_id
)
SELECT 
    ROUND(AVG(Total_Orders), 2) AS Transactions_Per_Customer
FROM CustomerOrderCount

-- Total Revenue

SELECT 
    ROUND(SUM(new_total_amount), 2) AS Total_Revenue
FROM Orders

-- Total Profit

SELECT 
    ROUND(SUM(new_total_amount - (quantity * cost_per_unit)), 2) AS Total_Profit
FROM Orders

-- Total Cost

SELECT 
    ROUND(SUM(quantity * cost_per_unit), 2) AS Total_Cost
FROM Orders

-- Total Quantity

SELECT 
    SUM(quantity) AS Total_Quantity
FROM Orders

-- Total Products

SELECT 
    COUNT(DISTINCT product_id) AS Total_Products
FROM Orders

-- Total Categories
SELECT 
    COUNT(DISTINCT p.category) AS Total_Categories
FROM Orders o
JOIN Product_info p ON o.product_id = p.product_id

-- Total Stores
SELECT 
    COUNT(DISTINCT delivered_storeid) AS Total_Stores
FROM Orders

-- Total Locations (Store City Level)

SELECT 
    COUNT(DISTINCT s.seller_city) AS Total_Locations
FROM stores_info s

-- Total Locations (Store State Level)

SELECT 
    COUNT(DISTINCT s.seller_state) AS Total_Regions
FROM stores_info s

-- Total Channels

SELECT 
    COUNT(DISTINCT channel) AS Total_Channels
FROM Orders

-- Total Payment Methods

SELECT 
    COUNT(DISTINCT payment_type) AS Total_Payment_Methods
FROM OrderPayments

-- Average Number of Days Between Two Transactions

;WITH CustomerTransactionGaps AS (
    SELECT 
        customer_id,
        DATEDIFF(
            DAY, 
            LAG(correctdate) OVER (PARTITION BY customer_id ORDER BY correctdate),
            correctdate
        ) AS Days_Between
    FROM Orders
)
SELECT 
    ROUND(AVG(Days_Between * 1.0), 2) AS Avg_Days_Between_Transactions
FROM CustomerTransactionGaps
WHERE Days_Between IS NOT NULL

-- Percentage of Profit

SELECT 
    ROUND((SUM(new_total_amount - (quantity * cost_per_unit)) / SUM(new_total_amount)) * 100, 2) AS Profit_Percentage
FROM Orders

-- Percentage of Discount

SELECT 
    ROUND((SUM(discount) / SUM(new_total_amount)) * 100, 2) AS Discount_Percentage
FROM Orders

-- Repeat Purchase Rate

;WITH CustomerOrders AS (
    SELECT 
        customer_id,
        COUNT(DISTINCT order_id) AS Order_Count
    FROM Orders
    GROUP BY customer_id
)
SELECT 
    ROUND(
        (COUNT(CASE WHEN Order_Count > 1 THEN 1 END) * 100.0 / COUNT(*)), 
        2
    ) AS Repeat_Purchase_Rate
FROM CustomerOrders

-- Repeat Customer Percentage

;WITH CustomerOrders AS (
    SELECT 
        customer_id,
        COUNT(DISTINCT order_id) AS Order_Count
    FROM Orders
    GROUP BY customer_id
)
SELECT 
    ROUND(
        (COUNT(CASE WHEN Order_Count > 1 THEN 1 END) * 100.0 / COUNT(*)), 
        2
    ) AS Repeat_Customer_Percentage
FROM CustomerOrders

-- One-Time Buyers Percentage

;WITH CustomerOrders AS (
    SELECT 
        customer_id,
        COUNT(DISTINCT order_id) AS Order_Count
    FROM Orders
    GROUP BY customer_id
)
SELECT 
    ROUND(
        (COUNT(CASE WHEN Order_Count = 1 THEN 1 END) * 100.0 / COUNT(*)), 
        2
    ) AS One_Time_Buyers_Percentage
FROM CustomerOrders

-- New Customers Acquired Each Month

;WITH FirstPurchase AS (
    SELECT 
        customer_id,
        MIN(CorrectDate) AS First_Purchase_Date
    FROM Orders
    WHERE CorrectDate IS NOT NULL
    GROUP BY customer_id
)
SELECT 
    FORMAT(First_Purchase_Date, 'yyyy-MM') AS YearMonth,
    COUNT(DISTINCT customer_id) AS New_Customers
FROM FirstPurchase
GROUP BY FORMAT(First_Purchase_Date, 'yyyy-MM')
ORDER BY YearMonth

-- The retention of customers on month on month basis 

WITH Monthly_Customers AS (
    SELECT 
        customer_id,
        FORMAT(CorrectDate, 'yyyy-MM') AS Month
    FROM Orders
    GROUP BY customer_id, FORMAT(CorrectDate, 'yyyy-MM')
),
Retention AS (
    SELECT 
        a.Month AS Current_Month,
        COUNT(DISTINCT a.customer_id) AS Customers_Current,
        COUNT(DISTINCT b.customer_id) AS Retained_Customers
    FROM Monthly_Customers a
    LEFT JOIN Monthly_Customers b
        ON a.customer_id = b.customer_id
       AND DATEADD(MONTH, 1, CAST(a.Month + '-01' AS DATE)) = CAST(b.Month + '-01' AS DATE)
    GROUP BY a.Month
)
SELECT 
    Current_Month,
    Customers_Current,
    Retained_Customers,
    ROUND((CAST(Retained_Customers AS FLOAT) / NULLIF(Customers_Current, 0)) * 100, 2) AS Retention_Rate_Percent
FROM Retention
ORDER BY Current_Month

-- The revenues from existing/new customers on monthly basis

WITH Customer_First_Purchase AS (
    SELECT 
        customer_id,
        MIN(CorrectDate) AS FirstPurchaseDate
    FROM Orders
    GROUP BY customer_id
),
RevenueSplit AS (
    SELECT 
        o.customer_id,
        FORMAT(o.CorrectDate, 'yyyy-MM') AS Month,
        CASE 
            WHEN FORMAT(c.FirstPurchaseDate, 'yyyy-MM') = FORMAT(o.CorrectDate, 'yyyy-MM') THEN 'New Customer'
            ELSE 'Existing Customer'
        END AS Customer_Type,
        SUM(o.Total_Amount) AS Revenue
    FROM Orders o
    JOIN Customer_First_Purchase c ON o.customer_id = c.customer_id
    GROUP BY 
        o.customer_id, 
        FORMAT(o.CorrectDate, 'yyyy-MM'),
        CASE 
            WHEN FORMAT(c.FirstPurchaseDate, 'yyyy-MM') = FORMAT(o.CorrectDate, 'yyyy-MM') THEN 'New Customer'
            ELSE 'Existing Customer'
        END
)
SELECT 
    Month,
    Customer_Type,
    SUM(Revenue) AS Total_Revenue
FROM RevenueSplit
GROUP BY Month, Customer_Type
ORDER BY Month, Customer_Type

-- Sales Trend by Category, Region, Store, Channel, Payment Method

SELECT 
    FORMAT(o.CorrectDate, 'yyyy-MM') AS Month,
    p.Category AS Product_Category,
    s.Region AS Store_Region,
    s.StoreID,
    o.Channel,
    op.payment_type,
    SUM(o.Total_Amount) AS Total_Sales,
    SUM(o.Quantity) AS Total_Quantity
FROM Orders o
LEFT JOIN Product_info p 
    ON o.Product_ID = p.Product_ID
LEFT JOIN stores_info s 
    ON o.Delivered_StoreID = s.StoreID
LEFT JOIN OrderPayments op 
    ON o.Order_ID = op.Order_ID
GROUP BY 
    FORMAT(o.CorrectDate, 'yyyy-MM'),
    p.Category,
    s.Region,
    s.StoreID,
    o.Channel,
    op.payment_type
ORDER BY 
    FORMAT(o.CorrectDate, 'yyyy-MM'),
    p.Category,
    s.Region,
    s.StoreID,
    o.Channel,
    op.payment_type

-- Popular categories/Popular Products by store, state, region. 

SELECT
    s.Region,
    s.seller_state,
    s.StoreID,
    p.Category AS Product_Category,
    p.product_id,
    SUM(o.Quantity) AS Total_Quantity_Sold,
    SUM(o.Total_Amount) AS Total_Sales,
    RANK() OVER (
        PARTITION BY s.Region, s.seller_state, s.StoreID
        ORDER BY SUM(o.Quantity) DESC
    ) AS Category_Rank
FROM Orders o
LEFT JOIN Product_info p 
    ON o.Product_ID = p.Product_ID
LEFT JOIN stores_info s 
    ON o.Delivered_StoreID = s.StoreID
GROUP BY 
    s.Region,
    s.seller_state,
    s.StoreID,
    p.Category,
    p.product_id
ORDER BY 
    s.Region,
    s.seller_state,Total_Quantity_Sold Desc,
    Category_Rank

-- List the top 10 most expensive products sorted by price and their contribution to sales

WITH ProductSales AS (
    SELECT 
        o.Product_ID,
        p.Category,
        MAX(o.Cost_Per_Unit) AS Price,          -- Highest price per product
        SUM(o.Total_Amount) AS Total_Sales
    FROM Orders o
    LEFT JOIN Product_info p 
        ON o.Product_ID = p.Product_ID
    GROUP BY 
        o.Product_ID,
        p.Category
),
TotalSales AS (
    SELECT SUM(Total_Sales) AS Overall_Sales FROM ProductSales
)
SELECT 
    ps.Product_ID,
    ps.Category,
    ps.Price,
    ps.Total_Sales,
    ROUND((ps.Total_Sales / ts.Overall_Sales) * 100, 2) AS Contribution_Percentage
FROM ProductSales ps
CROSS JOIN TotalSales ts
WHERE ps.Price IS NOT NULL
ORDER BY ps.Price DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY

-- Products Appearing in Transactions.

SELECT DISTINCT 
    o.Product_ID,
    p.Category
FROM Orders o
LEFT JOIN Product_info p 
    ON o.Product_ID = p.Product_ID
WHERE o.Product_ID IS NOT NULL
ORDER BY p.Category, o.Product_ID

--- Top 10-performing & worst 10 performance stores in terms of sales

WITH StoreSales AS (
    SELECT 
        s.StoreID,
        s.seller_city,
        s.seller_state,
        s.Region,
        SUM(o.Total_Amount) AS Total_Sales
    FROM Orders o
    LEFT JOIN stores_info s 
        ON o.Delivered_StoreID = s.StoreID
    GROUP BY 
        s.StoreID, s.seller_city, s.seller_state, s.Region
)
-- 🔹 Top 10 & Bottom 10 in one result
SELECT 
    'Bottom 10' AS Category,
    StoreID,
    seller_city,
    seller_state,
    Region,
    Total_Sales
FROM (
    SELECT TOP 10 * FROM StoreSales ORDER BY Total_Sales ASC
) AS BottomStores

UNION ALL

SELECT 
    'Top 10' AS Category,
    StoreID,
    seller_city,
    seller_state,
    Region,
    Total_Sales
FROM (
    SELECT TOP 10 * FROM StoreSales ORDER BY Total_Sales DESC
) AS TopStores
ORDER BY Category, Total_Sales DESC


-------====================== Customer Behaviour ==============---------------------

-----== Customer Based on Revenue

WITH CustomerRevenue AS (
    SELECT 
        o.Customer_ID,
        SUM(o.Total_Amount) AS Total_Revenue
    FROM Orders o
    GROUP BY o.Customer_ID
)
SELECT 
    c.Custid,
    c.Customer_City,
    c.Customer_State,
    cr.Total_Revenue,
    CASE
        WHEN cr.Total_Revenue >= 6000 THEN 'High Value'
        WHEN cr.Total_Revenue BETWEEN 3000 AND 5999 THEN 'Medium Value'
        ELSE 'Low Value'
    END AS Customer_Segment
FROM CustomerRevenue cr
LEFT JOIN Customers c 
    ON cr.Customer_ID = c.Custid
ORDER BY cr.Total_Revenue DESC

-----====== Sales And Sales Contribution By Rfm Segment

WITH CustomerSummary AS (
    SELECT 
        o.Customer_ID,
        MAX(o.CorrectDate) AS Last_Purchase_Date,
        COUNT(DISTINCT o.Order_ID) AS Frequency,
        SUM(o.Total_Amount) AS Monetary
    FROM Orders o
    GROUP BY o.Customer_ID
),
RFM_Scored AS (
    SELECT
        cs.Customer_ID,
        DATEDIFF(DAY, cs.Last_Purchase_Date, (SELECT MAX(CorrectDate) FROM Orders)) AS Recency,
        cs.Frequency,
        cs.Monetary
    FROM CustomerSummary cs
),
RFM_Ranked AS (
    SELECT
        Customer_ID,
        Recency,
        Frequency,
        Monetary,
        NTILE(4) OVER (ORDER BY Recency ASC) AS R_Score,   -- lower recency = better
        NTILE(4) OVER (ORDER BY Frequency DESC) AS F_Score, -- higher frequency = better
        NTILE(4) OVER (ORDER BY Monetary DESC) AS M_Score   -- higher spending = better
    FROM RFM_Scored
),
RFM_Final AS (
    SELECT 
        Customer_ID,
        Recency,
        Frequency,
        Monetary,
        R_Score,
        F_Score,
        M_Score,
        (R_Score + F_Score + M_Score) AS RFM_Score,
        CASE
            WHEN (R_Score + F_Score + M_Score) >= 10 THEN 'Premium'
            WHEN (R_Score + F_Score + M_Score) BETWEEN 7 AND 9 THEN 'Gold'
            WHEN (R_Score + F_Score + M_Score) BETWEEN 4 AND 6 THEN 'Silver'
            ELSE 'Standard'
        END AS Customer_Segment
    FROM RFM_Ranked
)
SELECT 
    f.Customer_ID,
    f.Recency,
    f.Frequency,
    f.Monetary,
    f.RFM_Score,
    f.Customer_Segment
FROM RFM_Final f
ORDER BY f.RFM_Score DESC

---===== the number of customers who purchased in all the channels and find the key metrics.

WITH CrossChannelCustomers AS (
    SELECT 
        customer_id
    FROM Orders
    GROUP BY customer_id
    HAVING COUNT(DISTINCT channel) = (SELECT COUNT(DISTINCT channel) FROM Orders)
)
SELECT
    c.customer_id,
    COUNT(DISTINCT o.order_id)        AS total_orders,
    SUM(o.quantity)                   AS total_quantity,
    SUM(o.total_amount)               AS total_sales,
    ROUND(AVG(o.total_amount), 2)     AS avg_order_value,
    MIN(o.correctdate)                AS first_purchase_date,
    MAX(o.correctdate)                AS last_purchase_date
FROM CrossChannelCustomers c
JOIN Orders o
  ON o.customer_id = c.customer_id
GROUP BY c.customer_id
ORDER BY total_sales DESC

-----========= the behavior of one time buyers and repeat buyers

WITH CustomerOrderStats AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS total_orders,
        SUM(total_amount)        AS total_sales,
        SUM(quantity)            AS total_quantity,
        AVG(total_amount)        AS avg_order_value
    FROM Orders
    GROUP BY customer_id
),
CustomerType AS (
    SELECT
        customer_id,
        CASE 
            WHEN total_orders = 1 THEN 'One-time Buyer'
            ELSE 'Repeat Buyer'
        END AS buyer_type,
        total_orders,
        total_sales,
        total_quantity,
        avg_order_value
    FROM CustomerOrderStats
)
SELECT
    buyer_type,
    COUNT(DISTINCT customer_id)              AS num_customers,
    SUM(total_orders)                        AS total_orders,
    SUM(total_quantity)                      AS total_quantity,
    SUM(total_sales)                         AS total_sales,
    ROUND(AVG(total_sales), 2)               AS avg_sales_per_customer,
    ROUND(AVG(avg_order_value), 2)           AS avg_order_value,
    ROUND(AVG(total_orders), 2)              AS avg_orders_per_customer,
    ROUND(SUM(total_sales) * 100.0 / 
          (SELECT SUM(total_sales) FROM CustomerType), 2) AS contribution_to_total_sales_percent
FROM CustomerType
GROUP BY buyer_type
ORDER BY total_sales DESC


----======= discount seekers & non discount seekers

WITH CustomerDiscountStats AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS total_orders,
        SUM(total_amount)        AS total_sales,
        SUM(quantity)            AS total_quantity,
        SUM(discount)            AS total_discount,
        CASE 
            WHEN SUM(discount) > 0 THEN 'Discount Seeker'
            ELSE 'Non-Discount Seeker'
        END AS customer_type
    FROM Orders
    GROUP BY customer_id
)
SELECT
    customer_type,
    COUNT(DISTINCT customer_id)                 AS num_customers,
    SUM(total_orders)                           AS total_orders,
    SUM(total_quantity)                         AS total_quantity,
    SUM(total_sales)                            AS total_sales,
    SUM(total_discount)                         AS total_discount_given,
    ROUND(AVG(total_sales), 2)                  AS avg_sales_per_customer,
    ROUND(AVG(total_discount), 2)               AS avg_discount_per_customer,
    ROUND(SUM(total_sales) * 100.0 / 
          (SELECT SUM(total_sales) FROM CustomerDiscountStats), 2) AS contribution_to_total_sales_percent,
    ROUND(SUM(total_discount) * 100.0 / 
          (SELECT SUM(total_discount) FROM CustomerDiscountStats WHERE total_discount > 0), 2) AS share_of_total_discount_percent
FROM CustomerDiscountStats
GROUP BY customer_type
ORDER BY total_sales DESC

--== preferences of customers (preferred channel, Preferred payment method, preferred store, discount preference, preferred categories

-- Preferred Channel per Customer
WITH ChannelPref AS (
    SELECT 
        customer_id, 
        channel,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY COUNT(*) DESC) AS rn
    FROM Orders
    GROUP BY customer_id, channel
),
PaymentPref AS (
    SELECT 
        o.customer_id, 
        op.payment_type AS payment_method,
        ROW_NUMBER() OVER (PARTITION BY o.customer_id ORDER BY COUNT(*) DESC) AS rn
    FROM Orders o
    JOIN OrderPayments op ON o.order_id = op.order_id
    GROUP BY o.customer_id, op.payment_type
),
StorePref AS (
    SELECT 
        customer_id, 
        delivered_storeid,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY COUNT(*) DESC) AS rn
    FROM Orders
    GROUP BY customer_id, delivered_storeid
),
CategoryPref AS (
    SELECT 
        o.customer_id, 
        p.category,
        ROW_NUMBER() OVER (PARTITION BY o.customer_id ORDER BY COUNT(*) DESC) AS rn
    FROM Orders o
    JOIN Product_info p ON o.product_id = p.product_id
    GROUP BY o.customer_id, p.category
),
DiscountStats AS (
    SELECT 
        customer_id,
        ROUND(AVG(discount), 2) AS avg_discount_used,
        CASE 
            WHEN AVG(discount) > 0 THEN 'Discount Lover'
            ELSE 'Non-Discount Buyer'
        END AS discount_preference
    FROM Orders
    GROUP BY customer_id
)
SELECT 
    c.customer_id,
    ch.channel AS preferred_channel,
    pm.payment_method AS preferred_payment_method,
    st.delivered_storeid AS preferred_store,
    ct.category AS preferred_category,
    ds.avg_discount_used,
    ds.discount_preference
FROM (SELECT DISTINCT customer_id FROM Orders) c
LEFT JOIN ChannelPref ch ON c.customer_id = ch.customer_id AND ch.rn = 1
LEFT JOIN PaymentPref pm ON c.customer_id = pm.customer_id AND pm.rn = 1
LEFT JOIN StorePref st ON c.customer_id = st.customer_id AND st.rn = 1
LEFT JOIN CategoryPref ct ON c.customer_id = ct.customer_id AND ct.rn = 1
LEFT JOIN DiscountStats ds ON c.customer_id = ds.customer_id
ORDER BY c.customer_id

--=== purchased one category and purchased multiple categories

WITH CustomerCategoryCount AS (
    SELECT 
        o.Customer_ID,
        COUNT(DISTINCT p.Category) AS Category_Count,
        SUM(o.Total_Amount) AS Total_Revenue,
        COUNT(DISTINCT o.Order_ID) AS Total_Orders,
        SUM(o.Quantity) AS Total_Quantity
    FROM Orders o
    JOIN Product_info p 
        ON o.Product_ID = p.Product_ID
    GROUP BY o.Customer_ID
)
SELECT 
    CASE 
        WHEN Category_Count = 1 THEN 'Single Category Buyers'
        ELSE 'Multi Category Buyers'
    END AS Customer_Type,
    COUNT(DISTINCT Customer_ID) AS Customer_Count,
    SUM(Total_Revenue) AS Total_Revenue,
    SUM(Total_Orders) AS Total_Orders,
    SUM(Total_Quantity) AS Total_Quantity,
    ROUND(AVG(Total_Revenue), 2) AS Avg_Revenue_per_Customer,
    ROUND(AVG(Total_Orders), 2) AS Avg_Orders_per_Customer
FROM CustomerCategoryCount
GROUP BY 
    CASE 
        WHEN Category_Count = 1 THEN 'Single Category Buyers'
        ELSE 'Multi Category Buyers'
    END
ORDER BY Customer_Count DESC

----=============================Cross-Selling==========================

-- Top 10 category pairs that are most frequently bought together
SELECT top 10
    c1.Category AS Category_1,
    c2.Category AS Category_2,
    COUNT(DISTINCT o1.Order_ID) AS Times_Bought_Together
FROM Orders o1
JOIN Product_info c1 
    ON o1.Product_ID = c1.Product_ID
JOIN Orders o2 
    ON o1.Order_ID = o2.Order_ID 
    AND o1.Product_ID < o2.Product_ID   -- Prevent duplicate/reverse pairs
JOIN Product_info c2 
    ON o2.Product_ID = c2.Product_ID
WHERE c1.Category <> c2.Category         -- Exclude same-category pairs
GROUP BY c1.Category, c2.Category
ORDER BY Times_Bought_Together DESC

---===Top 10 combinations of 3 product Category are selling together in each transaction

SELECT TOP 10
    p1.Category AS Category_1,
    p2.Category AS Category_2,
    p3.Category AS Category_3,
    COUNT(DISTINCT o1.Order_ID) AS Times_Bought_Together
FROM Orders o1
JOIN Product_info p1 
    ON o1.Product_ID = p1.Product_ID
JOIN Orders o2 
    ON o1.Order_ID = o2.Order_ID 
    AND o1.Product_ID < o2.Product_ID
JOIN Product_info p2 
    ON o2.Product_ID = p2.Product_ID
JOIN Orders o3 
    ON o1.Order_ID = o3.Order_ID 
    AND o2.Product_ID < o3.Product_ID
JOIN Product_info p3 
    ON o3.Product_ID = p3.Product_ID
WHERE 
    p1.Category <> p2.Category
    AND p2.Category <> p3.Category
    AND p1.Category <> p3.Category
GROUP BY 
    p1.Category, p2.Category, p3.Category
ORDER BY 
    Times_Bought_Together DESC

---------=============== Understand the Category Behavior===========--

----=== Total Sales & Percentage of sales by category
SELECT 
    p.Category,
    SUM(o.New_Total_Amount) AS Total_Sales,
    ROUND(
        (SUM(o.New_Total_Amount) * 100.0 / 
        (SELECT SUM(New_Total_Amount) FROM Orders)), 2
    ) AS Percentage_of_Sales
FROM Orders o
JOIN Product_info p 
    ON o.Product_ID = p.Product_ID
GROUP BY p.Category
ORDER BY Total_Sales DESC

-----== Most profitable category and its contribution

WITH CategoryProfit AS (
    SELECT 
        p.Category,
        SUM(o.New_Total_Amount - (o.Cost_Per_Unit * o.Quantity)) AS Total_Profit
    FROM Orders o
    JOIN Product_info p 
        ON o.Product_ID = p.Product_ID
    GROUP BY p.Category
)
SELECT 
    Category,
    Total_Profit,
    ROUND(
        (Total_Profit * 100.0 / SUM(Total_Profit) OVER ()), 2
    ) AS Profit_Contribution_Percentage
FROM CategoryProfit
ORDER BY Total_Profit DESC

---=== Category Penetration Analysis by month on month

--(Category Penetration = number of orders containing the category/number of orders)

WITH MonthlyOrders AS (
    SELECT 
        FORMAT(o.CorrectDate, 'yyyy-MM') AS Month,
        COUNT(DISTINCT o.Order_ID) AS Total_Orders
    FROM Orders o
    GROUP BY FORMAT(o.CorrectDate, 'yyyy-MM')
),
CategoryOrders AS (
    SELECT 
        FORMAT(o.CorrectDate, 'yyyy-MM') AS Month,
        p.Category,
        COUNT(DISTINCT o.Order_ID) AS Category_Order_Count
    FROM Orders o
    JOIN Product_info p 
        ON o.Product_ID = p.Product_ID
    GROUP BY FORMAT(o.CorrectDate, 'yyyy-MM'), p.Category
)
SELECT 
    c.Month,
    c.Category,
    c.Category_Order_Count,
    m.Total_Orders,
    ROUND((c.Category_Order_Count * 100.0 / m.Total_Orders), 2) AS Category_Penetration_Percentage
FROM CategoryOrders c
JOIN MonthlyOrders m 
    ON c.Month = m.Month
ORDER BY c.Month, Category_Penetration_Percentage DESC


--= Cross Category Analysis by month on Month (In Every Bill, how many categories shopped. Need to calculate average number of categories shopped in each bill by Region, By State

---- State Wise

SELECT
    CONCAT(YEAR(o.CorrectDate), '-', 
           RIGHT('0' + CAST(MONTH(o.CorrectDate) AS VARCHAR(2)), 2)) AS Month_Year,
    s.Seller_State,
    ROUND(AVG(CategoryCountPerOrder.Num_Categories), 2) AS Avg_Categories_Per_Order
FROM (
    SELECT 
        o.Order_ID,
        COUNT(DISTINCT p.Category) AS Num_Categories
    FROM Orders o
    JOIN Product_info p 
        ON o.Product_ID = p.Product_ID
    GROUP BY o.Order_ID
) AS CategoryCountPerOrder
JOIN Orders o 
    ON CategoryCountPerOrder.Order_ID = o.Order_ID
JOIN Stores_Info s 
    ON o.Delivered_StoreID = s.StoreID
GROUP BY 
    YEAR(o.CorrectDate),
    MONTH(o.CorrectDate),
    s.Seller_State
ORDER BY 
    YEAR(o.CorrectDate),
    MONTH(o.CorrectDate),
    s.Seller_State



----=== Region Wise


SELECT
    CONCAT(YEAR(o.CorrectDate), '-', 
           RIGHT('0' + CAST(MONTH(o.CorrectDate) AS VARCHAR(2)), 2)) AS Month_Year,
    s.Region AS Seller_Region,
    ROUND(AVG(CategoryCountPerOrder.Num_Categories), 2) AS Avg_Categories_Per_Order
FROM (
    SELECT 
        o.Order_ID,
        COUNT(DISTINCT p.Category) AS Num_Categories
    FROM Orders o
    JOIN Product_info p 
        ON o.Product_ID = p.Product_ID
    GROUP BY o.Order_ID
) AS CategoryCountPerOrder
JOIN Orders o 
    ON CategoryCountPerOrder.Order_ID = o.Order_ID
JOIN Stores_Info s 
    ON o.Delivered_StoreID = s.StoreID
GROUP BY 
    YEAR(o.CorrectDate),
    MONTH(o.CorrectDate),
    s.Region
ORDER BY 
    YEAR(o.CorrectDate),
    MONTH(o.CorrectDate),
    s.Region

----=== POPULAR CATEGORY DURING FIRST PURCHASE

    WITH FirstPurchase AS (
    SELECT 
        o.Customer_ID,
        MIN(o.CorrectDate) AS First_Purchase_Date
    FROM Orders o
    GROUP BY o.Customer_ID
),
FirstPurchaseDetails AS (
    SELECT 
        fp.Customer_ID,
        p.Category,
        o.Order_ID,
        o.CorrectDate
    FROM Orders o
    JOIN Product_info p 
        ON o.Product_ID = p.Product_ID
    JOIN FirstPurchase fp 
        ON o.Customer_ID = fp.Customer_ID
       AND o.CorrectDate = fp.First_Purchase_Date
)
SELECT 
    fpd.Category,
    COUNT(DISTINCT fpd.Customer_ID) AS No_Of_Customers,
    COUNT(DISTINCT fpd.Order_ID) AS No_Of_Orders
FROM FirstPurchaseDetails fpd
GROUP BY fpd.Category
ORDER BY No_Of_Customers DESC

    
-----======= CUSTOMER SATISFACTION ===========---

--======================== maximum rated & minimum rated and average rating score


---=====AVERAGE RATING BY MONTH

SELECT
    CONCAT(YEAR(o.CorrectDate), '-', 
           RIGHT('0' + CAST(MONTH(o.CorrectDate) AS VARCHAR(2)), 2)) AS Month_Year,
    ROUND(AVG(r.Customer_Satisfaction_Score), 2) AS Avg_Rating,
    COUNT(r.Customer_Satisfaction_Score) AS Total_Reviews
FROM Orders o
JOIN OrderReview_Ratings r 
    ON o.Order_ID = r.Order_ID
WHERE r.Customer_Satisfaction_Score IS NOT NULL
GROUP BY 
    YEAR(o.CorrectDate),
    MONTH(o.CorrectDate)
ORDER BY 
    YEAR(o.CorrectDate),
    MONTH(o.CorrectDate)

--======AVERAGE RATING BY CATEGORY

SELECT
    p.Category,
    ROUND(AVG(r.Customer_Satisfaction_Score), 2) AS Avg_Rating,
    COUNT(r.Customer_Satisfaction_Score) AS Total_Reviews
FROM Orders o
JOIN Product_info p 
    ON o.Product_ID = p.Product_ID
JOIN OrderReview_Ratings r 
    ON o.Order_ID = r.Order_ID
WHERE r.Customer_Satisfaction_Score IS NOT NULL
GROUP BY 
    p.Category
ORDER BY 
    Avg_Rating DESC


--== AVERAGE RATING BY STATE

SELECT
    c.Customer_State,
    ROUND(AVG(r.Customer_Satisfaction_Score), 2) AS Avg_Rating,
    COUNT(r.Customer_Satisfaction_Score) AS Total_Reviews
FROM Orders o
JOIN Customers c 
    ON o.Customer_ID = c.Custid
JOIN OrderReview_Ratings r 
    ON o.Order_ID = r.Order_ID
WHERE r.Customer_Satisfaction_Score IS NOT NULL
GROUP BY 
    c.Customer_State
ORDER BY 
    Avg_Rating DESC

--== AVERAGE RATING BY Store

SELECT
    o.Delivered_StoreID AS Store_ID,
    ROUND(AVG(r.Customer_Satisfaction_Score), 2) AS Avg_Rating,
    COUNT(r.Customer_Satisfaction_Score) AS Total_Reviews
FROM Orders o
JOIN OrderReview_Ratings r 
    ON o.Order_ID = r.Order_ID
WHERE r.Customer_Satisfaction_Score IS NOT NULL
GROUP BY 
    o.Delivered_StoreID
ORDER BY 
    Avg_Rating DESC


---=============== Perform cohort analysis  ================-

WITH FirstPurchase AS (
    SELECT 
        Customer_ID,
        FORMAT(MIN(CorrectDate), 'yyyy-MM') AS Cohort_Month
    FROM Orders
    GROUP BY Customer_ID
),
CustomerOrders AS (
    SELECT 
        o.Customer_ID,
        FORMAT(o.CorrectDate, 'yyyy-MM') AS Order_Month,
        SUM(o.New_Total_Amount) AS Revenue,
        COUNT(DISTINCT o.Order_ID) AS Total_Orders
    FROM Orders o
    GROUP BY o.Customer_ID, FORMAT(o.CorrectDate, 'yyyy-MM')
),
Combined AS (
    SELECT 
        f.Customer_ID,
        f.Cohort_Month,
        c.Order_Month,
        c.Revenue,
        c.Total_Orders,
        DATEDIFF(MONTH, 
                 CAST(f.Cohort_Month + '-01' AS date), 
                 CAST(c.Order_Month + '-01' AS date)) AS Months_Since_Cohort
    FROM FirstPurchase f
    JOIN CustomerOrders c
        ON f.Customer_ID = c.Customer_ID
),
CohortStats AS (
    SELECT 
        Cohort_Month,
        COUNT(DISTINCT Customer_ID) AS Cohort_Customers,
        COUNT(DISTINCT CASE WHEN Months_Since_Cohort > 0 THEN Customer_ID END) AS Repeat_Customers,
        ROUND(
            100.0 * COUNT(DISTINCT CASE WHEN Months_Since_Cohort > 0 THEN Customer_ID END)
            / COUNT(DISTINCT Customer_ID), 2
        ) AS Retention_Rate,
        ROUND(
            AVG(CASE WHEN Months_Since_Cohort > 0 THEN Months_Since_Cohort END), 2
        ) AS Avg_Months_to_Repeat,
        SUM(CASE WHEN Months_Since_Cohort = 0 THEN Total_Orders END) AS Total_Orders_Cohort_Customers,
        SUM(CASE WHEN Months_Since_Cohort = 0 THEN Revenue END) AS Total_Revenue_Cohort_Customers,
        SUM(CASE WHEN Months_Since_Cohort > 0 THEN Total_Orders END) AS Total_Orders_Repeat_Customers,
        SUM(CASE WHEN Months_Since_Cohort > 0 THEN Revenue END) AS Total_Revenue_Repeat_Customers
    FROM Combined
    GROUP BY Cohort_Month
)
SELECT *
FROM CohortStats
ORDER BY Cohort_Month

-----====================== SALES TREND ANALYSIS ==============

---=== what is the sales amount and contribution in percentage

SELECT 
    FORMAT(CorrectDate, 'yyyy-MM') AS Month,
    SUM(New_Total_Amount) AS Total_Sales,
    ROUND(
        (SUM(New_Total_Amount) * 100.0 / 
         (SELECT SUM(New_Total_Amount) FROM Orders)), 2
    ) AS Percentage_Contribution
FROM Orders
GROUP BY FORMAT(CorrectDate, 'yyyy-MM')
ORDER BY Total_Sales DESC

----============= Sales Trend by Month

SELECT 
    FORMAT(CorrectDate, 'yyyy-MM') AS Month,
    SUM(New_Total_Amount) AS Total_Sales
FROM Orders
GROUP BY FORMAT(CorrectDate, 'yyyy-MM')
ORDER BY FORMAT(CorrectDate, 'yyyy-MM')


-----========== Sales Day Weekdays And Weekends

SELECT 
    DATENAME(WEEKDAY, CorrectDate) AS Day_Name,
    DATEPART(WEEKDAY, CorrectDate) AS Day_Number,
    SUM(New_Total_Amount) AS Total_Sales
FROM Orders
GROUP BY DATENAME(WEEKDAY, CorrectDate), DATEPART(WEEKDAY, CorrectDate)
ORDER BY Day_Number



Select s.seller_city,s.StoreID,sum(o.)/sum(o.Quantity) from stores_info s
left join Orders o on s.StoreID=o.Delivered_StoreID






