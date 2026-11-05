# Repo 2: Finance Data Platform — Step-by-Step Build Plan
**Last Updated:** 2026-06-15  
**Project root:** `~/Desktop/git_projects/Stock_analysis/`  
**dbt root:** `~/Desktop/DBT/dbt_project /`

---

## Current State (What Already Exists)

| Component | Status |
|-----------|--------|
| Supabase project | ✅ Live at `uiocdjtwshxpqtlcgfel.supabase.co` |
| `stocks` table | ✅ 560 rows seeded |
| `fundamentals` table | ✅ 560 rows seeded (2026-Q2 snapshot) |
| `price_history` table | ✅ Schema exists — empty, no data yet |
| `portfolio` table | ✅ Schema exists — empty, no positions yet |
| `.env` file | ✅ `SUPABASE_URL` + `SUPABASE_KEY` set. **Missing: `POLYGON_API_KEY`** |
| dbt scaffolded | ✅ `dbt_project.yml` exists — no models yet, profile pointed at Databricks (wrong, needs to be fixed) |
| GitHub repo | ❓ Need to verify if remote exists |

---

## The 5 Phases

```
Phase 1 — Price Fetcher       ingestion/price_fetcher.py
Phase 2 — dbt Layer           dbt models: staging → marts
Phase 3 — Claude Analyzer     analysis/portfolio_analyzer.py
Phase 4 — GitHub Actions      .github/workflows/daily_prices.yml
Phase 5 — Dashboard           dashboard/app.py  (Streamlit + Plotly)
```

---

## Phase 1 — Daily Price Fetcher

**Goal:** Script pulls OHLCV data for all 560 tickers from Polygon.io and upserts into Supabase `price_history`. Should be runnable any time; re-runs are safe.

---

### Step 1.1 — Get Polygon.io API Key

