-- Synthetic portfolio positions for Finance Data Platform demo
-- 14 positions across 7 sectors, mixed P&L (~60% winners / 40% losers)
-- Purchase prices chosen so current prices produce realistic gains/losses
-- All tickers confirmed in the stocks table (seeded from finance.csv)

-- STEP 1: Seed SPY and QQQ into stocks (not in the original 560-ticker dataset)
-- Required for portfolio_vs_spy dbt mart. Price fetcher will pick them up automatically.
INSERT INTO stocks (ticker, company, sector, industry, theme, asset_type, exchange) VALUES
('SPY', 'SPDR S&P 500 ETF Trust',       NULL, NULL, 'S&P 500', 'ETF', 'NYQ'),
('QQQ', 'Invesco QQQ Trust',            NULL, NULL, 'S&P 500', 'ETF', 'NMS')
ON CONFLICT (ticker) DO NOTHING;

-- STEP 2: Insert portfolio positions

INSERT INTO portfolio (ticker, account, shares, purchase_price, purchase_date) VALUES

-- TECHNOLOGY (4 positions) --------------------------------------------------
-- AAPL: bought pre-split run, solid winner
('AAPL', 'Robinhood',  15,  230.00, '2024-08-15'),
-- MSFT: bought during AI hype peak, modest winner
('MSFT', 'Robinhood',   8,  390.00, '2024-06-10'),
-- NVDA: bought before the big correction, underwater now
('NVDA', 'Robinhood',  20,  290.00, '2024-03-20'),
-- AMD: bought near 52w high, significant loser
('AMD',  'Robinhood',   5,  620.00, '2024-07-01'),

-- COMMUNICATION SERVICES (2 positions) ----------------------------------------
-- META: bought during dip, strong winner
('META', 'Webull',     10,  480.00, '2024-01-12'),
-- GOOGL: bought recently, slight winner
('GOOGL','Webull',     12,  360.00, '2024-11-05'),

-- CONSUMER CYCLICAL (2 positions) ---------------------------------------------
-- AMZN: bought at good entry, winner
('AMZN', 'Robinhood',  18,  195.00, '2023-10-20'),
-- TSLA: volatile, currently a loser
('TSLA', 'Robinhood',   8,  500.00, '2024-12-15'),

-- FINANCIAL SERVICES (2 positions) --------------------------------------------
-- JPM: steady climber, winner
('JPM',  'Webull',     10,  220.00, '2023-11-08'),
-- BAC: rate-sensitive, slight loser
('BAC',  'Webull',     50,   52.00, '2024-09-30'),

-- HEALTHCARE (2 positions) ----------------------------------------------------
-- JNJ: defensive hold, modest winner
('JNJ',  'Robinhood',  10,  210.00, '2024-02-14'),
-- PFE: post-COVID collapse, significant loser
('PFE',  'Robinhood', 100,   35.00, '2024-01-20'),

-- ENERGY (1 position) ---------------------------------------------------------
-- XOM: energy bull thesis, winner
('XOM',  'Webull',     15,  115.00, '2023-09-15'),

-- INDUSTRIALS (1 position) ----------------------------------------------------
-- RTX: defense/aerospace, winner
('RTX',  'Webull',     12,  130.00, '2023-12-01');

-- Expected P&L summary (using prices from finance.csv snapshot):
--
-- WINNERS  (current > purchase):
--   AAPL   $230 → $312  +35.9%
--   META   $480 → $635  +32.3%
--   AMZN   $195 → $274  +40.5%
--   JPM    $220 → $297  +34.9%
--   JNJ    $210 → $231  +9.9%
--   XOM    $115 → $147  +27.8%
--   RTX    $130 → $179  +37.7%
--   GOOGL  $360 → $390  +8.4%
--   MSFT   $390 → $427  +9.5%
--
-- LOSERS   (current < purchase):
--   NVDA   $290 → $214  -26.2%
--   AMD    $620 → $518  -16.5%
--   TSLA   $500 → $442  -11.6%
--   BAC    $52  → $51   -2.4%
--   PFE    $35  → $26   -25.3%
