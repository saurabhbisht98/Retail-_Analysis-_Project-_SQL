# Retail Data Analysis — End-to-End Business Intelligence Project 📊🛒

## 📌 Overview
A comprehensive, end-to-end retail analytics project covering 6 interconnected datasets (Customers, Products, Stores, Orders, Order Payments, Order Reviews) with ~112,650 orders and 99,441 customers across 535 stores. The project spans the complete analytics lifecycle — from data modeling and quality auditing to advanced customer/store analytics and business recommendations — using SQL, Excel, and Power BI.

## 🎯 Business Problem
The retail client needed deeper insight into sales trends, customer behavior, product/store performance, and marketing impact, while facing data quality issues (a total-amount calculation error, duplicate records, inconsistent formatting) that were affecting financial reporting accuracy.

## 🛠️ Tools & Tech Stack
| Tool | Purpose |
|------|---------|
| SQL Server | Data validation, cleaning, transformations, advanced analysis |
| Excel | Data cleaning, exploratory analysis |
| Power BI | Dashboarding & visualization |

## 🗂️ Data Model
6 relational tables (Customer, Products Info, Store, Orders, Order Payments, Order Review Ratings) connected via an ER diagram, covering ~26 months of data (Sep 2021 – Oct 2023).

## 🔍 Key Work Areas

**1. Data Quality Audit & Cleaning**
- Identified and resolved duplicate records, missing values, inconsistent date formats, and mismatched Order IDs across tables
- Established data cleaning rules (e.g., standardizing timestamps, treating discounts as numeric, unifying currency assumptions)

**2. 360° Analytical Views (built using advanced SQL)**
- **Store 360**: Store-level sales, profitability, payment mix, and category performance
- **Customer 360**: RFM (Recency, Frequency, Monetary) analysis, spend segmentation using `PERCENTILE_CONT`, channel preference, weekday/weekend behavior
- **Orders 360**: Order-level profitability, basket size/value, discount classification, customer feedback linkage

**3. Exploratory Data Analysis**
- Revenue, cost, profit, and discount breakdowns
- New customer acquisition & retention trends (month-on-month)
- Regional/state/category-wise sales analysis
- Top/bottom performing stores and products

**4. Customer Behavior & Segmentation**
- RFM-based customer segmentation (Gold/Silver/Premium/Standard tiers) using `NTILE()`
- Discount-seeker vs. non-discount-seeker analysis
- One-time vs. repeat buyer analysis
- Gender-based purchasing pattern analysis

**5. Advanced Analytics**
- **Cross-selling analysis**: Identified top product category combinations frequently bought together
- **Pareto (80/20) analysis**: Found that ~50% of categories drive ~80% of total sales
- **Category penetration analysis**: Tracked category popularity trends month-over-month
- **Cohort analysis**: Fixed-month retention cohorts to measure customer retention rate and repeat-purchase timing

## 💡 Key Business Insights
- South region contributes **~71–75% of total profit** — highest-performing region
- **Female customers (69K+)** outnumber male customers and contribute more to revenue
- **99.96% of customers are one-time buyers** — a major retention opportunity
- Top-selling categories: **Toys & Gifts, Baby, Home Appliances** — together driving the bulk of Pareto-analyzed revenue
- Credit Card is the dominant payment method (~74K orders)

## 📈 Recommendations Delivered
- Introduce loyalty/retention programs to convert one-time buyers into repeat customers
- Focus marketing spend on South region and top-performing categories (Toys & Gifts, Home Appliances)
- Target "Silver/Standard" RFM segments with personalized offers to move them up-tier
- Optimize discount strategy — non-discount seekers show higher average order value

## 📂 Files
- `SQLQuery1.sql` — SQL queries for data cleaning, 360° views, RFM segmentation, cohort & Pareto analysis
- `Retail data.pptx` — Full project presentation with methodology, data quality findings, and business insights
