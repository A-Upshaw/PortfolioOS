# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

A finance data platform: Polygon.io daily prices → Supabase (PostgreSQL) → dbt transformations → Streamlit dashboard (direct Supabase/Polygon/FRED calls) + Claude-powered natural language analyzer.

**Full build plan:** [REPO2_BUILD_PLAN.md](REPO2_BUILD_PLAN.md)

---

## Running the Project

**Dashboard (standalone — no API server needed):**
```bash
portfolio   # shell alias in ~/.zshrc — launches Streamlit at localhost:8501
```

**FastAPI (optional — exists but the dashboard no longer calls it; see Key Architecture Decisions):**
```bash
api   # shell alias in ~/.zshrc — runs uvicorn at localhost:8000
```
Interactive API docs: `http://localhost:8000/docs`

**CLI analyzer (terminal Q&A, talks to Supabase + Polygon + FRED directly):**
```bash
/Users/Jarvis/Desktop/git_projects/PortfolioOS/.venv/bin/python -m analysis.portfolio_analyzer
```

**Price fetcher (manual run):**
```bash
/Users/Jarvis/Desktop/git_projects/PortfolioOS/.venv/bin/python -m ingestion.price_fetcher
```

**dbt (use shell functions — NOT the system dbt binary which is dbt Fusion):**
```bash
dbt run        # rebuild all mart tables after new price data
dbt run --select market_movers   # rebuild a single mart
dbt test       # run schema tests
dbt debug      # test Supabase connection
dbtdocs        # generate + serve lineage at localhost:8080
```
From a non-interactive shell (e.g. scripted), `dbt` won't resolve — it's a zsh function in `~/.zshrc`, not a binary. Use `zsh -ic "dbt run"` instead.

**Install dependencies:**
```bash
uv pip install --python .venv/bin/python -r requirements.txt
```
The `.venv` has no `pip` binary — always use `uv pip install`.

---

## Architecture

```
Polygon.io (1 API call = all 560 tickers)
    ↓
ingestion/price_fetcher.py  →  Supabase: price_history (raw OHLCV)
    ↓
dbt/models/staging/  (views: stg_stocks, stg_portfolio, stg_price_history — clean + typed)
    ↓
dbt/models/marts/
    portfolio_positions        (P&L per lot + weighted_avg_cost — joins portfolio + stocks + latest price)
    portfolio_summary          (totals rollup)
    portfolio_sector_exposure  (sector % allocation)
    portfolio_vs_spy           (daily alpha vs SPY, indexed to 100)
    market_movers              (daily % change per ticker, LAG window, full 560-ticker universe)
    realized_pnl               (per-sale gain/loss — joins sales + portfolio avg cost + stg_stocks)
    ↓
dashboard/app.py        (Streamlit — calls Supabase + Polygon news + FRED directly)
analysis/portfolio_analyzer.py  (Claude tool use — calls Supabase + Polygon + FRED directly)
api/main.py              (FastAPI — same endpoints, currently unused by the dashboard)
```

---

## Key Architecture Decisions

**Dashboard calls Supabase/Polygon/FRED directly, not FastAPI.** `dashboard/app.py` has its own `supabase` client and `requests` calls to Polygon/FRED. This superseded the original FastAPI-mediated design so the dashboard can deploy standalone on Streamlit Cloud without a separate API process running. `api/main.py` still exists with equivalent endpoints (including `/market/movers`, `/market/news`, `/market/indicators`) but nothing currently depends on it — don't assume it's wired up when tracing a dashboard bug.

**Analyzer also calls Supabase/Polygon/FRED directly**, mirroring the dashboard's approach rather than going through the API.

**`analyze()` returns a string, not prints.** The dashboard imports `analyze` and renders the return value via `st.markdown()`. The CLI wraps it with `print()` in `__main__`.

**Tool execution loop:** `analyze()` runs a `while True` loop — Claude calls tools (`stop_reason == "tool_use"`), we execute them and feed results back, loop until `stop_reason == "end_turn"`. Claude may call multiple tools per question.

**Multi-turn conversation history:** `analyze(question, messages)` accepts a `messages` list owned by the caller. The CLI `__main__` block creates `messages = []` once outside its loop; the dashboard uses `st.session_state.analyzer_messages` (separate from `st.session_state.messages` which is display-only). `add_user_messages` and `add_assistant_message` helpers append to the shared list each turn.

