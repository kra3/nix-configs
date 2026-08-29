#!/usr/bin/env python3
"""
Ghostfolio market data scraper.

Scrapes mutual fund NAV data from:
  - Avanza (Swedish funds/stocks) — current price only
  - mfapi.in (Indian mutual funds) — current or full history

Pushes market data into Ghostfolio's PostgreSQL database directly.
Symbols are configured via a JSON config file.

Config format (symbols.json):
  [
    {
      "provider": "avanza",
      "symbol": "MY_FUND",
      "orderbook_id": "878733",
      "type": "fund"               # optional, default "fund". "stock" for stocks
    },
    {
      "provider": "mfapi",
      "symbol": "HDFC_FLEXI_CAP",
      "scheme_code": "118989"
    }
  ]

Required per entry: provider, symbol, and the provider-specific ID
  (orderbook_id for avanza, scheme_code for mfapi).
All other fields (name, isin, currency) are fetched from the provider API.

Usage:
  python scraper.py                          # scrape latest prices, push to DB
  python scraper.py --dry-run                # fetch and print, no DB
  python scraper.py --backfill               # load full history (mfapi only)
  python scraper.py --backfill --dry-run     # preview historical data
"""

import argparse
import json
import logging
import os
import uuid
from datetime import date, datetime
from pathlib import Path

import requests