1. Go to [polygon.io](https://polygon.io) → sign up for free tier
2. Dashboard → API Keys → copy your key
3. Open `~/Desktop/git_projects/Stock_analysis/.env`
4. Add this line:
   ```
   POLYGON_API_KEY=your_key_here
   ```
5. **Do not commit this file.** It's already in `.gitignore` — you're covered.

**Free tier limit:** 5 API calls/minute. The grouped daily bars endpoint = **1 call for all 560 tickers** — this is why we chose it. Free tier is fine.

---

### Step 1.2 — Set Up Project Structure

The project currently has `scripts/` with notebooks. We're adding a proper Python script (not a notebook) because it needs to run from GitHub Actions later.

Create this folder structure (you'll create each file in the steps below):

```
Stock_analysis/
├── .env                          ← already exists
├── .gitignore                    ← already exists
├── schema/
│   └── stock_analysis_schema.sql ← already exists
├── scripts/
│   ├── finance_dataset.ipynb     ← already exists
│   └── seed_database.ipynb       ← already exists
├── ingestion/
│   ├── __init__.py               ← new (empty file, makes it a package)
│   └── price_fetcher.py          ← new (the main script)
├── requirements.txt              ← new (dependencies)
└── README.md                     ← new (after Phase 3, not now)
```

**What you type:**
```bash
mkdir ~/Desktop/git_projects/Stock_analysis/ingestion
touch ~/Desktop/git_projects/Stock_analysis/ingestion/__init__.py
touch ~/Desktop/git_projects/Stock_analysis/ingestion/price_fetcher.py
touch ~/Desktop/git_projects/Stock_analysis/requirements.txt
```

---

### Step 1.3 — Write requirements.txt

Open `requirements.txt` and add:

```
supabase==2.15.2
python-dotenv==1.1.0
requests==2.32.3
```

**Why these three only:**
- `supabase` — Python client for Supabase (already used in seed notebooks)
- `python-dotenv` — reads `.env` file
- `requests` — HTTP calls to Polygon.io API (simpler than the Polygon SDK for one endpoint)

---

### Step 1.4 — Install Dependencies

```bash
cd ~/Desktop/git_projects/Stock_analysis
source .venv/bin/activate        # activate the existing venv
pip install -r requirements.txt
```

If the `.venv` doesn't have pip working, create fresh:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

---

### Step 1.5 — Write price_fetcher.py

This is the full script you will type into `ingestion/price_fetcher.py`. I'll give you the complete architecture with every decision explained, then you write it.

**The logic, step by step:**

```
1. Load env vars (SUPABASE_URL, SUPABASE_KEY, POLYGON_API_KEY)
2. Connect to Supabase
3. Pull the list of all 560 tickers from the stocks table
   — we don't hardcode tickers; the DB is the source of truth
4. Call Polygon grouped daily bars endpoint for yesterday's date
   — endpoint: GET /v2/aggs/grouped/locale/us/market/stocks/{date}
   — returns OHLCV for ALL US stocks in one response
5. Filter the response to only our 560 tickers
   — Polygon returns 8,000+ tickers; we only want ours
6. Build a list of rows: {ticker, date, open, high, low, close, volume}
7. Upsert into Supabase price_history
   — UNIQUE(ticker, date) constraint handles re-runs safely
8. Log: rows inserted, tickers with no data, any errors
```

**The Polygon endpoint:**
```
GET https://api.polygon.io/v2/aggs/grouped/locale/us/market/stocks/2026-06-13
    ?adjusted=true
    &apiKey=YOUR_KEY
```

**Response shape (one ticker looks like this):**
```json
{
  "T": "AAPL",        ← ticker
  "o": 195.12,        ← open
  "h": 196.80,        ← high
  "l": 194.50,        ← low
  "c": 196.45,        ← close
  "v": 52341200       ← volume
}
```

**Why yesterday and not today:**  
Markets close at 4PM ET. Polygon's grouped daily bars for "today" aren't available until after close. Using yesterday (or the most recent trading day) guarantees data is there.

**The complete script structure — tell Claude Code exactly what to write:**

```python
# ingestion/price_fetcher.py

import os
import requests
from datetime import date, timedelta
from dotenv import load_dotenv
from supabase import create_client

# --- Setup ---
# load .env two levels up from this file (project root)
# determine target date (yesterday, or pass a date via CLI arg)
# connect to Supabase
# connect to Polygon (just a base URL + API key, no SDK needed)

# --- Get ticker universe ---
# pull all tickers from supabase stocks table
# store as a Python set for O(1) lookup during filtering

# --- Call Polygon ---
# build the URL for grouped daily bars
# GET request with apiKey as query param
# raise an error if status code != 200
# parse response JSON → results list

# --- Filter and shape ---
# loop through Polygon results
# skip any ticker not in our set
# build row dict: {ticker, date, open, high, low, close, volume}
# collect into a list

# --- Upsert to Supabase ---
# upsert the list with on_conflict="ticker,date"
# this is safe to re-run — duplicates update instead of error

# --- Log results ---
# print: date fetched, total Polygon results, matched tickers, rows upserted
# print: list of our tickers that had NO Polygon data (market holidays, delistings)
```

**When you're ready:** open the file, share it with me, and I'll architect every line.

---

### Step 1.6 — Test It

```bash
cd ~/Desktop/git_projects/Stock_analysis
source .venv/bin/activate
python -m ingestion.price_fetcher
```

Expected output:
```
Date: 2026-06-13
Polygon returned: 8,247 tickers
Matched our universe: 558 tickers
Upserted: 558 rows into price_history
No data for: ['BTC-USD', 'ETH-USD']   ← crypto won't be in US stocks endpoint
```

**Then verify in Supabase:**  
Dashboard → Table Editor → `price_history` → you should see 558+ rows with OHLCV data.

---

### Step 1.7 — Handle the GitHub Repo

Before Phase 2, the project needs to be on GitHub.

1. Check if remote exists: `git remote -v`
2. If no remote: create a new repo on GitHub named `finance-data-platform`, then:
   ```bash
   cd ~/Desktop/git_projects/Stock_analysis
   git init
   git add ingestion/ requirements.txt schema/ .gitignore
   git commit -m "Phase 1: price fetcher and project structure"
   git remote add origin https://github.com/YOUR_USERNAME/finance-data-platform.git
   git push -u origin main
   ```
3. **Never `git add .env`** — the `.gitignore` has it but double-check: `git status` should not show `.env` as staged.

---

## Phase 2 — dbt Transformation Layer

**Goal:** Take raw `price_history` in Supabase and build clean, tested, documented mart tables that the Claude analyzer will query.

**Why dbt matters for interviews:**  
dbt is on almost every analytics engineering job description. Having a working dbt project with tests and documentation — pointed at a real cloud database — is a concrete differentiator.

---

### Step 2.1 — Fix the dbt Profile

The existing `~/.dbt/profiles.yml` is pointed at Databricks with placeholder values. We need to replace it to point at Supabase (PostgreSQL).

**Open `~/.dbt/profiles.yml` and replace the entire contents with:**

```yaml
finance_platform:
  target: dev
  outputs:
    dev:
      type: postgres
      host: db.uiocdjtwshxpqtlcgfel.supabase.co
      port: 5432
      user: postgres
      password: YOUR_SUPABASE_DB_PASSWORD
      dbname: postgres
      schema: public
      threads: 1
```

**Where to get the Supabase DB password:**  
Supabase Dashboard → Project Settings → Database → Connection string → copy the password from the connection string. It's different from your API key.

**Then update `dbt_project.yml`** to reference the new profile name:

```yaml
name: finance_platform
version: '1.0'
profile: finance_platform

model-paths: ["models"]
test-paths: ["tests"]
seed-paths: ["seeds"]
target-path: "target"
clean-targets: ["target", "dbt_packages"]

models:
  finance_platform:
    staging:
      +materialized: view      # staging models = views (no extra storage)
    marts:
      +materialized: table     # mart models = real tables (queryable from Claude)
```

**Why staging = view, marts = table:**
- Staging models are just cleaning/renaming — no point materializing them as tables, views are free
- Mart models get queried by the Claude analyzer — they need to be real tables for performance

**Test the profile:**
```bash
cd ~/Desktop/DBT/dbt_project\ 
dbt debug
```
Should show: `Connection test: [OK connection ok]`

---

### Step 2.2 — Build the Folder Structure

```
dbt_project /
├── dbt_project.yml            ← update this (Step 2.1)
├── models/
│   ├── staging/
│   │   ├── stg_price_history.sql   ← new
│   │   └── schema.yml              ← new (column docs + tests)
│   └── marts/
│       ├── portfolio_positions.sql ← new
│       ├── portfolio_summary.sql   ← new
│       ├── portfolio_vs_spy.sql    ← new
│       └── schema.yml              ← new
└── tests/                          ← optional custom tests later
```

**What you type:**
```bash
mkdir -p ~/Desktop/DBT/dbt_project\ /models/staging
mkdir -p ~/Desktop/DBT/dbt_project\ /models/marts
```

---

### Step 2.3 — Staging Model: stg_price_history.sql

**Purpose:** Clean and type-cast the raw `price_history` table. Downstream models reference this, not the raw table.

**What it does:**
- Selects all columns from `price_history`
- Renames nothing (schema is already clean)
- Casts to correct types explicitly (belt-and-suspenders)
- Filters out any rows with null close price (bad data)

```sql
-- models/staging/stg_price_history.sql
-- Cleans raw price_history before mart models consume it.
-- Filters nulls and makes types explicit so downstream models don't need to.

select
    ticker,
    date,
    open::numeric    as open,
    high::numeric    as high,
    low::numeric     as low,
    close::numeric   as close,
    volume::bigint   as volume
from {{ source('public', 'price_history') }}
where close is not null   -- exclude rows where the price feed gave us nothing
```

**Add the source definition** — dbt needs to know where `price_history` lives. Create `models/staging/schema.yml`:

```yaml
version: 2

sources:
  - name: public
    database: postgres
    schema: public
    tables:
      - name: price_history
        description: "Raw daily OHLCV data from Polygon.io, one row per ticker per date"
        columns:
          - name: ticker
            description: "Stock ticker symbol"
            tests:
              - not_null
          - name: date
            description: "Trading date"
            tests:
              - not_null
          - name: close
            description: "Closing price"
            tests:
              - not_null
      - name: stocks
        description: "Reference table: one row per ticker with sector and metadata"
      - name: portfolio
        description: "Your positions: one row per buy lot with cost basis"

models:
  - name: stg_price_history
    description: "Cleaned price history — nulls removed, types explicit"
    columns:
      - name: ticker
        tests: [not_null]
      - name: date
        tests: [not_null]
      - name: close
        tests: [not_null]
```

**Run and test:**
```bash
dbt run --select stg_price_history
dbt test --select stg_price_history
```

---

### Step 2.4 — Mart Model: portfolio_positions.sql

**Purpose:** For each lot in your portfolio, calculate current value and P&L using latest price from `stg_price_history`.

**What it produces (one row per lot):**

| ticker | account | shares | purchase_price | purchase_date | current_price | cost_basis | current_value | unrealized_pnl | pnl_pct |
|--------|---------|--------|---------------|--------------|--------------|------------|--------------|----------------|---------|
| AAPL | Robinhood | 10 | 180.00 | 2025-01-15 | 196.45 | 1800.00 | 1964.50 | 164.50 | 9.14% |

```sql
-- models/marts/portfolio_positions.sql
-- One row per portfolio lot with cost basis and current P&L.
-- "Latest price" = the most recent date in price_history for each ticker.

with latest_prices as (
    -- For each ticker, get only the most recent date's close price.
    -- rank() = 1 means it's the latest row.
    select
        ticker,
        close      as current_price,
        date       as price_date,
        rank() over (partition by ticker order by date desc) as rn
    from {{ ref('stg_price_history') }}
),

current_prices as (
    select ticker, current_price, price_date
    from latest_prices
    where rn = 1
)

select
    p.ticker,
    s.company,
    s.sector,
    p.account,
    p.shares,
    p.purchase_price,
    p.purchase_date,
    cp.current_price,
    cp.price_date,
    -- cost basis = what you paid total for this lot
    round(p.shares * p.purchase_price, 2)                          as cost_basis,
    -- current value = what those shares are worth today
    round(p.shares * cp.current_price, 2)                          as current_value,
    -- unrealized P&L = gain or loss in dollars
    round((p.shares * cp.current_price) - (p.shares * p.purchase_price), 2) as unrealized_pnl,
    -- P&L as a percentage of cost
    round(((cp.current_price - p.purchase_price) / p.purchase_price) * 100, 2) as pnl_pct
from {{ source('public', 'portfolio') }} p
left join current_prices cp on p.ticker = cp.ticker
left join {{ source('public', 'stocks') }} s on p.ticker = s.ticker
```

---

### Step 2.5 — Mart Model: portfolio_summary.sql

**Purpose:** Portfolio-level rollup — total value, total cost, total P&L, and sector breakdown.

```sql
-- models/marts/portfolio_summary.sql
-- Rolls up portfolio_positions to portfolio level.
-- This is what the Claude analyzer reads for high-level questions.

with positions as (
    select * from {{ ref('portfolio_positions') }}
)

select
    -- Portfolio totals
    round(sum(cost_basis), 2)        as total_cost_basis,
    round(sum(current_value), 2)     as total_current_value,
    round(sum(unrealized_pnl), 2)    as total_unrealized_pnl,
    round(
        ((sum(current_value) - sum(cost_basis)) / sum(cost_basis)) * 100,
        2
    )                                as total_pnl_pct,

    -- Count of positions
    count(distinct ticker)           as num_positions,
    count(*)                         as num_lots,

    -- Best and worst performers
    max(pnl_pct)                     as best_position_pct,
    min(pnl_pct)                     as worst_position_pct,

    -- As-of date
   
from positions
```

**Also add: sector exposure query** (separate mart file)

```sql
-- models/marts/portfolio_sector_exposure.sql
-- Breaks down current value by sector.
-- Used by Claude to answer "what's my biggest sector bet?"

with positions as (
    select * from {{ ref('portfolio_positions') }}
),

totals as (
    select sum(current_value) as portfolio_total from positions
)

select
    sector,
    round(sum(current_value), 2)                                      as sector_value,
    round((sum(current_value) / max(t.portfolio_total)) * 100, 2)     as sector_pct
from positions
cross join totals t
where sector is not null
group by sector
order by sector_value desc
```

---

### Step 2.6 — Mart Model: portfolio_vs_spy.sql

**Purpose:** Compare portfolio daily return to SPY (the S&P 500 ETF) as a benchmark.

**Assumption:** SPY is one of your 560 tickers. If not, seed it into `stocks` and it'll get picked up by the price fetcher automatically.

```sql
-- models/marts/portfolio_vs_spy.sql
-- Daily portfolio return vs SPY benchmark.
-- Shows whether you're beating or lagging the market.

with daily_portfolio_value as (
    -- For each date, sum current value across all positions using that day's price
    select
        ph.date,
        round(sum(p.shares * ph.close), 2) as portfolio_value
    from {{ source('public', 'portfolio') }} p
    join {{ ref('stg_price_history') }} ph on p.ticker = ph.ticker
    group by ph.date
),

portfolio_with_return as (
    select
        date,
        portfolio_value,
        -- daily return = (today - yesterday) / yesterday
        lag(portfolio_value) over (order by date) as prev_value,
        round(
            ((portfolio_value - lag(portfolio_value) over (order by date))
             / lag(portfolio_value) over (order by date)) * 100,
            4
        ) as daily_return_pct
    from daily_portfolio_value
),

spy_prices as (
    select date, close as spy_close
    from {{ ref('stg_price_history') }}
    where ticker = 'SPY'
),

spy_with_return as (
    select
        date,
        spy_close,
        lag(spy_close) over (order by date) as prev_spy,
        round(
            ((spy_close - lag(spy_close) over (order by date))
             / lag(spy_close) over (order by date)) * 100,
            4
        ) as spy_daily_return_pct
    from spy_prices
)

select
    p.date,
    p.portfolio_value,
    p.daily_return_pct                                         as portfolio_return_pct,
    s.spy_daily_return_pct,
    round(p.daily_return_pct - s.spy_daily_return_pct, 4)     as alpha
from portfolio_with_return p
join spy_with_return s on p.date = s.date
where p.daily_return_pct is not null
order by p.date desc
```

---

### Step 2.7 — Add schema.yml for Marts

Create `models/marts/schema.yml`:

```yaml
version: 2

models:
  - name: portfolio_positions
    description: "One row per portfolio lot with current price and P&L"
    columns:
      - name: ticker
        tests: [not_null]
      - name: cost_basis
        tests: [not_null]
      - name: current_value
        tests: [not_null]

  - name: portfolio_summary
    description: "Portfolio-level rollup: total value, P&L, position count"

  - name: portfolio_sector_exposure
    description: "Current value and % allocation by sector"

  - name: portfolio_vs_spy
    description: "Daily portfolio return vs SPY benchmark with alpha calculation"
```

---

### Step 2.8 — Seed Your Portfolio Positions

Before the mart models return anything useful, you need actual positions in the `portfolio` table.

Go to Supabase Dashboard → Table Editor → `portfolio` → Insert rows.

Or write a quick seed script (easier). Format per the schema:
```
ticker | account | shares | purchase_price | purchase_date
AAPL   | Robinhood | 10  | 180.00         | 2025-01-15
```

Add your real positions. The `portfolio_positions` mart will calculate everything from there.

---

### Step 2.9 — Run the Full dbt Stack

```bash
cd ~/Desktop/DBT/dbt_project\ 
dbt run        # builds all models in dependency order
dbt test       # runs all schema tests
dbt docs generate && dbt docs serve   # opens docs in browser
```

Expected:
```
Running 5 models...
  stg_price_history      [OK]
  portfolio_positions    [OK]
  portfolio_summary      [OK]
  portfolio_sector_exposure [OK]
  portfolio_vs_spy       [OK]
5 tests passed.
```

**Then verify in Supabase:** you should see new tables in the `public` schema named after your mart models.

---

## Phase 3 — Claude API Portfolio Analyzer

**Goal:** Python script where you ask portfolio questions in natural language and Claude answers using real data from your Supabase marts via tool use.

---

### Step 3.1 — Create the Analysis Script

```
Stock_analysis/
└── analysis/
    ├── __init__.py
    └── portfolio_analyzer.py
```

```bash
mkdir ~/Desktop/git_projects/Stock_analysis/analysis
touch ~/Desktop/git_projects/Stock_analysis/analysis/__init__.py
touch ~/Desktop/git_projects/Stock_analysis/analysis/portfolio_analyzer.py
```

Add to `requirements.txt`:
```
anthropic==0.40.0
```

---

### Step 3.2 — Add ANTHROPIC_API_KEY to .env

```
ANTHROPIC_API_KEY=your_key_here
```

---

### Step 3.3 — Write portfolio_analyzer.py

**The architecture:**

```
User types: "Why is my portfolio down today?"
     ↓
Claude receives the question + a list of available tools
     ↓
Claude decides which tools to call:
   → get_portfolio_summary()       reads portfolio_summary mart
   → get_portfolio_vs_spy()        reads portfolio_vs_spy mart
     ↓
Tools execute SQL against Supabase, return real data as JSON
     ↓
Claude receives the data and writes the answer
     ↓
No hallucination — every number came from a real table
```

**The 4 tools Claude gets access to:**

```python
tools = [
    {
        "name": "get_portfolio_summary",
        "description": "Returns portfolio totals: total value, cost basis, unrealized P&L, P&L %, number of positions, best and worst performers. Use this for high-level portfolio health questions.",
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "get_portfolio_positions",
        "description": "Returns all individual holdings with ticker, shares, cost basis, current value, and P&L for each lot. Use this when the question is about specific positions.",
        "input_schema": {
            "type": "object",
            "properties": {
                "sector": {
                    "type": "string",
                    "description": "Optional: filter to positions in a specific sector (e.g. 'Technology', 'Healthcare')"
                }
            },
            "required": []
        }
    },
    {
        "name": "get_sector_exposure",
        "description": "Returns portfolio allocation broken down by sector: sector name, total value in that sector, and % of portfolio. Use this for sector concentration and diversification questions.",
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "get_daily_movers",
        "description": "Returns portfolio performance vs SPY for recent trading days, including daily return %, SPY return %, and alpha (outperformance). Use this for questions about recent performance.",
        "input_schema": {
            "type": "object",
            "properties": {
                "days": {
                    "type": "integer",
                    "description": "How many recent trading days to return. Default 5."
                }
            },
            "required": []
        }
    }
]
```

**The tool execution loop (same pattern from your Anthropic cert):**

```python
def run_tool(tool_name, tool_input, supabase):
    if tool_name == "get_portfolio_summary":
        result = supabase.table("portfolio_summary").select("*").execute()
        return result.data[0] if result.data else {}

    elif tool_name == "get_portfolio_positions":
        query = supabase.table("portfolio_positions").select("*")
        if tool_input.get("sector"):
            query = query.eq("sector", tool_input["sector"])
        result = query.execute()
        return result.data

    elif tool_name == "get_sector_exposure":
        result = supabase.table("portfolio_sector_exposure").select("*").execute()
        return result.data

    elif tool_name == "get_daily_movers":
        days = tool_input.get("days", 5)
        result = supabase.table("portfolio_vs_spy").select("*").limit(days).execute()
        return result.data
```

**Running the analyzer:**
```bash
python -m analysis.portfolio_analyzer
```

Sample session:
```
Portfolio Analyzer — ask anything about your holdings.
> Why is my portfolio down today?

[Claude calls get_daily_movers, gets today's data]
[Claude calls get_portfolio_positions, finds worst performers]

Your portfolio dropped 1.2% today vs SPY's -0.4%, underperforming by 0.8%.
The drag came primarily from your Technology positions — NVDA fell 3.1% and
AMD dropped 2.7%, which together represent 28% of your portfolio value...
```

---

## Phase 4 — GitHub Actions (Daily Automation)

**Goal:** `price_fetcher.py` runs automatically every weekday at 4:30 PM ET without you touching anything.

---

### Step 4.1 — Create the Workflow File

```
Stock_analysis/
└── .github/
    └── workflows/
        └── daily_prices.yml
```

```bash
mkdir -p ~/Desktop/git_projects/Stock_analysis/.github/workflows
touch ~/Desktop/git_projects/Stock_analysis/.github/workflows/daily_prices.yml
```

---

### Step 4.2 — Write daily_prices.yml

```yaml
name: Daily Price Fetch

on:
  schedule:
    # 21:30 UTC = 4:30 PM ET (UTC-5 in winter, UTC-4 in summer)
    # Use 21:30 to safely cover both EST and EDT
    - cron: '30 21 * * 1-5'    # weekdays only (1=Mon, 5=Fri)
  workflow_dispatch:             # also lets you trigger it manually from GitHub UI

jobs:
  fetch-prices:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repo
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Run price fetcher
        env:
          SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
          SUPABASE_KEY: ${{ secrets.SUPABASE_KEY }}
          POLYGON_API_KEY: ${{ secrets.POLYGON_API_KEY }}
        run: python -m ingestion.price_fetcher
```

---

### Step 4.3 — Add Secrets to GitHub

The workflow needs your API keys but can't read your `.env` file. GitHub has its own secrets vault.

1. Go to your GitHub repo → Settings → Secrets and variables → Actions → New repository secret
2. Add these three:
   - `SUPABASE_URL` — copy from your `.env`
   - `SUPABASE_KEY` — copy from your `.env`
   - `POLYGON_API_KEY` — copy from your `.env`

That's it. The `${{ secrets.X }}` references in the YAML pull from there.

---

### Step 4.4 — Test the Workflow

1. Push the workflow file to GitHub
2. Go to Actions tab in your repo
3. Click "Daily Price Fetch" → "Run workflow" (the manual trigger you added)
4. Watch it run — should complete in under 30 seconds

Once it runs green manually, the schedule takes over. You're done.

---

## Full Dependency Order

```
Step 1.1   Get Polygon API key
Step 1.2   Create ingestion/ folder structure
Step 1.3   Write requirements.txt
Step 1.4   Install dependencies
Step 1.5   Write price_fetcher.py          ← share with Claude Code to architect
Step 1.6   Test — verify rows in Supabase
Step 1.7   Push to GitHub

Step 2.1   Fix dbt profile + dbt_project.yml
Step 2.2   Create models/ folder structure
Step 2.3   Write stg_price_history.sql + schema.yml
Step 2.4   Write portfolio_positions.sql
Step 2.5   Write portfolio_summary.sql + sector_exposure.sql
Step 2.6   Write portfolio_vs_spy.sql
Step 2.7   Write marts schema.yml
Step 2.8   Seed portfolio positions in Supabase
Step 2.9   dbt run + dbt test → all green

Step 3.1   Create analysis/ folder structure
Step 3.2   Add ANTHROPIC_API_KEY to .env
Step 3.3   Write portfolio_analyzer.py    ← share with Claude Code to architect
           Run it — ask real questions, get real answers

Step 4.1   Create .github/workflows/ folder
Step 4.2   Write daily_prices.yml
Step 4.3   Add secrets to GitHub repo settings
Step 4.4   Trigger manual run → confirm green

DONE       Write LinkedIn post (template in PORTFOLIO_PLAN.md)
           Pin repo to GitHub profile
```

---

## Blockers Before You Can Start

| Blocker | Action |
|---------|--------|
| No Polygon API key | Sign up at polygon.io, add `POLYGON_API_KEY` to `.env` |
| dbt profile wrong (Databricks placeholder) | Replace `~/.dbt/profiles.yml` with Postgres config (Step 2.1) |
| No portfolio positions seeded | Add real positions to Supabase `portfolio` table (Step 2.8) |
| No GitHub remote for this project | Create repo on GitHub, add remote (Step 1.7) |

---

---

## Phase 5 — Streamlit Dashboard

**Goal:** Visual dashboard that reads the mart tables from Supabase and renders charts. No new data logic — the dbt marts already did the work. This is purely a display layer.

**Stack:** Streamlit (UI framework) + Plotly (charts) + Supabase Python client (already in requirements.txt)

---

### Step 5.1 — Create the Dashboard Folder

```
Stock_analysis/
└── dashboard/
    ├── __init__.py
    └── app.py
```

```bash
mkdir ~/Desktop/git_projects/Stock_analysis/dashboard
touch ~/Desktop/git_projects/Stock_analysis/dashboard/__init__.py
touch ~/Desktop/git_projects/Stock_analysis/dashboard/app.py
```

Add to `requirements.txt`:
```
streamlit==1.35.0
plotly==5.22.0
```

---

### Step 5.2 — Planned Charts

| Chart | Source mart | Type |
|-------|-------------|------|
| Portfolio total value over time | `portfolio_vs_spy` | Line |
| Portfolio vs SPY indexed to 100 | `portfolio_vs_spy` | Line (2 series) |
| Sector allocation | `portfolio_sector_exposure` | Pie |
| Per-position unrealized gain/loss | `portfolio_positions` | Horizontal bar |
| Portfolio summary KPIs | `portfolio_summary` | Metric cards |

---

### Step 5.3 — Run It

```bash
source .venv/bin/activate
streamlit run dashboard/app.py
```

Opens at `localhost:8501` in browser.

---

## Phase 6 — FastAPI Layer

**Status: Complete.** `api/main.py` serves 4 endpoints. Dashboard was migrated to call the API instead of Supabase directly. See `CLAUDE.md` for endpoint reference.

---

## Phase 7 — Market Movers, News & Economic Indicators

**Goal:** Fill the three "Coming soon" tabs: top gainers/losers from the 560-ticker universe, portfolio news via Polygon.io, and macro economic indicators via FRED. This is the final phase of the public repo.

**Pattern:** Same as Phase 6. New dbt mart → new FastAPI endpoints → dashboard tabs call the API → Claude gets new tools.

**What already exists heading into Phase 7:**
- `dashboard/app.py` has tabs 3, 4, 5 defined with placeholder `st.info()` text — just replace those blocks
- `api/main.py` has the Supabase client and pattern to follow — just add new route functions
- `analysis/portfolio_analyzer.py` has the tools list and `run_tool()` dispatch — just extend both

---

### Step 7.1 — Get a FRED API Key

FRED (Federal Reserve Economic Data) is maintained by the St. Louis Fed. Free, official, no meaningful rate limits.

1. Go to `https://fred.stlouisfed.org/docs/api/api_key.html`
2. Create a free account → request an API key (granted immediately)
3. Add to `.env`:
   ```
   FRED_API_KEY=your_key_here
   ```
4. Add to GitHub repo secrets (Settings → Secrets → Actions):
   - Name: `FRED_API_KEY`, Value: same key

**Why FRED and not a paid provider?** FRED has the four macro series every analyst tracks — Fed Funds Rate, CPI, GDP, Unemployment. It's the primary source Bloomberg and Reuters pull from. Free, reliable, no rate limits for reasonable use.

---

### Step 7.2 — Build the `market_movers` dbt Mart

**Why a dbt mart and not a live query?**
`price_history` already has all 560 tickers' daily OHLCV from the price fetcher — no new Polygon API call needed. A `LAG` window function gives you yesterday's close. Putting the calculation in dbt keeps all transformation logic in one place and makes the mart reusable by the API, the dashboard, and the analyzer.

Create `dbt/models/marts/market_movers.sql`:

```sql
-- models/marts/market_movers.sql
-- Daily price change for every ticker, computed from existing price_history data.
-- No new API call needed — price_history already has all 560 tickers.

with price_with_lag as (
    select
        ticker,
        date,
        open,
        close,
        volume,
        -- Previous trading day's close for this ticker (handles weekends correctly)
        lag(close) over (partition by ticker order by date) as prev_close
    from {{ ref('stg_price_history') }}
),

latest_day as (
    select
        ticker,
        date,
        open,
        close,
        volume,
        prev_close,
        rank() over (partition by ticker order by date desc) as rn
    from price_with_lag
    where prev_close is not null   -- skip tickers with only one day of data
)

select
    m.ticker,
    s.company,
    s.sector,
    m.date,
    m.open,
    m.close,
    round(m.close - m.prev_close, 2)                             as change_dollars,
    round(((m.close - m.prev_close) / m.prev_close) * 100, 2)   as change_pct,
    m.volume
from latest_day m
join {{ source('public', 'stocks') }} s on m.ticker = s.ticker
where m.rn = 1
order by change_pct desc
```

**The LAG window function:** `lag(close) over (partition by ticker order by date)` returns the prior row's close for that same ticker. Combined with `rank() over (...) = 1`, you get today's and yesterday's close for every ticker in a single pass — no self-join required.

Add the new model to `dbt/models/marts/schema.yml`:

```yaml
  - name: market_movers
    description: "Daily price change % for all 560 tickers — source for gainers/losers tab"
    columns:
      - name: ticker
        tests: [not_null]
      - name: change_pct
        tests: [not_null]
```

Run and verify:
```bash
dbt run --select market_movers
dbt test --select market_movers
```

Expected: `market_movers` table appears in Supabase `public` schema with ~560 rows. Sort by `change_pct` descending in Supabase Table Editor to spot-check the top gainer looks reasonable for that day.

---

### Step 7.3 — Add New FastAPI Endpoints

Open `api/main.py`. Add `import requests as http_requests` at the top (rename to avoid conflict with FastAPI's `Request` object if you add it later). Also add `import os` if not already there — it is.

```python
import requests as http_requests

POLYGON_BASE = "https://api.polygon.io"
FRED_BASE    = "https://api.stlouisfed.org/fred"


@app.get("/market/movers")
def get_movers(limit: int = 10):
    """Top gainers and top losers from the 560-ticker universe."""
    gainers = (
        supabase.table("market_movers")
        .select("*")
        .order("change_pct", desc=True)
        .limit(limit)
        .execute()
    )
    losers = (
        supabase.table("market_movers")
        .select("*")
        .order("change_pct", desc=False)
        .limit(limit)
        .execute()
    )
    return {"gainers": gainers.data, "losers": losers.data}


@app.get("/market/news")
def get_news(ticker: str = None, limit: int = 20):
    """
    Latest news from Polygon /v2/reference/news.
    Optionally filter to a single ticker with ?ticker=AAPL.
    """
    params = {
        "apiKey": os.environ["POLYGON_API_KEY"],
        "limit":  limit,
        "order":  "desc",
        "sort":   "published_utc",
    }
    if ticker:
        params["ticker.any_of"] = ticker
    resp = http_requests.get(f"{POLYGON_BASE}/v2/reference/news", params=params, timeout=10)
    resp.raise_for_status()
    return resp.json().get("results", [])


@app.get("/market/indicators")
def get_indicators():
    """
    Last 24 observations for 4 FRED macro series.
    FEDFUNDS (monthly), CPIAUCSL (monthly), GDP (quarterly), UNRATE (monthly).
    """
    fred_key = os.environ["FRED_API_KEY"]
    series_map = {
        "fed_funds_rate": "FEDFUNDS",
        "cpi":            "CPIAUCSL",
        "gdp":            "GDP",
        "unemployment":   "UNRATE",
    }
    result = {}
    for name, series_id in series_map.items():
        resp = http_requests.get(
            f"{FRED_BASE}/series/observations",
            params={
                "series_id":  series_id,
                "api_key":    fred_key,
                "file_type":  "json",
                "limit":      24,
                "sort_order": "desc",
            },
            timeout=10,
        )
        resp.raise_for_status()
        obs = resp.json().get("observations", [])
        # FRED marks missing observations with a literal "." — filter them out
        result[name] = [o for o in obs if o["value"] != "."]
    return result
```

**Why `timeout=10` on external API calls?** External calls can hang. A 10-second timeout surfaces the problem immediately instead of blocking the dashboard indefinitely.

**Why filter `value != "."`?** FRED uses a literal period character for missing data points (e.g., GDP during revisions). Leaving them in causes `pd.to_numeric()` to throw in the dashboard.

**Why 24 observations?** Monthly series = 2 years of history. Quarterly (GDP) = 6 years. Enough context for a trend chart without over-fetching.

**Updated API endpoint table after Phase 7:**

| Method | URL | Description |
|--------|-----|-------------|
| GET | `/portfolio/summary` | Portfolio totals |
| GET | `/portfolio/positions` | All portfolio lots |
| GET | `/portfolio/sector` | Sector exposure |
| GET | `/portfolio/spy` | Portfolio vs SPY |
| GET | `/market/movers?limit=10` | Top gainers and losers |
| GET | `/market/news?ticker=AAPL&limit=20` | News articles, optional ticker filter |
| GET | `/market/indicators` | Fed rate, CPI, GDP, unemployment |

---

### Step 7.4 — Dashboard: Market Movers Tab

Open `dashboard/app.py`. Add `import requests` at the top.

Replace this block in `tab3`:
```python
# Tab 3: Market Movers
with tab3:
    st.subheader("Market Movers")
    st.info("Coming soon — top gainers and losers from your 560-ticker universe.")
```

With:
```python
# Tab 3: Market Movers
with tab3:
    @st.cache_data(ttl=300)
    def load_movers():
        return requests.get("http://localhost:8000/market/movers?limit=10").json()

    movers_data = load_movers()
    gainers_df  = pd.DataFrame(movers_data["gainers"])
    losers_df   = pd.DataFrame(movers_data["losers"])

    def format_movers_table(df):
        display = df[["ticker", "company", "sector", "close", "change_dollars", "change_pct"]].copy()
        display.columns = ["Ticker", "Company", "Sector", "Price", "Change $", "Change %"]
        return display

    def color_change_cell(val):
        color = "#27ae60" if val > 0 else "#e74c3c"
        return f"color: {color}; font-weight: 600"

    col1, col2 = st.columns(2)

    with col1:
        st.markdown("#### Top Gainers")
        g = format_movers_table(gainers_df)
        st.dataframe(
            g.style
                .applymap(color_change_cell, subset=["Change $", "Change %"])
                .format({"Price": "${:.2f}", "Change $": "${:.2f}", "Change %": "{:.2f}%"}),
            use_container_width=True,
            hide_index=True,
        )

    with col2:
        st.markdown("#### Top Losers")
        l = format_movers_table(losers_df)
        st.dataframe(
            l.style
                .applymap(color_change_cell, subset=["Change $", "Change %"])
                .format({"Price": "${:.2f}", "Change $": "${:.2f}", "Change %": "{:.2f}%"}),
            use_container_width=True,
            hide_index=True,
        )

    as_of = gainers_df["date"].iloc[0] if not gainers_df.empty else "N/A"
    st.caption(f"Data as of {as_of}. Reflects most recent trading day in price_history.")
```

**Why `@st.cache_data` inside the tab function?** It only executes when the user opens that tab — not on every page load. Keeps startup fast.

---

### Step 7.5 — Dashboard: News Tab

Replace the `tab4` block:
```python
# Tab 4: News
with tab4:
    st.subheader("News")
    st.info("Coming soon — latest news for your portfolio tickers via Polygon.io.")
```

With:
```python
# Tab 4: News
with tab4:
    @st.cache_data(ttl=600)
    def load_news(ticker_filter, limit):
        url = f"http://localhost:8000/market/news?limit={limit}"
        if ticker_filter != "All":
            url += f"&ticker={ticker_filter}"
        return requests.get(url).json()

    portfolio_tickers = ["All"] + sorted(positions["ticker"].tolist())
    selected_ticker   = st.selectbox("Filter by ticker", portfolio_tickers, key="news_ticker")

    articles = load_news(selected_ticker, limit=20)

    if not articles:
        st.info("No news found for this selection.")
    else:
        for article in articles:
            pub_date = article.get("published_utc", "")[:10]
            tickers  = ", ".join(article.get("tickers", [])[:5])
            publisher = article.get("publisher", {}).get("name", "")
            description = article.get("description", "")
            if len(description) > 200:
                description = description[:200] + "..."

            st.markdown(
                f"**[{article['title']}]({article['article_url']})**\n\n"
                f"<small style='color:#7a8599;'>{publisher} · {pub_date} · {tickers}</small>",
                unsafe_allow_html=True,
            )
            if description:
                st.caption(description)
            st.markdown("---")
```

**Why `ttl=600` for news (vs 300 for other tabs)?** News doesn't change second-to-second. Polygon's free tier has a 5 req/min limit — a longer cache reduces API calls and avoids hitting that limit when multiple people use the dashboard.

**Why proxy news through FastAPI instead of calling Polygon from the dashboard directly?** API keys stay server-side. Rate limit handling and error surfacing happen in one place. The dashboard stays a display layer.

---

### Step 7.6 — Dashboard: Economic Indicators Tab

Replace the `tab5` block:
```python
# Tab 5: Economic Indicators
with tab5:
    st.subheader("Economic Indicators")
    st.info("Coming soon — GDP, inflation, Fed funds rate, and unemployment via FRED API.")
```

With:
```python
# Tab 5: Economic Indicators
with tab5:
    @st.cache_data(ttl=3600)   # macro data is monthly/quarterly — 1hr cache is fine
    def load_indicators():
        return requests.get("http://localhost:8000/market/indicators").json()

    indicators = load_indicators()

    def parse_fred_series(obs_list, label):
        df = pd.DataFrame(obs_list)
        df["date"]  = pd.to_datetime(df["date"])
        df["value"] = pd.to_numeric(df["value"])
        df = df.sort_values("date")
        df["label"] = label
        return df

    fed   = parse_fred_series(indicators["fed_funds_rate"], "Fed Funds Rate (%)")
    cpi   = parse_fred_series(indicators["cpi"],            "CPI (Index)")
    gdp   = parse_fred_series(indicators["gdp"],            "GDP ($B)")
    unemp = parse_fred_series(indicators["unemployment"],   "Unemployment (%)")

    def latest_and_delta(df):
        val   = df.iloc[-1]["value"]
        prior = df.iloc[-2]["value"] if len(df) > 1 else val
        return val, round(val - prior, 3)

    fed_val,   fed_d   = latest_and_delta(fed)
    cpi_val,   cpi_d   = latest_and_delta(cpi)
    gdp_val,   gdp_d   = latest_and_delta(gdp)
    unemp_val, unemp_d = latest_and_delta(unemp)

    # KPI row
    c1, c2, c3, c4 = st.columns(4)
    for col, label, val_str, delta in [
        (c1, "Fed Funds Rate",  f"{fed_val:.2f}%",    fed_d),
        (c2, "CPI Index",       f"{cpi_val:.1f}",     cpi_d),
        (c3, "GDP ($B)",        f"${gdp_val:,.0f}",   gdp_d),
        (c4, "Unemployment",    f"{unemp_val:.1f}%",  unemp_d),
    ]:
        d_color = "#27ae60" if delta >= 0 else "#e74c3c"
        d_arrow = "▲" if delta >= 0 else "▼"
        col.markdown(f"""<div class="kpi-card">
            <div class="kpi-label">{label}</div>
            <div class="kpi-value">{val_str}</div>
            <div class="kpi-delta" style="color:{d_color}">{d_arrow} {abs(delta)}</div>
        </div>""", unsafe_allow_html=True)

    st.markdown("---")

    col_a, col_b = st.columns(2)

    with col_a:
        fig_fed = px.line(fed, x="date", y="value", title="Federal Funds Rate (%)",
                          template=CHART_TEMPLATE, labels={"value": "%", "date": ""})
        fig_fed.update_traces(line_color="#4c9be8", line_width=2.5)
        fig_fed.update_layout(font=CHART_FONT, margin=dict(t=40, b=10, l=10, r=10))
        st.plotly_chart(fig_fed, use_container_width=True)

        fig_unemp = px.line(unemp, x="date", y="value", title="Unemployment Rate (%)",
                            template=CHART_TEMPLATE, labels={"value": "%", "date": ""})
        fig_unemp.update_traces(line_color="#e74c3c", line_width=2.5)
        fig_unemp.update_layout(font=CHART_FONT, margin=dict(t=40, b=10, l=10, r=10))
        st.plotly_chart(fig_unemp, use_container_width=True)

    with col_b:
        fig_cpi = px.line(cpi, x="date", y="value", title="CPI (Consumer Price Index)",
                          template=CHART_TEMPLATE, labels={"value": "Index", "date": ""})
        fig_cpi.update_traces(line_color="#f39c12", line_width=2.5)
        fig_cpi.update_layout(font=CHART_FONT, margin=dict(t=40, b=10, l=10, r=10))
        st.plotly_chart(fig_cpi, use_container_width=True)

        fig_gdp = px.bar(gdp, x="date", y="value", title="GDP (Billions USD)",
                         template=CHART_TEMPLATE, labels={"value": "$B", "date": ""})
        fig_gdp.update_traces(marker_color="#27ae60")
        fig_gdp.update_layout(font=CHART_FONT, margin=dict(t=40, b=10, l=10, r=10))
        st.plotly_chart(fig_gdp, use_container_width=True)

    st.caption("Source: FRED (Federal Reserve Bank of St. Louis). Data lags 1–2 reporting periods.")
```

**Why `ttl=3600`?** FRED data is released monthly or quarterly — caching for 1 hour is completely safe.

**Why GDP as a bar chart instead of a line?** GDP is a discrete quarterly snapshot, not a continuous signal. A bar chart communicates "this quarter's value" more accurately than a line, which implies continuous movement between points.

---

### Step 7.7 — Add Three New Tools to the Analyzer

Open `analysis/portfolio_analyzer.py`. Add `import requests` at the top.

Add to the `tools` list:

```python
    {
        "name": "get_market_movers",
        "description": "Returns top gainers and losers from the 560-ticker universe for the most recent trading day. Use when asked what's moving today, what's up big, what's down, or what stocks are hot.",
        "input_schema": {
            "type": "object",
            "properties": {
                "limit": {
                    "type": "integer",
                    "description": "How many gainers and losers to return. Default 10."
                }
            },
            "required": []
        }
    },
    {
        "name": "get_news",
        "description": "Returns recent financial news articles from Polygon. Optionally filter to one ticker. Use when asked about news, what's happening with a stock, or why something is moving.",
        "input_schema": {
            "type": "object",
            "properties": {
                "ticker": {
                    "type": "string",
                    "description": "Optional: stock ticker to filter news for (e.g. 'AAPL'). Leave blank for general market news."
                },
                "limit": {
                    "type": "integer",
                    "description": "Number of articles to return. Default 10."
                }
            },
            "required": []
        }
    },
    {
        "name": "get_macro_indicators",
        "description": "Returns recent observations for Fed Funds Rate, CPI, GDP, and Unemployment from FRED. Use when asked about the macro environment, interest rates, inflation, economic conditions, or how the broader economy affects the portfolio.",
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
```

Add to the `run_tool()` function:

```python
    elif tool_name == "get_market_movers":
        limit = tool_input.get("limit", 10)
        resp = requests.get(f"http://localhost:8000/market/movers?limit={limit}")
        return resp.json()

    elif tool_name == "get_news":
        ticker = tool_input.get("ticker", "")
        limit  = tool_input.get("limit", 10)
        url    = f"http://localhost:8000/market/news?limit={limit}"
        if ticker:
            url += f"&ticker={ticker}"
        resp = requests.get(url)
        return resp.json()

    elif tool_name == "get_macro_indicators":
        resp = requests.get("http://localhost:8000/market/indicators")
        return resp.json()
```

**Why call the API instead of calling Polygon/FRED directly from the analyzer?** The API already handles credentials, error handling, and caching. The analyzer stays focused on reasoning — it shouldn't know about external API details.

---

### Step 7.8 — End-to-End Test

1. `dbt run` — confirm `market_movers` table appears in Supabase with ~560 rows
2. Start the API (`api` alias) — test all three new endpoints in the browser:
   - `http://localhost:8000/market/movers`
   - `http://localhost:8000/market/news`
   - `http://localhost:8000/market/indicators`
3. Start the dashboard (`portfolio` alias) — click through all three tabs
4. Ask the analyzer: *"What's moving in the market today?"* and *"What is the current Federal Funds Rate?"*

**If `market_movers` is empty:** The mart needs at least 2 days of price history per ticker (`prev_close is not null` filter). Run the backfill (`python -m ingestion.backfill`) if needed.

**If news returns empty:** Polygon free tier may throttle. Try the endpoint directly with a small limit (`/market/news?limit=5`) and check the API response for error messages.

---

### Phase 7 Complete — Public Repo Done

The public repo is now feature-complete:

| Layer | What's built |
|-------|-------------|
| Data | 560 tickers, daily OHLCV, portfolio positions, fundamentals |
| dbt | 5 mart tables: positions, summary, sector, SPY, market movers |
| API | 7 endpoints across `/portfolio/*` and `/market/*` |
| Dashboard | 5 tabs: Summary, Positions, Market Movers, News, Economic Indicators |
| Analyzer | 7 tools covering portfolio, movers, news, and macro |
| Automation | GitHub Actions running price fetcher daily at 4:30 PM ET |

**Next step: fork this repo to a private repo and continue with Phase 8.**
See `personal/PRIVATE_BUILD_PLAN.md` for the full private-phase roadmap.

---

*Build plan lives at `~/Desktop/git_projects/REPO2_BUILD_PLAN.md`*