**dbt profile:** `finance_platform` → `dev` → postgres at Supabase. Lives in `~/.dbt/profiles.yml`. The `dbt` shell function in `~/.zshrc` points to dbt-core 1.9.0 with `--project-dir` set to `dbt/`.

**`portfolio_vs_spy` requires SPY** in both `stocks` and `price_history`. If SPY has no price data, this mart returns empty.

**`market_movers` filters out split/adjustment artifacts.** Polygon back-adjusts historical prices for splits, but a ticker's older `price_history` row can predate that adjustment, producing a fake ~2x/0.5x overnight "move". The mart excludes any `abs(change_pct) >= 50%` as not a real single-day move.

**Price fetcher always targets the most recently completed trading day** (`get_target_dates()` in `ingestion/price_fetcher.py`), never "today" — Polygon's free Basic plan 403s (`NOT_AUTHORIZED`) on same-day grouped data regardless of time of day, confirmed via direct testing, not just docs.

**Dashboard caching:** All data-loading functions in `dashboard/app.py` are wrapped in `@st.cache_data` — `ttl=300` (5 min) for price-driven data (summary, positions, sector, vs_spy, movers, news), `ttl=3600` (1 hr) for slow-changing data (enterprise values, FRED indicators). Clear with `C` in browser.

**`sys.path.append`** at the top of `dashboard/app.py` lets it import from `analysis/` (sibling directory). Required because Streamlit doesn't run from the package root.

**After new price data:** GitHub Actions runs `price_fetcher.py` then `dbt run` automatically every weekday at 4:30 PM ET (`.github/workflows/daily_prices.yml`). dbt runs in CI using a dynamically created `~/.dbt/profiles.yml` built from the `SUPABASE_DB_PASSWORD` GitHub secret (separate from `SUPABASE_KEY` — this is the direct PostgreSQL password). To rebuild marts manually: `dbt run`.

**Portfolio write functions live in `dashboard/app.py`, not the API.** `add_portfolio_lot()`, `add_sale()`, `fetch_ticker_metadata()`, and `backfill_ticker_prices()` are module-level functions in the dashboard — not cached, not in the API layer. `add_portfolio_lot()` auto-registers unknown tickers: checks `stocks` table, fetches metadata from Polygon `/v3/reference/tickers/{ticker}`, inserts into `stocks`, then backfills 365 days of price history via the per-ticker aggregates endpoint (`/v2/aggs/ticker/{ticker}/range/1/day/...`) before inserting the portfolio lot. `add_sale()` inserts into `sales` then does FIFO deduction from `portfolio` lots ordered by `purchase_date` ascending — partially consumed lots are updated, fully consumed lots are deleted.

**`realized_pnl` uses weighted average cost, not FIFO.** Cost basis is `sum(shares * purchase_price) / sum(shares)` per ticker+account across all buy lots at query time — not matched lot-by-lot. This is the average cost method. The FIFO matching only applies to which `portfolio` lot rows get deducted when a sale is recorded.

**Treemap color override (Market Movers tab):** Plotly's `px.treemap` averages a parent node's color from its children, which washes out sector/root headers toward the neutral midpoint. `dashboard/app.py` manually overrides `marker.colors` post-construction — leaf nodes (`id.count("/") == 2`) get a data-driven color via `sample_colorscale`, parent/root nodes get a fixed dark color. `HEATMAP_SCALE` stops must be `[val, color]` lists, not tuples — tuples break Plotly's `validate_colors`.

---

## API Endpoints (api/main.py — currently unused by the dashboard)

| Method | URL | Source |
|--------|-----|-------------|
| GET | `/portfolio/summary` | `portfolio_summary` table — single row |
| GET | `/portfolio/positions` | `portfolio_positions` table — all rows |
| GET | `/portfolio/sector` | `portfolio_sector_exposure` table — all rows |
| GET | `/portfolio/spy` | `portfolio_vs_spy` table — all rows |
| GET | `/market/movers` | `market_movers` table — top gainers/losers |
| GET | `/market/news` | Polygon `/v2/reference/news` proxy |
| GET | `/market/indicators` | FRED `series/observations` for FEDFUNDS, CPIAUCSL, GDP, UNRATE |

