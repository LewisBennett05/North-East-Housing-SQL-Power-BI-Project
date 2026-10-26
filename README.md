# North East England House Prices: Affordability and Price Drivers

An end-to-end analytics project. Raw HM Land Registry and ONS data is loaded, cleaned and audited in **SQL Server**, modelled as a **star schema**, and presented in a three-page **Power BI** report on how affordable homes are across the North East's 12 local authorities, and how that has changed since 2015.

| | |
|---|---|
| **Question** | Where in the North East is housing most affordable, what drives price differences, and how has that changed since 2015? |
| **Audience** | [TODO: one person and the decision it helps, e.g. "a first-time buyer comparing districts" or "a council housing planner"] |
| **Stack** | SQL Server (T-SQL), SSMS, Power BI Desktop (DAX), Git |
| **Scope** | 12 local authorities, sales from 2015 to [TODO: latest month] |

![Overview page](powerbi/screenshots/overview.png)

## Key findings

[TODO: replace each bracket with a real number from `sql/10_analysis_queries.sql` or the report. Keep 3 to 4 findings. Delete any that you can't support.]

1. **[District]** is the most affordable area at **[x.x]** times local earnings in [year], against **[x.x]** in **[District]**.
2. The regional median price rose from about **£[xxx]k** in 2015 to **£[xxx]k** in [year], an increase of **[xx]%**. **[District]** grew fastest (**[xx]%**) and **[District]** slowest (**[xx]%**).
3. [Something about property type or new builds, e.g. "New builds sold at a median [xx]% premium over existing homes in [District]."]
4. [Anything surprising, e.g. a district that became less affordable, or a gap that widened.]

## Report pages

| Overview | Affordability | Drivers |
|---|---|---|
| ![Overview](powerbi/screenshots/01_overview.png) | ![Affordability](powerbi/screenshots/02_affordability.png) | ![Drivers](powerbi/screenshots/03_drivers.png) |

A PDF export is in [`powerbi/`](powerbi/). The `.pbix` file is included and opens in Power BI Desktop (Windows).

## Data sources

| Source | Provides | Grain |
|---|---|---|
| HM Land Registry, Price Paid Data | Every residential property sale in England and Wales | One row per sale |
| ONS, House price to residence-based earnings ratio | Median house price to earnings ratio | Local authority, annual |

Contains HM Land Registry data (c) Crown copyright and database right [TODO: year]. This data is licensed under the Open Government Licence v3.0.
Contains public sector information licensed under the Open Government Licence v3.0 (ONS).

**Raw data is not included in this repository.** See [How to reproduce](#how-to-reproduce).

## How it works

```
staging (raw, text)  ->  clean (typed, validated, audited)  ->  dw (star schema)  ->  Power BI
```

```mermaid
erDiagram
    dim_date ||--o{ fact_sales : date_key
    dim_location ||--o{ fact_sales : location_key
    dim_property_type ||--o{ fact_sales : property_type_key
    dim_tenure ||--o{ fact_sales : tenure_key
    dim_date ||--o{ fact_affordability : date_key
    dim_location ||--o{ fact_affordability : location_key
```

- **Raw layer:** files are loaded exactly as received, all columns as text, so the source is never altered.
- **Clean layer:** types are converted, postcodes standardised, property types and tenure decoded. Nothing is deleted. Every rejected row is **labelled with a reason**, which gives an audit trail.
- **Warehouse layer:** `fact_sales` (one row per sale) and `fact_affordability` (one row per district per year), with date, location, property type and tenure dimensions.
- **Aggregates:** monthly and rolling 12-month medians are pre-computed in SQL for fast reporting.

Full column definitions are in [`docs/DATA_DICTIONARY.md`](docs/DATA_DICTIONARY.md).

### Cleaning decisions

| Rule | Why | Rows affected |
|---|---|---|
| Category B sales excluded | Repossessions and bulk transfers are not ordinary market sales | [TODO] |
| Price below GBP 10,000 or above GBP 5,000,000 excluded | Token transfers and outliers | [TODO] |
| Property type "other" excluded | Not comparable with houses and flats | [TODO] |
| Duplicate registrations removed | Same address, date and price under different IDs | [TODO] |
| **Rows kept** | | **[TODO] of [TODO] ([xx]%)** |

*(Counts come from the audit summary at the end of `sql/04_clean_price_paid.sql`.)*

### Design choices worth knowing

- **Medians, not averages.** Property prices are right-skewed, so a few expensive sales pull averages up. SQL uses `PERCENTILE_CONT(0.5)` and DAX uses `MEDIAN`.
- **Rolling median needs a month spine.** `PERCENTILE_CONT` does not accept a window frame, so the rolling 12-month median joins each month to the previous 12 months of sales.
- **Affordability is annual and sits at its own grain.** It joins to the date dimension on 1 January of each year and is never joined to individual sales.
- **Filtering on district, not county.** County spellings vary in the Land Registry data, and district maps cleanly to ONS codes.

## Skills demonstrated

- **SQL:** layered ETL, `BULK INSERT`, `TRY_CAST`, CTEs, window functions (`LAG`, `RANK`, `FIRST_VALUE`, `NTILE`), `PERCENTILE_CONT`, dynamic SQL, views, indexes, constraints
- **Data modelling:** star schema, surrogate keys, a date dimension, facts at different grains
- **Power BI:** relationships, DAX (`CALCULATE`, `SAMEPERIODLASTYEAR`, `DIVIDE`, `ALLSELECTED`), slicers and interaction control, dashboard design for a stated audience

## Limitations

- Price Paid covers registered sales only. It excludes rentals and unsold homes, and the mix of homes that sell changes each year.
- ONS affordability data is annual and at local authority level only.
- Small districts have few new-build sales a year, so the new-build premium is volatile.
- **EPC (energy certificate) data was not loaded in this version.** The national dataset is about 90 GB. The scripts include the matching logic (`sql/optional/`), but price per square metre and energy rating analysis are future work.
- Data quality checks are implemented as SQL checks and database constraints, not as dbt tests.
- The latest year is partial, so year-on-year change for that year is not comparable.

## How to reproduce

1. Install SQL Server (Developer edition) and SSMS.
2. Download the Price Paid yearly files from gov.uk, and the ONS workbook. Save the **median, local authority** sheet as CSV with a single heading row.
3. Put the files in a folder SQL Server can read (for example `C:\Housingdata`) and edit the paths at the top of `01_stage_price_paid.sql` and `03_stage_ons_ratio.sql`.
4. Open each script from the `sql/` folder in its own SSMS tab and run them in this order:

| Order | Script | Purpose |
|---|---|---|
| 1 | `00_setup.sql` | Database, schemas, helper functions, district lookup |
| 2 | `01_stage_price_paid.sql` | Load Price Paid files |
| 3 | `02b_epc_placeholder.sql` | Empty EPC table (EPC not loaded) |
| 4 | `03_stage_ons_ratio.sql` | Load ONS ratio CSV |
| 5 | `04_clean_price_paid.sql` | Clean and audit sales |
| 6 | `05_clean_epc_and_ratio.sql` | Clean EPC and ratio |
| 7 | `06_dimensions.sql` | Dimension tables |
| 8 | `07_epc_match.sql` | EPC match (finds nothing without EPC data) |
| 9 | `08_fact_tables.sql` | Fact tables |
| 10 | `05b_fix_ratio.sql` | Rebuild ratio tables and fill `fact_affordability` |
| 11 | `09_aggregates_and_views.sql` | Medians, YoY, growth ranking |
| 12 | `10_analysis_queries.sql` | Analysis queries |
| 13 | `11_data_quality_checks.sql` | Reconciliation and checks |

5. Open `powerbi/*.pbix`, point it at your `ne_housing` database, and refresh.

## Repository structure

```
.
|-- README.md
|-- LICENSE
|-- .gitignore
|-- sql/                numbered scripts (see order above)
|   `-- optional/       EPC loader for the full dataset
|-- powerbi/            .pbix, PDF export, screenshots/
`-- docs/               data dictionary, technical notes
```

## Licence

Code is released under the MIT licence (see `LICENSE`). Data remains under the original Open Government Licence terms of its publishers.