logging.basicConfig(
    level=logging.DEBUG if os.getenv("DEBUG_LOGGING", "").lower() == "true" else logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("ghostfolio-scraper")

CONFIG_PATH = Path(os.getenv("CONFIG_PATH", "/srv/appdata/life/ghostfolio/scraper/symbols.json"))


# ---------------------------------------------------------------------------
# Avanza provider
# ---------------------------------------------------------------------------

AVANZA_FUND_URL = "https://www.avanza.se/_api/fund-guide/guide/{orderbook_id}"
AVANZA_STOCK_URL = "https://www.avanza.se/_api/market-guide/stock/{orderbook_id}"


def fetch_avanza_fund(orderbook_id: str) -> dict:
    resp = requests.get(
        AVANZA_FUND_URL.format(orderbook_id=orderbook_id),
        timeout=15,
    )
    resp.raise_for_status()
    data = resp.json()
    return {
        "name": data["name"],
        "isin": data["isin"],
        "currency": data.get("currency", "SEK"),
        "price": data["nav"],
        "date": data.get("navDate", date.today().isoformat()),
    }


def fetch_avanza_stock(orderbook_id: str) -> dict:
    resp = requests.get(
        AVANZA_STOCK_URL.format(orderbook_id=orderbook_id),
        timeout=15,
    )
    resp.raise_for_status()
    data = resp.json()
    return {
        "name": data["name"],
        "isin": data["isin"],
        "currency": data["listing"].get("currency", "SEK"),
        "price": data["quote"]["last"],
        "date": date.today().isoformat(),
    }


def fetch_avanza(symbol_cfg: dict) -> list[dict]:
    orderbook_id = symbol_cfg["orderbook_id"]
    kind = symbol_cfg.get("type", "fund")
    if kind == "stock":
        return [fetch_avanza_stock(orderbook_id)]
    return [fetch_avanza_fund(orderbook_id)]


def fetch_avanza_history(symbol_cfg: dict, since: date | None = None) -> list[dict]:
    # Avanza doesn't expose historical NAV via public API
    log.warning("Backfill not supported for Avanza, fetching latest only")
    return fetch_avanza(symbol_cfg)


# ---------------------------------------------------------------------------
# Indian MF provider (mfapi.in)
# ---------------------------------------------------------------------------

MFAPI_LATEST_URL = "https://api.mfapi.in/mf/{scheme_code}/latest"
MFAPI_ALL_URL = "https://api.mfapi.in/mf/{scheme_code}"


def _parse_mfapi_date(date_str: str) -> str:
    try:
        return datetime.strptime(date_str, "%d-%m-%Y").date().isoformat()
    except ValueError:
        return date.today().isoformat()


def _parse_mfapi_response(data: dict) -> tuple[dict, list[dict]]:
    """Returns (meta_info, list of price entries)."""
    meta = data.get("meta", {})
    info = {
        "name": meta.get("scheme_name", ""),
        "isin": meta.get("isin", ""),
        "currency": "INR",
    }
    return info, data.get("data", [])


def fetch_indian_mf(symbol_cfg: dict) -> list[dict]:
    scheme_code = symbol_cfg["scheme_code"]
    resp = requests.get(
        MFAPI_LATEST_URL.format(scheme_code=scheme_code),
        timeout=15,
    )
    resp.raise_for_status()
    info, nav_entries = _parse_mfapi_response(resp.json())
    if not nav_entries:
        return []
    entry = nav_entries[0]
    return [{
        **info,
        "price": float(entry.get("nav", 0)),
        "date": _parse_mfapi_date(entry.get("date", "")),
    }]


def fetch_indian_mf_history(symbol_cfg: dict, since: date | None = None) -> list[dict]:
    scheme_code = symbol_cfg["scheme_code"]
    resp = requests.get(
        MFAPI_ALL_URL.format(scheme_code=scheme_code),
        timeout=30,
    )
    resp.raise_for_status()
    info, nav_entries = _parse_mfapi_response(resp.json())
    results = []
    for entry in nav_entries:
        nav = entry.get("nav")
        if nav is None:
            continue
        parsed = _parse_mfapi_date(entry.get("date", ""))
        if since and datetime.strptime(parsed, "%Y-%m-%d").date() < since:
            continue
        results.append({
            **info,
            "price": float(nav),
            "date": parsed,
        })
    log.info("Fetched %d historical entries for scheme %s", len(results), scheme_code)
    return results


# ---------------------------------------------------------------------------
# Provider dispatch
# ---------------------------------------------------------------------------

PROVIDERS = {
    "avanza": fetch_avanza,
    "mfapi": fetch_indian_mf,
}

PROVIDERS_HISTORY = {
    "avanza": fetch_avanza_history,
    "mfapi": fetch_indian_mf_history,
}


# ---------------------------------------------------------------------------
# Database operations
# ---------------------------------------------------------------------------

def get_connection():
    import psycopg2
    return psycopg2.connect(os.environ["DATABASE_URL"])


def ensure_symbol_profile(conn, symbol: str, name: str, isin: str, currency: str, asset_sub_class: str):
    with conn.cursor() as cur:
        cur.execute(
            'SELECT id FROM "SymbolProfile" WHERE symbol = %s AND "dataSource" = \'MANUAL\'::"DataSource"',
            (symbol,),
        )
        if cur.fetchone():
            return
        cur.execute(
            """
            INSERT INTO "SymbolProfile"
                (id, "createdAt", "updatedAt", "dataSource", symbol, name, currency,
                 "assetClass", "assetSubClass", isin, countries, sectors, "symbolMapping")
            VALUES (%s, NOW(), NOW(), 'MANUAL'::"DataSource", %s, %s, %s,
                    'EQUITY'::"AssetClass", %s::"AssetSubClass", %s, '[]', '[]', NULL)
            """,
            (str(uuid.uuid4()), symbol, name, currency, asset_sub_class, isin),
        )
    conn.commit()
    log.info("Created symbol profile: %s (%s)", symbol, name)


def push_market_data(conn, symbol: str, market_price: float, date_str: str):
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO "MarketData" ("createdAt", date, id, symbol, "marketPrice", "dataSource", state)
            VALUES (NOW(), %s, %s, %s, %s, 'MANUAL'::"DataSource", 'CLOSE'::"MarketDataState")
            ON CONFLICT (date, symbol, "dataSource")
            DO UPDATE SET "marketPrice" = EXCLUDED."marketPrice", "createdAt" = NOW()
            """,
            (date_str, str(uuid.uuid4()), symbol, market_price),
        )
    conn.commit()


def push_market_data_batch(conn, symbol: str, entries: list[dict]):
    with conn.cursor() as cur:
        for entry in entries:
            cur.execute(
                """
                INSERT INTO "MarketData" ("createdAt", date, id, symbol, "marketPrice", "dataSource", state)
                VALUES (NOW(), %s, %s, %s, %s, 'MANUAL'::"DataSource", 'CLOSE'::"MarketDataState")
                ON CONFLICT (date, symbol, "dataSource")
                DO UPDATE SET "marketPrice" = EXCLUDED."marketPrice", "createdAt" = NOW()
                """,
                (entry["date"], str(uuid.uuid4()), symbol, entry["price"]),
            )
    conn.commit()
    log.info("Pushed %d entries for %s", len(entries), symbol)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Ghostfolio market data scraper")
    parser.add_argument("--dry-run", action="store_true", help="Fetch data and print, skip DB writes")
    parser.add_argument("--backfill", action="store_true", help="Load full price history (mfapi only)")
    parser.add_argument("--since", type=str, help="Backfill start date (YYYY-MM-DD), default 6 years ago")
    parser.add_argument("--config", type=str, help="Path to symbols.json (overrides CONFIG_PATH env)")
    args = parser.parse_args()

    since = None
    if args.backfill:
        if args.since:
            since = datetime.strptime(args.since, "%Y-%m-%d").date()
        else:
            since = date(date.today().year - 6, date.today().month, date.today().day)

    providers = PROVIDERS

    if args.backfill:
        providers = PROVIDERS_HISTORY
        log.info("Backfill mode: loading history since %s", since)

    config_path = Path(args.config) if args.config else CONFIG_PATH
    if not config_path.exists():
        log.error("Config not found: %s", config_path)
        return

    with open(config_path) as f:
        symbols = json.load(f)

    if not symbols:
        log.warning("No symbols configured")
        return

    conn = None
    if not args.dry_run:
        conn = get_connection()

    try:
        for sym in symbols:
            provider = sym.get("provider")
            gf_symbol = sym["symbol"]
            asset_sub_class = sym.get("asset_sub_class", "MUTUALFUND")

            if provider not in providers:
                log.error("Unknown provider %s for %s", provider, gf_symbol)
                continue

            try:
                entries = providers[provider](sym, since=since) if args.backfill else providers[provider](sym)
                if not entries:
                    log.warning("No data returned for %s", gf_symbol)
                    continue

                if args.dry_run:
                    log.info("Fetched %s: %d entries", gf_symbol, len(entries))
                    log.info("  name=%s isin=%s currency=%s", entries[0]["name"], entries[0]["isin"], entries[0]["currency"])
                    log.info("  latest: %s %s on %s", entries[0]["price"], entries[0]["currency"], entries[0]["date"])
                    if len(entries) > 1:
                        log.info("  oldest: %s %s on %s", entries[-1]["price"], entries[-1]["currency"], entries[-1]["date"])
                    continue

                ensure_symbol_profile(conn, gf_symbol, entries[0]["name"], entries[0]["isin"], entries[0]["currency"], asset_sub_class)

                if len(entries) == 1:
                    push_market_data(conn, gf_symbol, entries[0]["price"], entries[0]["date"])
                    log.info("Market data: %s = %s on %s", gf_symbol, entries[0]["price"], entries[0]["date"])
                else:
                    push_market_data_batch(conn, gf_symbol, entries)
            except Exception:
                log.exception("Failed to scrape %s", gf_symbol)
    finally:
        if conn:
            conn.close()

    mode = "backfill" if args.backfill else "latest"
    log.info("Scrape complete (%s%s)", mode, ", dry run" if args.dry_run else "")


if __name__ == "__main__":
    main()