---

## Database Schema

Four source tables in Supabase (`uiocdjtwshxpqtlcgfel.supabase.co`), defined in `schema/stock_analysis_schema.sql`:

- **`stocks`** — 560 rows, parent table. Always seed before others.
- **`price_history`** — daily OHLCV, `UNIQUE(ticker, date)`, safe to re-run upserts
- **`fundamentals`** — quarterly financials, `UNIQUE(ticker, period)`, format `'2026-Q2'`
- **`portfolio`** — one row per buy lot (not per ticker), cost-basis source of truth

- **`sales`** — one row per sell transaction (`ticker`, `account`, `shares`, `sale_price`, `sale_date`). Written by the Sell Position form; `portfolio` lots are FIFO-deducted on each sale.

dbt mart tables (materialized as real tables in Supabase `public` schema):
- `portfolio_positions` — per buy lot: `ticker`, `company`, `sector`, `account`, `shares`, `purchase_price`, `current_price`, `cost_basis`, `current_value`, `unrealized_gain_loss`, `unrealized_gain_loss_pct`, `weighted_avg_cost`
- `portfolio_summary` — `total_market_value`, `total_cost_basis`, `total_gain_loss_dollars`, `portfolio_gain_loss_pct`, `num_positions`, `best_position_pct`, `worst_position_pct`, `as_of_date`
- `portfolio_sector_exposure` — `sector`, `sector_market_value`, `sector_gain_loss_dollars`, `allocation_pct`
- `portfolio_vs_spy` — `date`, `portfolio_idx`, `spy_idx`, `alpha`
- `market_movers` — `ticker`, `company`, `sector`, `date`, `open`, `close`, `change_dollars`, `change_pct`, `volume`
- `realized_pnl` — per sale: `ticker`, `company`, `sector`, `account`, `shares`, `sale_price`, `sale_date`, `avg_cost_per_share`, `realized_gain_loss`, `realized_gain_loss_pct`

---

## Phase Status

| Phase | What | Status |
|-------|------|--------|
| 1 | `ingestion/price_fetcher.py` — Polygon → Supabase | Complete |
| 1.5 | `ingestion/backfill.py` — historical price backfill | Complete |
| 2 | dbt staging + mart models | Complete |
| 3 | `analysis/portfolio_analyzer.py` — Claude tool use | Complete |
| 4 | `.github/workflows/daily_prices.yml` — weekday 4:30 PM ET cron | Complete |
| 5 | `dashboard/app.py` — Streamlit dashboard with tabs | Complete |
| 6 | `api/main.py` — FastAPI layer (later superseded — dashboard moved to direct Supabase calls) | Complete |
| 7 | Market Movers tab — Finviz-style sector treemap + gainers/losers tables | Complete |
| 7 | News tab — Polygon.io `/v2/reference/news` | Complete |
| 7 | Economic Indicators tab — FRED API (GDP, CPI, Fed funds rate, unemployment) | Complete |
| 7 | Analyzer tools for movers/news/macro data | Complete |
| 8 | Multi-turn conversation history in `analyze()` / CLI / dashboard chat | Complete |
| 9 | Add Position form — writes buy lot to Supabase, auto-registers new tickers via Polygon + backfills price history | Complete |
| 9 | Sell Position form — FIFO lot deduction from `portfolio`, records sale in `sales` table | Complete |
| 9 | `realized_pnl` dbt mart — weighted avg cost basis + per-sale gain/loss | Complete |
| 9 | `weighted_avg_cost` added to `portfolio_positions` mart | Complete |
| 10 | Realized P&L KPI card + total return (unrealized + realized) in Portfolio Summary tab | Next |

---

## Environment

- `.env` at project root: `SUPABASE_URL`, `SUPABASE_KEY`, `POLYGON_API_KEY`, `ANTHROPIC_API_KEY`, `FRED_API_KEY`
- GitHub Actions reads the same keys from repo secrets (never from `.env`)
- Python 3.12, venv at `.venv/`
- Dependencies: `supabase`, `python-dotenv`, `requests`, `anthropic`, `streamlit`, `plotly`, `pandas`, `fastapi`, `uvicorn`
