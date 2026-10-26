# Data dictionary

Tables in the `dw` (warehouse) schema of the `ne_housing` database.

## fact_sales
One row per valid residential property sale.

| Column | Type | Description |
|---|---|---|
| sale_key | int | Surrogate key |
| transaction_id | varchar(36) | Land Registry transaction ID (without braces), unique |
| date_key | int | Sale date as yyyymmdd, links to `dim_date` |
| location_key | int | Links to `dim_location` |
| property_type_key | int | Links to `dim_property_type` |
| tenure_key | int | Links to `dim_tenure` |
| price | int | Sale price in GBP |
| is_new_build | bit | 1 = new build, 0 = existing |
| build_status | varchar(10) | "New build" or "Existing" |
| postcode | varchar(8) | Standardised postcode (house number and street deliberately not kept) |
| postcode_district | varchar(4) | Outward code, e.g. NE1 |
| epc_matched | bit | 1 if matched to an EPC certificate |
| epc_match_tier | tinyint | Match method (1 to 3), null if unmatched |
| floor_area_m2 | decimal(8,2) | From the matched EPC, null if unmatched |
| energy_rating | char(1) | A to G from the matched EPC, null if unmatched |
| price_per_sqm | decimal(10,2) | Price divided by floor area, GBP 100 to 10,000 only |

The EPC columns are empty in this version because EPC data was not loaded.

## fact_affordability
One row per district per year.

| Column | Type | Description |
|---|---|---|
| location_key | int | Links to `dim_location` |
| ratio_year | int | Year of the ratio |
| date_key | int | 1 January of the year, links to `dim_date` |
| price_earnings_ratio | decimal(9,3) | Median house price divided by median residence-based earnings |
| source_label | varchar(100) | Column heading as published by ONS |

## dim_date
One row per day, 2015 to 2027. Includes `year_num`, `quarter_num`, `year_quarter`, `month_num`, `month_name`, `month_short`, `year_month`, `month_start`, `day_name`, `is_weekend`.

## dim_location
One row per local authority: `ons_code`, `district_name`, `lr_district` (Land Registry spelling), `sub_region` (County Durham, Northumberland, Tees Valley, Tyne and Wear), `la_type`, `region`.

## dim_property_type
Detached, Semi-detached, Terraced, Flat/Maisonette, with `type_group` (House or Flat) and `sort_order`.

## dim_tenure
Freehold, Leasehold, Unknown.

## Aggregates and views
| Object | Description |
|---|---|
| `agg_district_month` | Monthly median, mean and sales count per district |
| `agg_district_rolling12` | Rolling 12-month median per district (latest month excluded as incomplete) |
| `v_district_year` | Annual median per district with prior year and year-on-year change (`LAG`) and a partial-year flag |
| `v_district_growth_rank` | Growth from the first to the last complete year, compound annual growth rate and `RANK` |

## Cleaning layer (`clean` schema)
| Object | Description |
|---|---|
| `pp_typed` | All North East sales, typed, each with a `reject_reason` (null = kept) |
| `sales` | View of `pp_typed` where `reject_reason` is null |
| `ratio` | ONS ratio in long format (district, year, value) |
| `ref_district` | The 12 districts with ONS codes and Land Registry spellings |
