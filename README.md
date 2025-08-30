# Airbnb Data Pipeline (dbt + Snowflake)

A complete, production-style dbt project that transforms raw Airbnb data in Snowflake into cleansed dimensions, facts, and marts—with tests, docs, snapshots, seeds, and incremental models.

## Table of Contentss

- [Architecture & Flow](#architecture--flow)
- [Project Structure](#project-structure)
- [Environment Setup (dbt Core)](#environment-setup-dbt-core)
- [Snowflake Profile](#snowflake-profile)
- [Packages](#packages)
- [Sources](#sources)
- [Staging (src) Models](#staging-src-models)
- [Dimension Models](#dimension-models)
- [Fact Models](#fact-models)
- [Seeds & Marts](#seeds--marts)
- [Snapshots (SCD Type 2 on Raw Listings)](#snapshots-scd-type-2-on-raw-listings)
- [Testing Strategy](#testing-strategy)
- [Project Documentation (dbt docs)](#project-documentation-dbt-docs)
- [Variables & Configuration](#variables--configuration)
- [How to Run](#how-to-run)
- [Advanced Usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)
- [Why These Choices?](#why-these-choices)

## Architecture & Flow

**Source (Snowflake RAW schema) → Staging (src models) → Dimensions (dim) → Facts (fct) → Marts**

We also use snapshots to track source changes over time and seeds to enrich data (e.g., full moon dates).

**High-level lineage:**

```
AIRBNB.RAW.RAW_LISTINGS ┐
AIRBNB.RAW.RAW_HOSTS     ├─> src models ─> dim_* ─┐
AIRBNB.RAW.RAW_REVIEWS  ┘                          ├─> fct_reviews ─> marts
Seed: full_moon_dates  ────────────────────────────┘
```

## Project Structure

```
.
├─ models/
│  ├─ src/                          # Staging models (from sources)
│  │  ├─ src_listings.sql
│  │  ├─ src_hosts.sql
│  │  └─ src_reviews.sql
│  ├─ dim/                          # Cleansed dimensions
│  │  ├─ dim_listings_cleansed.sql
│  │  ├─ dim_hosts_cleansed.sql
│  │  └─ dim_listings_w_hosts.sql
│  ├─ fct/                          # Facts
│  │  └─ fct_reviews.sql
│  ├─ mart/                         # Business-facing marts
│  │  └─ full_moon_reviews.sql
│  ├─ source.yml                    # Source definitions (+ freshness)
│  ├─ schema.yml                    # Model docs + generic tests
│  └─ overview.md                   # Docs page shown in dbt Docs UI
│
├─ tests/
│  ├─ dim_listings_minimum_nights.sql      # Singular test
│  └─ consistent_created_at.sql            # Singular test
│
├─ seeds/
│  └─ seed_full_moon_dates.csv             # Seeded enrichment table
│
├─ snapshots/
│  └─ scd_raw_listings.sql                 # SCD2 snapshot of raw listings
│
├─ macros/
│  └─ positive_value.sql                   # Custom generic test
│
├─ packages.yml
├─ dbt_project.yml
└─ README.md
```

## Environment Setup (dbt Core)

Create a Python virtual environment and install dbt for Snowflake.

```bash

# on Windows PowerShell
 python -m venv .venv
 .\.venv\Scripts\Activate

# install dbt core + snowflake adapter
pip install --upgrade pip
pip install dbt-core dbt-snowflake
```

## Snowflake Profile

dbt Core reads connection settings from  `%USERPROFILE%\.dbt\profiles.yml` (Windows).

```yaml
# ~/.dbt/profiles.yml
dbtlearn:                   # must match `profile:` in dbt_project.yml
  target: dev
  outputs:
    dev:
      type: snowflake
      account: "your-account-here"
      user: "your-username"
      password: "your-password"
      role: "your-role"
      database: "AIRBNB"
      warehouse: "your-warehouse"
      schema: "DEV"
      threads: 4
```

> ⚠️ **Important:** Replace placeholder values with your actual Snowflake credentials.

## Packages

**packages.yml**

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: 1.3.0

  - package: metaplane/dbt_expectations
    version: 0.10.8 # check releases for the latest version
```

**Install:**

```bash
dbt deps
```

## Sources

**models/source.yml**

```yaml
version: 2

sources:
  - name: airbnb
    schema: raw
    tables:
      - name: listings
        identifier: raw_listings

      - name: hosts
        identifier: raw_hosts

      - name: reviews
        identifier: raw_reviews
        loaded_at_field: date
        freshness:
          warn_after: {count: 1, period: hour}
          error_after: {count: 24, period: hour}
```

**Run freshness checks:**

```bash
dbt source freshness
```

## Staging (src) Models

These standardize column names and types, and act as a clean interface to the raw sources.

**models/src/src_listings.sql**

```sql
with  raw_listings as (
    select * from AIRBNB.RAW.RAW_LISTINGS
)

select 
    id as listing_id,
          listing_url,
          name as listing_name,
          room_type,
          minimum_nights,
          host_id,
          price as price_str,
          created_at,
          updated_at
from raw_listings
```

**models/src/src_reviews.sql**

```sql
with raw_reviews as ( select * from AIRBNB.RAW.RAW_REVIEWS)
select listing_id,
       date as review_date ,
       reviewer_name,
       comments as review_text ,
       sentiment as review_sentiment
from raw_reviews
```

**models/src/src_hosts.sql**

```sql
with raw_hosts as (
select * from AIRBNB.RAW.RAW_HOSTS
)

select id as host_id ,
       name as host_name,
       is_superhost,
       created_at,
       updated_at
from raw_hosts
```

## Dimension Models

**models/dim/dim_listings_cleansed.sql**

```sql
{{ config(materialized='view') }}

with src_listings as (
  select * from {{ ref('src_listings') }}
)

select
  listing_id,
  listing_name,
  room_type,
  case when minimum_nights = 0 then 1 else minimum_nights end as minimum_nights,
  host_id,
  replace(price_str, '$')::number(10,2) as price,
  created_at,
  updated_at
from src_listings
```

**models/dim/dim_hosts_cleansed.sql**

```sql
{{ config(materialized='view') }}

with src_hosts as (
  select * from {{ ref('src_hosts') }}
)

select
  host_id,
  nvl(host_name, 'Anonymous') as host_name,
  is_superhost,
  created_at,
  updated_at
from src_hosts
```

**models/dim/dim_listings_w_hosts.sql**

```sql
with l as (
  select * from {{ ref('dim_listings_cleansed') }}
),
h as (
  select * from {{ ref('dim_hosts_cleansed') }}
)
select
  l.listing_id,
  l.listing_name,
  l.room_type,
  l.minimum_nights,
  l.price,
  l.host_id,
  h.host_name,
  h.is_superhost as host_is_superhost,
  l.created_at,
  greatest(l.updated_at, h.updated_at) as updated_at
from l
left join h on h.host_id = l.host_id
```

Defaults (from dbt_project.yml) set dim/ as table, but we override two dims to view for agility and cost.

## Fact Models

**models/fct/fct_reviews.sql** — incremental model with variables and logging:

```sql
{{
  config(
    materialized = 'incremental',
    on_schema_change='fail'
    )
}}

WITH src_reviews AS (
  SELECT * FROM {{ ref('src_reviews') }}
)
SELECT 
  {{ dbt_utils.generate_surrogate_key(['listing_id', 'review_date', 'reviewer_name', 'review_text']) }} as review_id,
  *
FROM src_reviews
WHERE review_text is not null
{% if is_incremental() %}
  {% if var("start_date", False) and var("end_date", False) %}
    {{ log('Loading ' ~ this ~ ' incrementally (start_date: ' ~ var("start_date") ~ ', end_date: ' ~ var("end_date") ~ ')', info=True) }}
    AND review_date >= '{{ var("start_date") }}'
    AND review_date < '{{ var("end_date") }}'
  {% else %}
    AND review_date > (select max(review_date) from {{ this }})
    {{ log('Loading ' ~ this ~ ' incrementally (all missing dates)', info=True)}}
  {% endif %}
{% endif %}
```

**Key Features:**

- **Flexible incremental loading:** Use variables for custom date ranges or default to latest data
- **Logging:** Informative log messages show which incremental strategy is being used
- **Surrogate key:** `generate_surrogate_key` provides a stable, unique identifier
- **Null filtering:** Excludes reviews without text content

**Variable Usage:**

- `start_date` & `end_date`: Load specific date range (format: 'YYYY-MM-DD')
- If variables not provided, defaults to loading all data newer than existing max date

## Seeds & Marts

We enrich reviews with a calendar of full moon dates.

**Seed:** `seeds/seed_full_moon_dates.csv` (headers must include full_moon_date)

**Load seeds:**

```bash
dbt seed
```

**Mart:** `models/mart/full_moon_reviews.sql`

```sql
{{ config(materialized='table') }}

with fct_reviews as (
  select * from {{ ref('fct_reviews') }}
),
full_moon_dates as (
  select * from {{ ref('seed_full_moon_dates') }}
)
select
  r.*,
  case when fm.full_moon_date is null then 'not full moon' else 'full moon' end as is_full_moon
from fct_reviews r
left join full_moon_dates fm
  on (to_date(r.review_date) = dateadd(day, 1, fm.full_moon_date))
```

**Why DATEADD(day, 1, fm.full_moon_date)?**
In this dataset we assume review activity peaks the day after a full moon. The join flags any review occurring on full moon + 1 day.

## Snapshots (SCD Type 2 on Listings_cleansed)

We track source-of-truth changes to listings using a dbt snapshot. It preserves history with dbt_valid_from / dbt_valid_to.

**snapshots/scd_raw_listings.sql**

```sql
{% snapshot scd_raw_listings %}

{{
   config(
       target_schema='DEV',
       unique_key='listing_id',
       strategy='timestamp',
       updated_at='updated_at',
       invalidate_hard_deletes=True
   )
}}

select * FROM {{ ref('dim_listings_cleansed') }}

{% endsnapshot %}
```

**Run snapshots:**

```bash
dbt snapshot
```

This snapshot captures changes in the DIM table. 
## Testing Strategy

We use three layers: built-in dbt tests, a custom generic test, and dbt-expectations package tests. We also added singular tests for business logic.

### 1) Built-in Generic Tests (models/schema.yml)

- `unique`, `not_null` on keys and required columns
- `relationships` for FK → PK integrity
- `accepted_values` for categorical columns

```yaml
version: 2

models:
  - name: dim_listings_cleansed
    description: Cleansed table which contains Airbnb listings.
    columns:
      - name: listing_id
        description: Primary key for the listing
        tests: [unique, not_null]

      - name: host_id
        description: The hosts's id. References the host table.
        tests:
          - not_null
          - relationships:
              to: ref('dim_hosts_cleansed')
              field: host_id

      - name: room_type
        description: Type of the apartment / room
        tests:
          - accepted_values:
              values: ['Entire home/apt', 'Private room', 'Shared room', 'Hotel room']

      - name: minimum_nights
        description: '{{ doc("dim_listing_cleansed__minimum_nights") }}'
        tests:
          - positive_value

  - name: dim_hosts_cleansed
    columns:
      - name: host_id
        tests: [not_null, unique]
      - name: host_name
        tests: [not_null]
      - name: is_superhost
        tests:
          - accepted_values:
              values: ['t', 'f']

  - name: dim_listings_w_hosts
    tests:
      - dbt_expectations.expect_table_row_count_to_equal_other_table:
          compare_model: source('airbnb', 'listings')
    columns:
      - name: price
        tests:
          - dbt_expectations.expect_column_values_to_be_of_type:
              column_type: number
          - dbt_expectations.expect_column_quantile_values_to_be_between:
              quantile: .99
              min_value: 50
              max_value: 500
          - dbt_expectations.expect_column_max_to_be_between:
              max_value: 5000
              config:
                severity: warn

  - name: fct_reviews
    columns:
      - name: listing_id
        tests:
          - relationships:
              to: ref('dim_listings_cleansed')
              field: listing_id
      - name: reviewer_name
        tests: [not_null]
      - name: review_sentiment
        tests:
          - accepted_values:
              values: ['positive', 'neutral', 'negative']
```

### 2) Custom Generic Test (macros/positive_value.sql)

```sql
/* creating a custom generic test */
{% test positive_value(model, column_name) %}
select *
from {{ model }}
where {{ column_name }} < 1
{% endtest %}
```

### 3) dbt-expectations Tests

- Table row count parity (dim_listings_w_hosts vs source listings)
- Type check, quantile bounds, and max bounds for price

### 4) Singular Tests (tests/)

**tests/dim_listings_minimum_nights.sql**

```sql
select *
from {{ ref('dim_listings_cleansed') }}
where minimum_nights < 1
limit 10
```

**tests/consistent_created_at.sql**

```sql
/* Ensure every review_date in fct_reviews is later than listing created_at */
select *
from {{ ref('dim_listings_cleansed') }} l
inner join {{ ref('fct_reviews') }} r
using (listing_id)
where l.created_at >= r.review_date
```

**Run all tests:**

```bash
dbt test
```

## Project Documentation (dbt docs)

**models/overview.md** (rendered in dbt Docs)

```markdown
{% docs __overview__ %}
# Airbnb pipeline

Hey, welcome to our Airbnb pipeline documentation!

Here is the schema of our input data:
![input schema](https://dbtlearn.s3.us-east-2.amazonaws.com/input_schema.png)

{% enddocs %}
```

**Generate & serve docs:**

```bash
dbt docs generate
dbt docs serve
```

If your browser asks for credentials on localhost:8080, another service is using that port. Launch on a different port:

```bash
dbt docs serve --port 8081
```

## Variables & Configuration

The project supports several configuration options and variables for flexible execution:

### dbt Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `start_date` | Start date for incremental fact loading | None | `'2024-01-01'` |
| `end_date` | End date for incremental fact loading | None | `'2024-12-31'` |

**Usage examples:**

```bash
# Load reviews for specific date range
dbt run --models fct_reviews --vars '{"start_date": "2024-01-01", "end_date": "2024-01-31"}'

# Load all new reviews (default behavior)
dbt run --models fct_reviews
```

### Model Configurations

- **Staging models:** Views for fast development and testing
- **Dimension models:** Mix of views (cleansed) and tables (joined) based on usage
- **Fact models:** Incremental for efficient large-scale loading
- **Marts:** Tables for optimized business user queries



## How to Run

### Initial Setup

```bash
# 0) Install dependencies
dbt deps

# 1) Load seed data (first time only)
dbt seed

# 2) Build all models
dbt run

# 3) Create initial snapshots
dbt snapshot

# 4) Run tests
dbt test

# 5) Generate documentation
dbt docs generate
dbt docs serve --port 8081
```

### Development Workflow

```bash
# Build and test everything
dbt build

# Test specific models
dbt test --models dim_listings_cleansed

# Run specific model families
dbt run --models +fct_reviews+  # upstream and downstream of fct_reviews
dbt run --models src_*          # all staging models

```