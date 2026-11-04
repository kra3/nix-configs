// Fitness server: one small process, SQLite storage, per-user data keyed by the
// username an authenticating reverse proxy (Authelia via nginx) passes in a header.
//
// Storage is relational: one row per day, one row per set, one row of settings per
// user. The page still exchanges whole day documents; every write carries the
// version it was based on (If-Match) and a stale write gets 409 with the current
// copy, so two devices never silently overwrite each other.
use rusqlite::{params, Connection, OpenFlags, OptionalExtension};
use serde_json::{json, Map, Value};
use std::io::Read;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use std::{env, fs, process};
use tiny_http::{Header, Method, Request, Response, Server, StatusCode};

mod coach;
mod extras;
mod mcp;

const INDEX: &str = include_str!("../index.html");
const APP_JS: &str = include_str!("../app.js");
const APP_CSS: &str = include_str!("../app.css");
const SW: &str = include_str!("../sw.js");
const MANIFEST: &str = include_str!("../manifest.webmanifest");
const ICON_192: &[u8] = include_bytes!("../icon-192.png");
const ICON_512: &[u8] = include_bytes!("../icon-512.png");
const MAX_BODY: u64 = 262_144;
const MAX_IMPORT: u64 = 4 * 1024 * 1024;
const JSON: &str = "application/json";
// Script and styles are separate same-origin files, so nothing inline is allowed.
const CSP: &str = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; \
    connect-src 'self'; manifest-src 'self'; worker-src 'self'; object-src 'none'; \
    base-uri 'none'; form-action 'self'; frame-ancestors 'none'";

// Numeric day fields and their upper bounds (all must be >= 0).
const DAY_NUM: [(&str, f64); 7] = [
    ("weight", 500.0),
    ("waist", 300.0),
    ("kcal", 20_000.0),
    ("protein", 1_000.0),
    ("steps", 200_000.0),
    ("sleep", 24.0),
    ("bodyfat", 75.0),
];
const SETTING_NUM: [(&str, f64); 8] = [
    ("kcal", 20_000.0),
    ("protein", 1_000.0),
    ("steps", 200_000.0),
    ("sleep", 24.0),
    ("workouts", 7.0),
    ("height", 300.0),
    ("start_weight", 500.0),
    ("rest", 900.0),
];
const MAX_EXERCISES: usize = 30;
const MAX_SETS: usize = 20;
const MAX_NOTE: usize = 500;
const WORKOUTS: [&str; 2] = ["A", "B"];
const UNITS: [&str; 3] = ["kg", "reps", "sec"];
const MAX_PLAN_EXERCISES: usize = 15;
const MAX_NAME: usize = 60;

// Schema version 1: days, sets, settings.
const SCHEMA_1: &str = "
CREATE TABLE days(
  user TEXT NOT NULL, date TEXT NOT NULL,
  weight REAL, waist REAL, kcal REAL, protein REAL, steps REAL, sleep REAL,
  note TEXT, workout TEXT CHECK (workout IN ('A', 'B')),
  version INTEGER NOT NULL, updated INTEGER NOT NULL,
  PRIMARY KEY (user, date)) WITHOUT ROWID;
CREATE TABLE sets(
  user TEXT NOT NULL, date TEXT NOT NULL, exercise TEXT NOT NULL, idx INTEGER NOT NULL,
  kg REAL, reps REAL NOT NULL,
  PRIMARY KEY (user, date, exercise, idx),
  FOREIGN KEY (user, date) REFERENCES days(user, date) ON DELETE CASCADE) WITHOUT ROWID;
CREATE TABLE settings(
  user TEXT NOT NULL PRIMARY KEY,
  kcal REAL, protein REAL, steps REAL, sleep REAL, workouts REAL,
  height REAL, start_weight REAL, rest REAL,
  version INTEGER NOT NULL, updated INTEGER NOT NULL) WITHOUT ROWID;
PRAGMA user_version = 1;";

// Schema version 2: each user's workout plan (A/B exercise lists), editable in the page.
const SCHEMA_2: &str = "
CREATE TABLE plans(
  user TEXT NOT NULL PRIMARY KEY,
  version INTEGER NOT NULL, updated INTEGER NOT NULL) WITHOUT ROWID;
CREATE TABLE plan_exercises(
  user TEXT NOT NULL, workout TEXT NOT NULL CHECK (workout IN ('A', 'B')), pos INTEGER NOT NULL,
  key TEXT NOT NULL, name TEXT NOT NULL, sets INTEGER NOT NULL, lo INTEGER NOT NULL, hi INTEGER NOT NULL,
  unit TEXT NOT NULL CHECK (unit IN ('kg', 'reps', 'sec')),
  PRIMARY KEY (user, workout, pos),
  UNIQUE (user, workout, key),
  FOREIGN KEY (user) REFERENCES plans(user) ON DELETE CASCADE) WITHOUT ROWID;
PRAGMA user_version = 2;";

// Schema version 3: per-exercise weight step (kg) for progression suggestions.
const SCHEMA_3: &str = "
ALTER TABLE plan_exercises ADD COLUMN inc REAL;
PRAGMA user_version = 3;";

// Schema version 4: sex for the waist-to-height body-fat estimate (RFM), which
// uses a different constant for men and women.
const SCHEMA_4: &str = "
ALTER TABLE settings ADD COLUMN sex TEXT CHECK (sex IN ('m', 'f'));
PRAGMA user_version = 4;";

// Schema version 5: body fat % per day, as measured (e.g. by the Withings scale).
const SCHEMA_5: &str = "
ALTER TABLE days ADD COLUMN bodyfat REAL;
PRAGMA user_version = 5;";

// Migrations run in order, each in its own transaction, from the stored user_version.
// Schema version 6 (coach profile, proposals, coach log) lives in coach.rs, version 7
// (blood tests, cardio, photo names) in extras.rs.
const MIGRATIONS: [&str; 7] = [SCHEMA_1, SCHEMA_2, SCHEMA_3, SCHEMA_4, SCHEMA_5, coach::SCHEMA_6, extras::SCHEMA_7];

fn init(c: &Connection) -> rusqlite::Result<()> {
    c.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;")?;
    let v: i64 = c.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    if v as usize > MIGRATIONS.len() {
        eprintln!("database schema version {v} is newer than this build understands");
        process::exit(1);
    }
    for m in &MIGRATIONS[v as usize..] {
        c.execute_batch(&format!("BEGIN; {m} COMMIT;"))?;
    }
    Ok(())
}

fn open(path: &str) -> Connection {
    let c = Connection::open(path).unwrap_or_else(|e| {
        eprintln!("cannot open database {path}: {e}");
        process::exit(1);
    });
    init(&c).unwrap_or_else(|e| {
        eprintln!("cannot initialise database {path}: {e}");
        process::exit(1);
    });
    c
}

// Read-only, no migrations: for the backup job, which must not change the
// live database's schema under a running service.
fn open_ro(path: &str) -> Connection {
    Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX).unwrap_or_else(|e| {
        eprintln!("cannot open database {path}: {e}");
        process::exit(1);
    })
}

fn now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

fn valid_date(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() == 10
        && b.iter()
            .enumerate()
            .all(|(i, c)| if i == 4 || i == 7 { *c == b'-' } else { c.is_ascii_digit() })
}

fn valid_key(s: &str) -> bool {
    !s.is_empty() && s.len() <= 32 && s.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_' || c == b'-')
}

/* ---------- validation: JSON document -> rows ---------- */

#[derive(Debug, PartialEq)]
struct Day {
    nums: [Option<f64>; 7],
    note: Option<String>,
    workout: Option<String>,
    sets: Vec<(String, i64, Option<f64>, f64)>,
}

fn num_field(v: Option<&Value>, name: &str, max: f64) -> Result<Option<f64>, String> {
    match v {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Number(n)) => match n.as_f64() {
            Some(x) if x.is_finite() && (0.0..=max).contains(&x) => Ok(Some(x)),
            _ => Err(format!("{name} must be between 0 and {max}")),
        },
        Some(_) => Err(format!("{name} must be a number")),
    }
}

fn parse_day(v: &Value) -> Result<Day, String> {
    let o = v.as_object().ok_or("object expected")?;
    for k in o.keys() {
        let known = k == "date" || k == "note" || k == "workout" || k == "sets" || DAY_NUM.iter().any(|(n, _)| n == k);
        if !known {
            return Err(format!("unknown field {k}"));
        }
    }
    let mut nums = [None; 7];
    for (i, (name, max)) in DAY_NUM.iter().enumerate() {
        nums[i] = num_field(o.get(*name), name, *max)?;
    }
    let note = match o.get("note") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) if s.chars().count() <= MAX_NOTE => Some(s.trim().to_string()).filter(|s| !s.is_empty()),
        Some(_) => return Err(format!("note must be text of at most {MAX_NOTE} characters")),
    };
    let workout = match o.get("workout") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) if s == "A" || s == "B" => Some(s.clone()),
        Some(_) => return Err("workout must be A or B".into()),
    };
    let mut sets = Vec::new();
    match o.get("sets") {
        None | Some(Value::Null) => {}
        Some(Value::Object(m)) => {
            if m.len() > MAX_EXERCISES {
                return Err("too many exercises".into());
            }
            for (ex, list) in m {
                if !valid_key(ex) {
                    return Err(format!("bad exercise name {ex}"));
                }
                let arr = list.as_array().ok_or_else(|| format!("sets for {ex} must be a list"))?;
                if arr.len() > MAX_SETS {
                    return Err(format!("too many sets for {ex}"));
                }
                for (i, s) in arr.iter().enumerate() {
                    let pair = s.as_array().filter(|p| p.len() == 2).ok_or_else(|| format!("set {} of {ex} must be [kg, reps]", i + 1))?;
                    let kg = num_field(pair.first(), "kg", 1_000.0)?;
                    let reps = num_field(pair.get(1), "reps", 1_000.0)?.ok_or_else(|| format!("set {} of {ex} needs reps", i + 1))?;
                    sets.push((ex.clone(), i as i64, kg, reps));
                }
            }
        }
        Some(_) => return Err("sets must be an object".into()),
    }
    Ok(Day { nums, note, workout, sets })
}

struct Settings {
    nums: [Option<f64>; 8],
    sex: Option<String>,
}

fn parse_settings(v: &Value) -> Result<Settings, String> {
    let o = v.as_object().ok_or("object expected")?;
    if let Some(k) = o.keys().find(|k| *k != "sex" && !SETTING_NUM.iter().any(|(n, _)| n == k)) {
        return Err(format!("unknown field {k}"));
    }
    let mut nums = [None; 8];
    for (i, (name, max)) in SETTING_NUM.iter().enumerate() {
        nums[i] = num_field(o.get(*name), name, *max)?;
    }
    let sex = match o.get("sex") {
        None | Some(Value::Null) => None,
        Some(Value::String(x)) if x == "m" || x == "f" => Some(x.clone()),
        Some(_) => return Err("sex must be m or f".into()),
    };
    Ok(Settings { nums, sex })
}

#[derive(Debug, PartialEq)]
struct PlanEx {
    workout: &'static str,
    key: String,
    name: String,
    sets: i64,
    lo: i64,
    hi: i64,
    unit: String,
    inc: Option<f64>,
}

fn int_field(o: &Map<String, Value>, k: &str, lo: i64, hi: i64) -> Result<i64, String> {
    o.get(k).and_then(Value::as_i64).filter(|x| (lo..=hi).contains(x)).ok_or_else(|| format!("{k} must be a whole number from {lo} to {hi}"))
}

// {"A": [{"k", "n", "sets", "lo", "hi", "u", "inc"?}, ...], "B": [...]}
fn parse_plan(v: &Value) -> Result<Vec<PlanEx>, String> {
    let o = v.as_object().ok_or("object expected")?;
    if let Some(k) = o.keys().find(|k| !WORKOUTS.contains(&k.as_str())) {
        return Err(format!("unknown workout {k}"));
    }
    let mut out = Vec::new();
    for w in WORKOUTS {
        let Some(list) = o.get(w) else { continue };
        let list = list.as_array().ok_or_else(|| format!("workout {w} must be a list"))?;
        if list.len() > MAX_PLAN_EXERCISES {
            return Err(format!("too many exercises in workout {w}"));
        }
        let mut seen = Vec::new();
        for (i, e) in list.iter().enumerate() {
            let at = format!("workout {w}, exercise {}", i + 1);
            let e = e.as_object().ok_or_else(|| format!("{at} must be an object"))?;
            if let Some(k) = e.keys().find(|k| !["k", "n", "sets", "lo", "hi", "u", "inc"].contains(&k.as_str())) {
                return Err(format!("{at}: unknown field {k}"));
            }
            let key = e.get("k").and_then(Value::as_str).filter(|k| valid_key(k)).ok_or_else(|| format!("{at}: bad key"))?;
            if seen.contains(&key) {
                return Err(format!("{at}: {key} appears twice"));
            }
            seen.push(key);
            let name = e.get("n").and_then(Value::as_str).map(str::trim).filter(|n| !n.is_empty() && n.chars().count() <= MAX_NAME);
            let name = name.ok_or_else(|| format!("{at}: name must be 1 to {MAX_NAME} characters"))?;
            let unit = e.get("u").and_then(Value::as_str).filter(|u| UNITS.contains(u)).ok_or_else(|| format!("{at}: unit must be kg, reps or sec"))?;
            let sets = int_field(e, "sets", 1, 10).map_err(|m| format!("{at}: {m}"))?;
            let lo = int_field(e, "lo", 1, 600).map_err(|m| format!("{at}: {m}"))?;
            let hi = int_field(e, "hi", 1, 600).map_err(|m| format!("{at}: {m}"))?;
            if lo > hi {
                return Err(format!("{at}: range low is above high"));
            }
            let inc = num_field(e.get("inc"), "inc", 50.0).map_err(|m| format!("{at}: {m}"))?;
            if inc == Some(0.0) {
                return Err(format!("{at}: inc must be above 0"));
            }
            out.push(PlanEx { workout: w, key: key.into(), name: name.into(), sets, lo, hi, unit: unit.into(), inc });
        }
    }
    Ok(out)
}

/* ---------- rows -> JSON document ---------- */

// Whole numbers go back out as integers so 12 reps stays 12, not 12.0.
fn num_value(x: f64) -> Value {
    if x.fract() == 0.0 && x.abs() < 1e15 {
        json!(x as i64)
    } else {
        json!(x)
    }
}

fn put_num(m: &mut Map<String, Value>, k: &str, v: Option<f64>) {
    if let Some(x) = v {
        m.insert(k.to_string(), num_value(x));
    }
}

fn get_day(c: &Connection, user: &str, date: &str) -> rusqlite::Result<Option<(i64, Value)>> {
    let row = c
        .query_row(
            "SELECT weight, waist, kcal, protein, steps, sleep, bodyfat, note, workout, version FROM days WHERE user = ?1 AND date = ?2",
            params![user, date],
            |r| {
                let mut nums = [None; 7];
                for (i, n) in nums.iter_mut().enumerate() {
                    *n = r.get::<_, Option<f64>>(i)?;
                }
                Ok((nums, r.get::<_, Option<String>>(7)?, r.get::<_, Option<String>>(8)?, r.get::<_, i64>(9)?))
            },
        )
        .optional()?;
    let Some((nums, note, workout, version)) = row else { return Ok(None) };
    let mut m = Map::new();
    m.insert("date".into(), json!(date));
    for (i, (name, _)) in DAY_NUM.iter().enumerate() {
        put_num(&mut m, name, nums[i]);
    }
    if let Some(n) = note {
        m.insert("note".into(), json!(n));
    }
    if let Some(w) = workout {
        m.insert("workout".into(), json!(w));
    }
    let mut st = c.prepare_cached("SELECT exercise, kg, reps FROM sets WHERE user = ?1 AND date = ?2 ORDER BY exercise, idx")?;
    let rows = st.query_map(params![user, date], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<f64>>(1)?, r.get::<_, f64>(2)?)))?;
    let mut sets = Map::new();
    for row in rows {
        let (ex, kg, reps) = row?;
        let entry = json!([kg.map(num_value).unwrap_or(Value::Null), num_value(reps)]);
        if let Value::Array(list) = sets.entry(ex).or_insert_with(|| json!([])) {
            list.push(entry);
        }
    }
    if !sets.is_empty() {
        m.insert("sets".into(), Value::Object(sets));
    }
    Ok(Some((version, Value::Object(m))))
}

fn get_settings(c: &Connection, user: &str) -> rusqlite::Result<Option<(i64, Value)>> {
    c.query_row(
        "SELECT kcal, protein, steps, sleep, workouts, height, start_weight, rest, version, sex FROM settings WHERE user = ?1",
        params![user],
        |r| {
            let mut m = Map::new();
            for (i, (name, _)) in SETTING_NUM.iter().enumerate() {
                put_num(&mut m, name, r.get::<_, Option<f64>>(i)?);
            }
            if let Some(x) = r.get::<_, Option<String>>(9)? {
                m.insert("sex".into(), json!(x));
            }
            Ok((r.get::<_, i64>(8)?, Value::Object(m)))
        },
    )
    .optional()
}

fn get_plan(c: &Connection, user: &str) -> rusqlite::Result<Option<(i64, Value)>> {
    let Some(version) = c.query_row("SELECT version FROM plans WHERE user = ?1", params![user], |r| r.get::<_, i64>(0)).optional()? else {
        return Ok(None);
    };
    let mut st = c.prepare_cached("SELECT workout, key, name, sets, lo, hi, unit, inc FROM plan_exercises WHERE user = ?1 ORDER BY workout, pos")?;
    let rows = st.query_map(params![user], |r| {
        let mut e = json!({ "k": r.get::<_, String>(1)?, "n": r.get::<_, String>(2)?, "sets": r.get::<_, i64>(3)?,
                            "lo": r.get::<_, i64>(4)?, "hi": r.get::<_, i64>(5)?, "u": r.get::<_, String>(6)? });
        if let (Some(inc), Value::Object(m)) = (r.get::<_, Option<f64>>(7)?, &mut e) {
            m.insert("inc".into(), num_value(inc));
        }
        Ok((r.get::<_, String>(0)?, e))
    })?;
    let mut m = Map::new();
    for w in WORKOUTS {
        m.insert(w.into(), json!([]));
    }
    for row in rows {
        let (w, e) = row?;
        if let Some(Value::Array(list)) = m.get_mut(&w) {
            list.push(e);
        }
    }
    Ok(Some((version, Value::Object(m))))
}

fn list_dates(c: &Connection, user: &str) -> rusqlite::Result<Vec<String>> {
    let mut st = c.prepare_cached("SELECT date FROM days WHERE user = ?1 ORDER BY date")?;
    let rows = st.query_map(params![user], |r| r.get::<_, String>(0))?;
    rows.collect()
}

fn get_doc(c: &Connection, user: &str, id: &str) -> rusqlite::Result<Option<(i64, Value)>> {
    match id {
        "settings" => get_settings(c, user),
        "plan" => get_plan(c, user),
        "profile" => coach::get_profile(c, user),
        _ => get_day(c, user, id),
    }
}

// Ids that are not days.
const SINGLETONS: [&str; 3] = ["settings", "plan", "profile"];

/* ---------- writes (version-checked) ---------- */

// Ok(Some(new_version)) on success, Ok(None) when `base` is not the current version.
fn write_day(c: &Connection, user: &str, date: &str, d: &Day, base: i64) -> rusqlite::Result<Option<i64>> {
    let tx = c.unchecked_transaction()?;
    let cur: Option<i64> = tx.query_row("SELECT version FROM days WHERE user = ?1 AND date = ?2", params![user, date], |r| r.get(0)).optional()?;
    if cur.unwrap_or(0) != base {
        return Ok(None);
    }
    let version = base + 1;
    let n = &d.nums;
    tx.execute(
        "INSERT INTO days(user, date, weight, waist, kcal, protein, steps, sleep, bodyfat, note, workout, version, updated)
         VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
         ON CONFLICT(user, date) DO UPDATE SET weight = excluded.weight, waist = excluded.waist, kcal = excluded.kcal,
           protein = excluded.protein, steps = excluded.steps, sleep = excluded.sleep, bodyfat = excluded.bodyfat,
           note = excluded.note, workout = excluded.workout, version = excluded.version, updated = excluded.updated",
        params![user, date, n[0], n[1], n[2], n[3], n[4], n[5], n[6], d.note, d.workout, version, now()],
    )?;
    tx.execute("DELETE FROM sets WHERE user = ?1 AND date = ?2", params![user, date])?;
    {
        let mut st = tx.prepare_cached("INSERT INTO sets(user, date, exercise, idx, kg, reps) VALUES(?1, ?2, ?3, ?4, ?5, ?6)")?;
        for (ex, idx, kg, reps) in &d.sets {
            st.execute(params![user, date, ex, idx, kg, reps])?;
        }
    }
    tx.commit()?;
    Ok(Some(version))
}

fn write_settings(c: &Connection, user: &str, st: &Settings, base: i64) -> rusqlite::Result<Option<i64>> {
    let s = &st.nums;
    let tx = c.unchecked_transaction()?;
    let cur: Option<i64> = tx.query_row("SELECT version FROM settings WHERE user = ?1", params![user], |r| r.get(0)).optional()?;
    if cur.unwrap_or(0) != base {
        return Ok(None);
    }
    let version = base + 1;
    tx.execute(
        "INSERT INTO settings(user, kcal, protein, steps, sleep, workouts, height, start_weight, rest, version, updated, sex)
         VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
         ON CONFLICT(user) DO UPDATE SET kcal = excluded.kcal, protein = excluded.protein, steps = excluded.steps,
           sleep = excluded.sleep, workouts = excluded.workouts, height = excluded.height,
           start_weight = excluded.start_weight, rest = excluded.rest, version = excluded.version, updated = excluded.updated,
           sex = excluded.sex",
        params![user, s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7], version, now(), st.sex],
    )?;
    tx.commit()?;
    Ok(Some(version))
}

fn write_plan(c: &Connection, user: &str, p: &[PlanEx], base: i64) -> rusqlite::Result<Option<i64>> {
    let tx = c.unchecked_transaction()?;
    let cur: Option<i64> = tx.query_row("SELECT version FROM plans WHERE user = ?1", params![user], |r| r.get(0)).optional()?;
    if cur.unwrap_or(0) != base {
        return Ok(None);
    }
    let version = base + 1;
    tx.execute(
        "INSERT INTO plans(user, version, updated) VALUES(?1, ?2, ?3)
         ON CONFLICT(user) DO UPDATE SET version = excluded.version, updated = excluded.updated",
        params![user, version, now()],
    )?;
    tx.execute("DELETE FROM plan_exercises WHERE user = ?1", params![user])?;
    {
        let mut st = tx.prepare_cached(
            "INSERT INTO plan_exercises(user, workout, pos, key, name, sets, lo, hi, unit, inc) VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
        )?;
        let mut pos = [0i64; 2];
        for e in p {
            let i = WORKOUTS.iter().position(|w| *w == e.workout).unwrap_or(0);
            st.execute(params![user, e.workout, pos[i], e.key, e.name, e.sets, e.lo, e.hi, e.unit, e.inc])?;
            pos[i] += 1;
        }
    }
    tx.commit()?;
    Ok(Some(version))
}

// Ok(true) when the day is gone afterwards (deleted now or already absent),
// Ok(false) when it exists at a different version than `base`.
fn delete_day(c: &Connection, user: &str, date: &str, base: i64) -> rusqlite::Result<bool> {
    let tx = c.unchecked_transaction()?;
    let cur: Option<i64> = tx.query_row("SELECT version FROM days WHERE user = ?1 AND date = ?2", params![user, date], |r| r.get(0)).optional()?;
    match cur {
        None => Ok(true),
        Some(v) if v != base => Ok(false),
        Some(_) => {
            tx.execute("DELETE FROM days WHERE user = ?1 AND date = ?2", params![user, date])?;
            tx.commit()?;
            Ok(true)
        }
    }
}

/* ---------- import / export ---------- */

#[derive(Debug, Default, PartialEq)]
struct ImportReport {
    imported: u32,
    skipped: u32,
    invalid: u32,
}

// Accepts {"YYYY-MM-DD": {...day...}, "settings": {...}} (this server's export and
// the old claude.ai tracker's format). Existing days and settings are kept.
fn import_map(c: &Connection, user: &str, v: &Value) -> Result<ImportReport, String> {
    let map = v.as_object().ok_or("expected an object keyed by date")?;
    let mut rep = ImportReport::default();
    for (id, d) in map {
        let res = if id == "settings" {
            match parse_settings(d) {
                Ok(s) => write_settings(c, user, &s, 0).map_err(|e| e.to_string())?,
                Err(_) => {
                    rep.invalid += 1;
                    continue;
                }
            }
        } else if id == "plan" {
            match parse_plan(d) {
                Ok(p) => write_plan(c, user, &p, 0).map_err(|e| e.to_string())?,
                Err(_) => {
                    rep.invalid += 1;
                    continue;
                }
            }
        } else if id == "profile" {
            match coach::parse_profile(d) {
                Ok(p) => coach::write_profile(c, user, &p, 0).map_err(|e| e.to_string())?,
                Err(_) => {
                    rep.invalid += 1;
                    continue;
                }
            }
        } else if id == "coach_log" {
            let (ok, bad) = coach::import_log(c, user, d)?;
            rep.invalid += bad;
            if ok > 0 {
                rep.imported += 1;
            } else if bad == 0 {
                rep.skipped += 1;
            }
            continue;
        } else if id == "labs" || id == "cardio" {
            let (ok, dup, bad) = extras::import_list(c, user, id, d)?;
            rep.invalid += bad;
            if ok > 0 {
                rep.imported += 1;
            } else if dup > 0 {
                rep.skipped += 1;
            }
            continue;
        } else if valid_date(id) {
            match parse_day(d) {
                Ok(day) => write_day(c, user, id, &day, 0).map_err(|e| e.to_string())?,
                Err(_) => {
                    rep.invalid += 1;
                    continue;
                }
            }
        } else {
            rep.invalid += 1;
            continue;
        };
        if res.is_some() {
            rep.imported += 1;
        } else {
            rep.skipped += 1;
        }
    }
    Ok(rep)
}

fn export_map(c: &Connection, user: &str) -> rusqlite::Result<Value> {
    let mut m = Map::new();
    for d in list_dates(c, user)? {
        if let Some((_, doc)) = get_day(c, user, &d)? {
            m.insert(d, doc);
        }
    }
    for id in SINGLETONS {
        if let Some((_, d)) = get_doc(c, user, id)? {
            m.insert(id.into(), d);
        }
    }
    let log = coach::export_log(c, user)?;
    if log.as_array().is_some_and(|l| !l.is_empty()) {
        m.insert("coach_log".into(), log);
    }
    extras::export_lists(c, user, &mut m)?;
    Ok(Value::Object(m))
}

// fitness backup <file>: a consistent copy of the live database (VACUUM INTO),
// written beside the target and renamed into place.
fn backup(c: &Connection, dest: &str) -> Result<(), String> {
    let tmp = format!("{dest}.tmp");
    let _ = fs::remove_file(&tmp);
    c.execute("VACUUM INTO ?1", params![tmp]).map_err(|e| e.to_string())?;
    fs::rename(&tmp, dest).map_err(|e| e.to_string())
}

/* ---------- HTTP ---------- */

struct Reply {
    code: u16,
    ctype: &'static str,
    body: Vec<u8>,
    extra: Vec<(&'static str, String)>,
}

fn reply(code: u16, v: Value) -> Reply {
    Reply { code, ctype: JSON, body: v.to_string().into_bytes(), extra: vec![] }
}

fn err(code: u16, msg: &str) -> Reply {
    reply(code, json!({ "error": msg }))
}

fn db_err(e: rusqlite::Error) -> Reply {
    eprintln!("database error: {e}");
    err(500, "database error")
}

fn conflict(c: &Connection, user: &str, id: &str) -> Reply {
    match get_doc(c, user, id) {
        Ok(cur) => reply(409, json!({ "error": "conflict", "current": cur.map(|(v, d)| json!({ "version": v, "data": d })) })),
        Err(e) => db_err(e),
    }
}

// If-Match carries the version the client's edit was based on; 0 means "new".
fn parse_version(h: Option<&str>) -> Option<i64> {
    let s = h?.trim().trim_start_matches("W/").trim_matches('"');
    s.parse::<i64>().ok().filter(|v| *v >= 0)
}

fn api(c: &Connection, user: &str, method: &Method, path: &str, query: &str, if_match: Option<&str>, body: &[u8]) -> Reply {
    if path.starts_with("/api/coach/") {
        return coach::api(c, user, method, path, query, body);
    }
    if ["/api/labs", "/api/cardio", "/api/photos"].iter().any(|p| path == *p || path.starts_with(&format!("{p}/"))) {
        return extras::api(c, user, method, path, query, body);
    }
    match (method, path) {
        (Method::Get, "/api/log") => {
            let mut docs = Vec::new();
            let dates = match list_dates(c, user) {
                Ok(d) => d,
                Err(e) => return db_err(e),
            };
            for id in dates.iter().map(String::as_str).chain(SINGLETONS) {
                match get_doc(c, user, id) {
                    Ok(Some((v, d))) => docs.push(json!({ "id": id, "version": v, "data": d })),
                    Ok(None) => {}
                    Err(e) => return db_err(e),
                }
            }
            reply(200, json!({ "docs": docs }))
        }
        // The signed-in user, so the page can keep each account's offline copy apart.
        (Method::Get, "/api/me") => reply(200, json!({ "user": user })),
        (Method::Get, "/api/export") => match export_map(c, user) {
            Ok(v) => Reply {
                code: 200,
                ctype: JSON,
                body: serde_json::to_vec_pretty(&v).unwrap_or_default(),
                extra: vec![("Content-Disposition", "attachment; filename=\"fitness-export.json\"".into())],
            },
            Err(e) => db_err(e),
        },
        (Method::Post, "/api/import") => {
            let v: Value = match serde_json::from_slice(body) {
                Ok(v) => v,
                Err(_) => return err(400, "bad json"),
            };
            match import_map(c, user, &v) {
                Ok(r) => reply(200, json!({ "imported": r.imported, "skipped": r.skipped, "invalid": r.invalid })),
                Err(e) => err(400, &e),
            }
        }
        (Method::Put, p) | (Method::Delete, p) if p.starts_with("/api/log/") => {
            let id = &p["/api/log/".len()..];
            if !SINGLETONS.contains(&id) && !valid_date(id) {
                return err(400, "bad id");
            }
            let Some(base) = parse_version(if_match) else {
                return err(428, "If-Match with the base version is required");
            };
            if *method == Method::Delete {
                if SINGLETONS.contains(&id) {
                    return err(400, "only days can be deleted");
                }
                return match delete_day(c, user, id, base) {
                    Ok(true) => reply(200, json!({ "deleted": true })),
                    Ok(false) => conflict(c, user, id),
                    Err(e) => db_err(e),
                };
            }
            let v: Value = match serde_json::from_slice(body) {
                Ok(v) => v,
                Err(_) => return err(400, "bad json"),
            };
            let res = if id == "settings" {
                match parse_settings(&v) {
                    Ok(s) => write_settings(c, user, &s, base),
                    Err(e) => return err(400, &e),
                }
            } else if id == "plan" {
                match parse_plan(&v) {
                    Ok(p) => write_plan(c, user, &p, base),
                    Err(e) => return err(400, &e),
                }
            } else if id == "profile" {
                match coach::parse_profile(&v) {
                    Ok(p) => coach::write_profile(c, user, &p, base),
                    Err(e) => return err(400, &e),
                }
            } else {
                match parse_day(&v) {
                    Ok(d) => write_day(c, user, id, &d, base),
                    Err(e) => return err(400, &e),
                }
            };
            match res {
                Ok(Some(version)) => reply(200, json!({ "version": version })),
                Ok(None) => conflict(c, user, id),
                Err(e) => db_err(e),
            }
        }
        _ => err(404, "not found"),
    }
}

fn static_file(path: &str) -> Option<(&'static str, &'static [u8])> {
    Some(match path {
        "/" | "/index.html" => ("text/html; charset=utf-8", INDEX.as_bytes()),
        "/app.js" => ("text/javascript; charset=utf-8", APP_JS.as_bytes()),
        "/app.css" => ("text/css; charset=utf-8", APP_CSS.as_bytes()),
        "/sw.js" => ("text/javascript; charset=utf-8", SW.as_bytes()),
        "/manifest.webmanifest" => ("application/manifest+json", MANIFEST.as_bytes()),
        "/icon-192.png" => ("image/png", ICON_192),
        "/icon-512.png" => ("image/png", ICON_512),
        _ => return None,
    })
}

fn respond(rq: Request, r: Reply) {
    let h = |k: &str, v: &str| Header::from_bytes(k.as_bytes(), v.as_bytes()).unwrap();
    // A reply may set its own Cache-Control (private photos); otherwise no-store.
    let own_cache = r.extra.iter().any(|(k, _)| *k == "Cache-Control");
    let mut resp = Response::from_data(r.body)
        .with_status_code(StatusCode(r.code))
        .with_header(h("Content-Type", r.ctype));
    if !own_cache {
        resp = resp.with_header(h("Cache-Control", "no-store"));
    }
    let mut resp = resp
        .with_header(h("X-Content-Type-Options", "nosniff"))
        .with_header(h("Referrer-Policy", "no-referrer"));
    if r.ctype.starts_with("text/html") {
        resp = resp.with_header(h("Content-Security-Policy", CSP));
    }
    for (k, v) in r.extra {
        resp = resp.with_header(h(k, &v));
    }
    let _ = rq.respond(resp);
}

fn header_of<'a>(rq: &'a Request, name: &str) -> Option<&'a str> {
    rq.headers().iter().find(|h| h.field.as_str().as_str().eq_ignore_ascii_case(name)).map(|h| h.value.as_str())
}

fn user_of(rq: &Request, header: &str, fallback: Option<&str>) -> Option<String> {
    match header_of(rq, header).map(str::trim) {
        Some(v) if !v.is_empty() && v.len() <= 128 => Some(v.to_string()),
        _ => fallback.map(str::to_string),
    }
}

fn handle(mut rq: Request, db: &Mutex<Connection>, header: &str, fallback: Option<&str>) {
    let url = rq.url().to_string();
    let (path, query) = match url.split_once('?') {
        Some((p, q)) => (p.to_string(), q.to_string()),
        None => (url.clone(), String::new()),
    };
    let method = rq.method().clone();
    // Paths are matched as raw bytes, so refuse anything a proxy could have
    // normalised differently: dot segments, empty segments, percent-encoding.
    if path.contains("/.") || path.contains("//") || path.contains('%') {
        return respond(rq, err(400, "bad path"));
    }

    if method == Method::Get {
        if let Some((ctype, body)) = static_file(&path) {
            return respond(rq, Reply { code: 200, ctype, body: body.to_vec(), extra: vec![] });
        }
        // Unauthenticated liveness check (nginx exposes only this path without
        // login): the process answers and the database is readable.
        if path == "/healthz" {
            let ok = db.lock().unwrap_or_else(|p| p.into_inner()).query_row("SELECT 1", [], |r| r.get::<_, i64>(0)).is_ok();
            let r = if ok { reply(200, json!({ "ok": true })) } else { err(503, "database unavailable") };
            return respond(rq, r);
        }
    }
    if !path.starts_with("/api/") {
        return respond(rq, err(404, "not found"));
    }
    let Some(user) = user_of(&rq, header, fallback) else {
        return respond(rq, err(401, "no user"));
    };
    // A cross-site form can POST, but only as form or text data; every POST the
    // page makes is JSON, so anything else is refused.
    // The one exception is the photo upload, a raw JPEG body (not a form type, so a
    // cross-site form cannot send it); its handler checks the JPEG magic bytes.
    let photo_upload = method == Method::Post && path == "/api/photos";
    let want = if photo_upload { "image/jpeg" } else { "application/json" };
    if method == Method::Post && !header_of(&rq, "Content-Type").is_some_and(|t| t.trim_start().starts_with(want)) {
        return respond(rq, err(415, if photo_upload { "JPEG image expected" } else { "JSON body expected" }));
    }
    // The page names the account a change was made for; if someone else is signed
    // in now (a shared device), the change is refused rather than written to them.
    if header_of(&rq, "X-Fitness-User").is_some_and(|u| !u.is_empty() && u != user) {
        return respond(rq, reply(403, json!({ "error": "signed in as another user", "user": user })));
    }
    let if_match = header_of(&rq, "If-Match").map(str::to_string);
    let limit = if photo_upload {
        extras::MAX_PHOTO
    } else if path == "/api/import" {
        MAX_IMPORT
    } else {
        MAX_BODY
    };
    let mut body = Vec::new();
    if rq.as_reader().take(limit + 1).read_to_end(&mut body).is_err() {
        return respond(rq, err(400, "read failed"));
    }
    if body.len() as u64 > limit {
        return respond(rq, err(413, "too large"));
    }
    let r = {
        let c = db.lock().unwrap_or_else(|p| p.into_inner());
        api(&c, &user, &method, &path, &query, if_match.as_deref(), &body)
    };
    respond(rq, r)
}

// Fills numeric day fields that are still empty (e.g. steps and sleep from a
// phone via Home Assistant). A value already logged, by hand or by an earlier
// run, is never changed. Returns the fields it set.
fn fill_day(c: &Connection, user: &str, date: &str, vals: &[(String, f64)]) -> Result<Vec<String>, String> {
    if !valid_date(date) {
        return Err(format!("bad date {date}"));
    }
    for (k, _) in vals {
        if !DAY_NUM.iter().any(|(n, _)| n == k) {
            return Err(format!("unknown field {k}"));
        }
    }
    // A concurrent write from the page bumps the version; read again and retry.
    for _ in 0..3 {
        let (base, cur) = get_day(c, user, date).map_err(|e| e.to_string())?.unwrap_or((0, json!({ "date": date })));
        let mut m = cur.as_object().cloned().unwrap_or_default();
        let mut set = Vec::new();
        for (k, v) in vals {
            if !m.contains_key(k) {
                m.insert(k.clone(), num_value(*v));
                set.push(k.clone());
            }
        }
        if set.is_empty() {
            return Ok(set);
        }
        let day = parse_day(&Value::Object(m))?;
        if write_day(c, user, date, &day, base).map_err(|e| e.to_string())?.is_some() {
            return Ok(set);
        }
    }
    Err("the day kept changing; try again".into())
}

fn fill_cli(db_path: &str, user: &str, date: &str, pairs: &[String]) {
    let mut vals = Vec::new();
    for p in pairs {
        let parsed = p.split_once('=').and_then(|(k, v)| v.trim().parse::<f64>().ok().map(|v| (k.trim().to_string(), v)));
        match parsed {
            Some(kv) => vals.push(kv),
            None => {
                eprintln!("expected field=number, got {p}");
                process::exit(2);
            }
        }
    }
    match fill_day(&open(db_path), user, date, &vals) {
        Ok(set) if set.is_empty() => println!("{user} {date}: nothing to fill"),
        Ok(set) => println!("{user} {date}: filled {}", set.join(", ")),
        Err(e) => {
            eprintln!("fill failed: {e}");
            process::exit(1);
        }
    }
}

fn import_cli(db_path: &str, file: &str, user: &str) {
    let c = open(db_path);
    let text = fs::read_to_string(file).unwrap_or_else(|e| {
        eprintln!("cannot read {file}: {e}");
        process::exit(1);
    });
    let v: Value = serde_json::from_str(&text).unwrap_or_else(|e| {
        eprintln!("bad json in {file}: {e}");
        process::exit(1);
    });
    match import_map(&c, user, &v) {
        Ok(r) => println!("{user}: imported {}, kept existing {}, invalid {}", r.imported, r.skipped, r.invalid),
        Err(e) => {
            eprintln!("import failed: {e}");
            process::exit(1);
        }
    }
}

fn serve(listen: &str) -> Server {
    #[cfg(unix)]
    if let Some(p) = listen.strip_prefix("unix:") {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::remove_file(p);
        let s = Server::http_unix(std::path::Path::new(p)).unwrap_or_else(|e| {
            eprintln!("cannot listen on {listen}: {e}");
            process::exit(1);
        });
        // Owner and group only; the service unit puts the proxy in the group.
        if let Err(e) = fs::set_permissions(p, fs::Permissions::from_mode(0o660)) {
            eprintln!("cannot set permissions on {p}: {e}");
            process::exit(1);
        }
        return s;
    }
    Server::http(listen).unwrap_or_else(|e| {
        eprintln!("cannot listen on {listen}: {e}");
        process::exit(1);
    })
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let db_path = env::var("DB_FILE").unwrap_or_else(|_| "fitness.db".into());
    if args.get(1).map(String::as_str) == Some("import") {
        if args.len() != 4 {
            eprintln!("usage: fitness import <export.json> <user>");
            process::exit(2);
        }
        return import_cli(&db_path, &args[2], &args[3]);
    }
    if args.get(1).map(String::as_str) == Some("fill") {
        if args.len() < 5 {
            eprintln!("usage: fitness fill <user> <YYYY-MM-DD> <field=number>...");
            process::exit(2);
        }
        return fill_cli(&db_path, &args[2], &args[3], &args[4..]);
    }
    if args.get(1).map(String::as_str) == Some("coach") {
        return mcp::cli(&db_path, &args[2..]);
    }
    if args.get(1).map(String::as_str) == Some("backup") {
        if args.len() != 3 {
            eprintln!("usage: fitness backup <file>");
            process::exit(2);
        }
        match backup(&open_ro(&db_path), &args[2]) {
            Ok(()) => return println!("backed up {db_path} to {}", args[2]),
            Err(e) => {
                eprintln!("backup failed: {e}");
                process::exit(1);
            }
        }
    }
    // LISTEN is host:port or unix:/path/to.sock.
    let listen = env::var("LISTEN").unwrap_or_else(|_| "127.0.0.1:8787".into());
    let header = env::var("USER_HEADER").unwrap_or_else(|_| "Remote-User".into());
    // Set ANON_USER only to run without a login proxy (local testing).
    let fallback = env::var("ANON_USER").ok();
    let db = Mutex::new(open(&db_path));
    let server = serve(&listen);
    println!("Fitness listening on {listen}, database {db_path}, user header {header}");
    for rq in server.incoming_requests() {
        handle(rq, &db, &header, fallback.as_deref());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn db() -> Connection {
        let c = Connection::open_in_memory().unwrap();
        init(&c).unwrap();
        c
    }

    fn call(c: &Connection, user: &str, m: Method, path: &str, if_match: Option<&str>, body: Value) -> (u16, Value) {
        let b = if body.is_null() { vec![] } else { body.to_string().into_bytes() };
        let (path, query) = path.split_once('?').unwrap_or((path, ""));
        let r = api(c, user, &m, path, query, if_match, &b);
        (r.code, serde_json::from_slice(&r.body).unwrap_or(Value::Null))
    }

    fn workout() -> Value {
        json!({
            "date": "2026-11-03", "weight": 66, "workout": "A", "note": "first day back",
            "sets": { "legpress": [[36, 12], [46, 14], [55, 12]], "crunch": [[null, 15]] }
        })
    }

    #[test]
    fn round_trip_and_versions() {
        let c = db();
        let (code, v) = call(&c, "kra3", Method::Put, "/api/log/2026-11-03", Some("0"), workout());
        assert_eq!((code, v["version"].as_i64()), (200, Some(1)));
        let (_, list) = call(&c, "kra3", Method::Get, "/api/log", None, Value::Null);
        assert_eq!(list["docs"][0]["data"], workout());
        assert_eq!(list["docs"][0]["version"], 1);
        let sets: i64 = c.query_row("SELECT COUNT(*) FROM sets", [], |r| r.get(0)).unwrap();
        assert_eq!(sets, 4);
        let (code, v) = call(&c, "kra3", Method::Put, "/api/log/2026-11-03", Some("\"1\""), json!({ "weight": 65.8 }));
        assert_eq!((code, v["version"].as_i64()), (200, Some(2)));
        let sets: i64 = c.query_row("SELECT COUNT(*) FROM sets", [], |r| r.get(0)).unwrap();
        assert_eq!(sets, 0, "a write replaces the day's sets");
    }

    #[test]
    fn stale_write_is_rejected_with_current_copy() {
        let c = db();
        call(&c, "kra3", Method::Put, "/api/log/2026-11-03", Some("0"), workout());
        let (code, v) = call(&c, "kra3", Method::Put, "/api/log/2026-11-03", Some("0"), json!({ "weight": 70 }));
        assert_eq!(code, 409);
        assert_eq!(v["current"]["version"], 1);
        assert_eq!(v["current"]["data"]["weight"], 66);
        let (code, _) = call(&c, "kra3", Method::Put, "/api/log/2026-11-03", None, json!({ "weight": 70 }));
        assert_eq!(code, 428);
    }

    #[test]
    fn validation() {
        let c = db();
        for bad in [
            json!({ "weigth": 66 }),
            json!({ "weight": -1 }),
            json!({ "weight": "66" }),
            json!({ "workout": "C" }),
            json!({ "sets": { "Leg Press": [[1, 1]] } }),
            json!({ "sets": { "legpress": [[10]] } }),
            json!({ "sets": { "legpress": [[10, null]] } }),
            json!({ "note": "x".repeat(501) }),
        ] {
            let (code, _) = call(&c, "kra3", Method::Put, "/api/log/2026-11-03", Some("0"), bad.clone());
            assert_eq!(code, 400, "{bad}");
        }
        let (code, _) = call(&c, "kra3", Method::Put, "/api/log/2026-13", Some("0"), json!({}));
        assert_eq!(code, 400);
    }

    #[test]
    fn delete_cascades_and_checks_version() {
        let c = db();
        call(&c, "kra3", Method::Put, "/api/log/2026-11-03", Some("0"), workout());
        let (code, _) = call(&c, "kra3", Method::Delete, "/api/log/2026-11-03", Some("0"), Value::Null);
        assert_eq!(code, 409);
        let (code, _) = call(&c, "kra3", Method::Delete, "/api/log/2026-11-03", Some("1"), Value::Null);
        assert_eq!(code, 200);
        let sets: i64 = c.query_row("SELECT COUNT(*) FROM sets", [], |r| r.get(0)).unwrap();
        assert_eq!(sets, 0);
        let (code, _) = call(&c, "kra3", Method::Delete, "/api/log/2026-11-03", Some("1"), Value::Null);
        assert_eq!(code, 200, "deleting an absent day is not an error");
        let (code, _) = call(&c, "kra3", Method::Delete, "/api/log/settings", Some("0"), Value::Null);
        assert_eq!(code, 400);
    }

    #[test]
    fn users_are_isolated() {
        let c = db();
        call(&c, "kra3", Method::Put, "/api/log/2026-11-03", Some("0"), workout());
        let (_, list) = call(&c, "someone", Method::Get, "/api/log", None, Value::Null);
        assert_eq!(list["docs"], json!([]));
        let (code, _) = call(&c, "someone", Method::Put, "/api/log/2026-11-03", Some("0"), json!({ "weight": 80 }));
        assert_eq!(code, 200, "same date for another user is a separate row");
    }

    #[test]
    fn settings_round_trip() {
        let c = db();
        let s = json!({ "kcal": 1850, "protein": 110, "rest": 90, "height": 172.5 });
        let (code, _) = call(&c, "kra3", Method::Put, "/api/log/settings", Some("0"), s.clone());
        assert_eq!(code, 200);
        let (_, list) = call(&c, "kra3", Method::Get, "/api/log", None, Value::Null);
        assert_eq!(list["docs"][0]["id"], "settings");
        assert_eq!(list["docs"][0]["data"], s);
        let (code, _) = call(&c, "kra3", Method::Put, "/api/log/settings", Some("1"), json!({ "colour": 1 }));
        assert_eq!(code, 400);
    }

    #[test]
    fn import_keeps_existing_and_export_round_trips() {
        let c = db();
        let file = json!({ "2026-11-03": workout(), "2026-11-05": { "weight": 65.5 }, "settings": { "kcal": 1800 }, "junk": 1 });
        let (code, r) = call(&c, "kra3", Method::Post, "/api/import", None, file.clone());
        assert_eq!(code, 200);
        assert_eq!((r["imported"].as_i64(), r["skipped"].as_i64(), r["invalid"].as_i64()), (Some(3), Some(0), Some(1)));
        let (_, r) = call(&c, "kra3", Method::Post, "/api/import", None, file);
        assert_eq!((r["imported"].as_i64(), r["skipped"].as_i64()), (Some(0), Some(3)));
        let exported = export_map(&c, "kra3").unwrap();
        assert_eq!(exported["2026-11-03"], workout());
        assert_eq!(exported["2026-11-05"], json!({ "date": "2026-11-05", "weight": 65.5 }));
        let fresh = db();
        assert_eq!(import_map(&fresh, "kra3", &exported).unwrap().imported, 3);
        assert_eq!(export_map(&fresh, "kra3").unwrap(), exported);
    }

    fn plan() -> Value {
        json!({
            "A": [ { "k": "legpress", "n": "Leg press", "sets": 3, "lo": 10, "hi": 12, "u": "kg" },
                   { "k": "plank", "n": "Plank", "sets": 2, "lo": 30, "hi": 60, "u": "sec" } ],
            "B": [ { "k": "legpress", "n": "Leg press", "sets": 3, "lo": 8, "hi": 10, "u": "kg" } ]
        })
    }

    #[test]
    fn plan_round_trip_keeps_order_and_versions() {
        let c = db();
        let (code, v) = call(&c, "kra3", Method::Put, "/api/log/plan", Some("0"), plan());
        assert_eq!((code, v["version"].as_i64()), (200, Some(1)));
        let (_, list) = call(&c, "kra3", Method::Get, "/api/log", None, Value::Null);
        let doc = list["docs"].as_array().unwrap().iter().find(|d| d["id"] == "plan").unwrap();
        assert_eq!(doc["data"], plan());
        let mut swapped = plan();
        swapped["A"].as_array_mut().unwrap().reverse();
        call(&c, "kra3", Method::Put, "/api/log/plan", Some("1"), swapped.clone());
        assert_eq!(get_plan(&c, "kra3").unwrap().unwrap(), (2, swapped));
        let (code, _) = call(&c, "kra3", Method::Put, "/api/log/plan", Some("1"), plan());
        assert_eq!(code, 409);
        let (code, _) = call(&c, "kra3", Method::Delete, "/api/log/plan", Some("2"), Value::Null);
        assert_eq!(code, 400);
    }

    #[test]
    fn plan_validation() {
        let c = db();
        let ex = |f: &dyn Fn(&mut Value)| {
            let mut p = plan();
            f(&mut p["A"][0]);
            p
        };
        for bad in [
            json!({ "C": [] }),
            ex(&|e| e["u"] = json!("lb")),
            ex(&|e| e["lo"] = json!(13)),
            ex(&|e| e["sets"] = json!(0)),
            ex(&|e| e["n"] = json!("  ")),
            ex(&|e| e["k"] = json!("Leg Press")),
            ex(&|e| e["k"] = json!("plank")),
            ex(&|e| e["extra"] = json!(1)),
        ] {
            let (code, _) = call(&c, "kra3", Method::Put, "/api/log/plan", Some("0"), bad.clone());
            assert_eq!(code, 400, "{bad}");
        }
    }

    #[test]
    fn migrates_a_version_1_database() {
        let c = Connection::open_in_memory().unwrap();
        c.execute_batch(&format!("BEGIN; {SCHEMA_1} COMMIT;")).unwrap();
        c.execute("INSERT INTO days(user, date, weight, version, updated) VALUES('kra3', '2026-11-03', 66, 1, 0)", []).unwrap();
        init(&c).unwrap();
        let v: i64 = c.query_row("PRAGMA user_version", [], |r| r.get(0)).unwrap();
        assert_eq!(v, MIGRATIONS.len() as i64);
        assert_eq!(get_day(&c, "kra3", "2026-11-03").unwrap().unwrap().1["weight"], 66);
        assert_eq!(write_plan(&c, "kra3", &parse_plan(&plan()).unwrap(), 0).unwrap(), Some(1));
        init(&c).unwrap();
    }

    #[test]
    fn backup_is_a_readable_copy() {
        let dir = env::temp_dir().join(format!("fitness-test-{}", process::id()));
        fs::create_dir_all(&dir).unwrap();
        let src = dir.join("live.db");
        let dest = dir.join("copy.db");
        let c = open(src.to_str().unwrap());
        call(&c, "kra3", Method::Put, "/api/log/2026-11-03", Some("0"), workout());
        // As the backup job does: a second, read-only connection beside the live one.
        let ro = open_ro(src.to_str().unwrap());
        backup(&ro, dest.to_str().unwrap()).unwrap();
        backup(&ro, dest.to_str().unwrap()).unwrap();
        let copy = open(dest.to_str().unwrap());
        assert_eq!(get_day(&copy, "kra3", "2026-11-03").unwrap().unwrap().1, workout());
        drop(c);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn backup_does_not_migrate_the_source() {
        let dir = env::temp_dir().join(format!("fitness-test-ro-{}", process::id()));
        fs::create_dir_all(&dir).unwrap();
        let src = dir.join("old.db");
        Connection::open(&src).unwrap().execute_batch("CREATE TABLE t (x); PRAGMA user_version = 1;").unwrap();
        backup(&open_ro(src.to_str().unwrap()), dir.join("copy.db").to_str().unwrap()).unwrap();
        let v: i64 = Connection::open(&src).unwrap().query_row("PRAGMA user_version", [], |r| r.get(0)).unwrap();
        assert_eq!(v, 1);
        let _ = fs::remove_dir_all(&dir);
    }

    /* ---------- HTTP layer, through a real socket ---------- */

    fn server() -> std::net::SocketAddr {
        let s = Server::http("127.0.0.1:0").unwrap();
        let addr = s.server_addr().to_ip().unwrap();
        std::thread::spawn(move || {
            let db = Mutex::new(db());
            for rq in s.incoming_requests() {
                handle(rq, &db, "Remote-User", None);
            }
        });
        addr
    }

    fn status(addr: std::net::SocketAddr, head: &str, body: &[u8]) -> u16 {
        use std::io::Write;
        let mut t = std::net::TcpStream::connect(addr).unwrap();
        let req = format!("{head}\r\nHost: x\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", body.len());
        t.write_all(req.as_bytes()).unwrap();
        let _ = t.write_all(body); // the server may answer before reading it all
        let mut out = String::new();
        let _ = t.read_to_string(&mut out);
        out.split(' ').nth(1).and_then(|c| c.parse().ok()).unwrap_or(0)
    }

    #[test]
    fn http_user_and_health() {
        let a = server();
        assert_eq!(status(a, "GET /healthz HTTP/1.1", b""), 200);
        assert_eq!(status(a, "GET /api/log HTTP/1.1", b""), 401);
        assert_eq!(status(a, "GET /api/log HTTP/1.1\r\nRemote-User: kra3", b""), 200);
        assert_eq!(status(a, "GET /nope HTTP/1.1\r\nRemote-User: kra3", b""), 404);
        // A change made for one account is refused when another is signed in.
        let day = b"{\"date\":\"2026-11-03\",\"weight\":70}";
        assert_eq!(status(a, "PUT /api/log/2026-11-03 HTTP/1.1\r\nRemote-User: anj\r\nX-Fitness-User: kra3\r\nIf-Match: 0", day), 403);
        assert_eq!(status(a, "PUT /api/log/2026-11-03 HTTP/1.1\r\nRemote-User: kra3\r\nX-Fitness-User: kra3\r\nIf-Match: 0", day), 200);
    }

    #[test]
    fn http_refuses_paths_a_proxy_could_normalise() {
        let a = server();
        for p in ["/api/export/../../healthz", "/api/./export", "/api//export", "/api/export%3F/../../healthz", "/healthz/.."] {
            assert_eq!(status(a, &format!("GET {p} HTTP/1.1\r\nRemote-User: kra3"), b""), 400, "{p}");
        }
    }

    #[test]
    fn http_body_limit() {
        let a = server();
        let big = vec![b' '; MAX_BODY as usize + 10];
        let head = "PUT /api/log/2026-11-03 HTTP/1.1\r\nRemote-User: kra3\r\nIf-Match: 0";
        assert_eq!(status(a, head, &big), 413);
    }

    #[test]
    fn plan_weight_step_round_trips() {
        let c = db();
        let plan = json!({ "A": [{ "k": "legpress", "n": "Leg press", "sets": 3, "lo": 10, "hi": 12, "u": "kg", "inc": 2.5 },
                                 { "k": "crunch", "n": "Crunch", "sets": 2, "lo": 12, "hi": 15, "u": "reps" }], "B": [] });
        let (code, _) = call(&c, "kra3", Method::Put, "/api/log/plan", Some("0"), plan.clone());
        assert_eq!(code, 200);
        assert_eq!(get_plan(&c, "kra3").unwrap().unwrap().1, plan);
        for bad in [json!(0), json!(-1), json!(51), json!("2")] {
            let p = json!({ "A": [{ "k": "x", "n": "X", "sets": 1, "lo": 1, "hi": 2, "u": "kg", "inc": bad }] });
            assert_eq!(call(&c, "kra3", Method::Put, "/api/log/plan", Some("1"), p).0, 400);
        }
    }

    #[test]
    fn fill_only_sets_empty_fields() {
        let c = db();
        let v = |k: &str, x: f64| (k.to_string(), x);
        assert_eq!(fill_day(&c, "kra3", "2026-11-02", &[v("steps", 9100.0)]).unwrap(), vec!["steps"]);
        let (ver, day) = get_day(&c, "kra3", "2026-11-02").unwrap().unwrap();
        assert_eq!((ver, day), (1, json!({ "date": "2026-11-02", "steps": 9100 })));
        // A hand-logged or earlier value is kept; other fields are still filled.
        call(&c, "kra3", Method::Put, "/api/log/2026-11-03", Some("0"), workout());
        call(&c, "kra3", Method::Put, "/api/log/2026-11-03", Some("1"), json!({ "date": "2026-11-03", "steps": 4000 }));
        assert_eq!(fill_day(&c, "kra3", "2026-11-03", &[v("steps", 12000.0), v("sleep", 7.5)]).unwrap(), vec!["sleep"]);
        let day = get_day(&c, "kra3", "2026-11-03").unwrap().unwrap().1;
        assert_eq!((day["steps"].clone(), day["sleep"].clone()), (json!(4000), json!(7.5)));
        assert!(fill_day(&c, "kra3", "2026-11-03", &[v("steps", 1.0)]).unwrap().is_empty());
        assert!(fill_day(&c, "kra3", "2026-11-3", &[v("steps", 1.0)]).is_err());
        assert!(fill_day(&c, "kra3", "2026-11-04", &[v("mood", 1.0)]).is_err());
        assert!(fill_day(&c, "kra3", "2026-11-04", &[v("steps", -5.0)]).is_err());
        assert_eq!(fill_day(&c, "kra3", "2026-11-04", &[v("bodyfat", 25.3)]).unwrap(), vec!["bodyfat"]);
        assert_eq!(get_day(&c, "kra3", "2026-11-04").unwrap().unwrap().1["bodyfat"], json!(25.3));
        assert!(fill_day(&c, "kra3", "2026-11-05", &[v("bodyfat", 80.0)]).is_err());
    }

    #[test]
    fn settings_sex_round_trips() {
        let c = db();
        let st = json!({ "kcal": 1850, "height": 175, "sex": "m" });
        assert_eq!(call(&c, "kra3", Method::Put, "/api/log/settings", Some("0"), st.clone()).0, 200);
        assert_eq!(get_settings(&c, "kra3").unwrap().unwrap().1, st);
        assert_eq!(call(&c, "kra3", Method::Put, "/api/log/settings", Some("1"), json!({ "sex": "x" })).0, 400);
        assert_eq!(call(&c, "kra3", Method::Put, "/api/log/settings", Some("1"), json!({ "kcal": 1800 })).0, 200);
        assert_eq!(get_settings(&c, "kra3").unwrap().unwrap().1, json!({ "kcal": 1800 }));
    }

    /* ---------- coaching (schema v6) ---------- */

    fn profile() -> Value {
        json!({ "birth_year": 1990, "goal": "recomp", "goal_notes": " Lose belly fat ", "days_per_week": 4, "days": ["fri", "mon"],
                "session_minutes": 60, "injuries": "knee sometimes", "diet": "",
                "goals": [{ "measure": "waist", "target": 85, "by": "2027-03-01",
                            "milestones": [{ "value": 86, "by": "2027-02-01" }, { "value": 88, "by": "2026-12-15" }] },
                          { "measure": "exercise", "exercise": "legpress", "target": 100 }] })
    }

    #[test]
    fn dates_round_trip() {
        assert_eq!(coach::day_num("1970-01-01"), 0);
        assert_eq!(coach::day_num("2026-11-04") - coach::day_num("2026-10-28"), 7);
        for d in ["2024-02-29", "2026-11-04", "2000-03-01", "1999-12-31"] {
            assert_eq!(coach::day_str(coach::day_num(d)), d);
        }
    }

    #[test]
    fn profile_validates_normalises_and_keeps_history() {
        let c = db();
        assert_eq!(call(&c, "kra3", Method::Put, "/api/log/profile", Some("0"), profile()).0, 200);
        let (v, p) = get_doc(&c, "kra3", "profile").unwrap().unwrap();
        assert_eq!(v, 1);
        assert_eq!(p["goal_notes"], json!("Lose belly fat"));
        assert_eq!(p["days"], json!(["mon", "fri"]));
        assert!(p.get("diet").is_none());
        assert_eq!(p["goals"][0]["milestones"][0]["by"], json!("2026-12-15"));
        assert_eq!(call(&c, "kra3", Method::Put, "/api/log/profile", Some("1"), json!({ "goal": "strength" })).0, 200);
        let hist: i64 = c.query_row("SELECT count(*) FROM profile_history WHERE user = 'kra3'", [], |r| r.get(0)).unwrap();
        assert_eq!(hist, 1);
        for bad in [
            json!({ "mood": 1 }),
            json!({ "goal": "bulk" }),
            json!({ "days": ["someday"] }),
            json!({ "goals": [{ "measure": "exercise", "target": 100 }] }),
            json!({ "goals": [{ "measure": "waist", "target": 85, "milestones": [{ "value": 88 }] }] }),
            json!({ "goals": [{ "measure": "waist", "target": 0 }] }),
            json!({ "session_minutes": 5 }),
        ] {
            assert_eq!(call(&c, "kra3", Method::Put, "/api/log/profile", Some("2"), bad.clone()).0, 400, "{bad}");
        }
    }

    #[test]
    fn proposals_accept_reject_outdated_superseded() {
        use coach::Decision;
        let c = db();
        let plan = json!({ "A": [{ "k": "legpress", "n": "Leg press", "sets": 3, "lo": 10, "hi": 12, "u": "kg" }], "B": [] });
        let p1 = coach::propose(&c, "kra3", "plan", &plan, "Start with one exercise").unwrap();
        let p2 = coach::propose(&c, "kra3", "plan", &plan, "Same, newer").unwrap();
        assert_eq!(coach::decide(&c, "kra3", p1, true, None).unwrap(), Decision::NotOpen("superseded".into()));
        assert_eq!(coach::decide(&c, "kra3", p2, true, Some("ok")).unwrap(), Decision::Accepted(1));
        assert_eq!(get_plan(&c, "kra3").unwrap().unwrap().1, plan);
        assert_eq!(coach::decide(&c, "kra3", p2, false, None).unwrap(), Decision::NotOpen("accepted".into()));
        // The target changed after the proposal was written: refused, nothing written.
        let p3 = coach::propose(&c, "kra3", "settings", &json!({ "kcal": 2000 }), "More food").unwrap();
        call(&c, "kra3", Method::Put, "/api/log/settings", Some("0"), json!({ "kcal": 1900 }));
        assert_eq!(coach::decide(&c, "kra3", p3, true, None).unwrap(), Decision::Outdated);
        assert_eq!(get_settings(&c, "kra3").unwrap().unwrap().1, json!({ "kcal": 1900 }));
        let p4 = coach::propose(&c, "kra3", "profile", &profile(), "Your intake").unwrap();
        assert_eq!(coach::decide(&c, "kra3", p4, false, Some("not yet")).unwrap(), Decision::Rejected);
        assert_eq!(coach::decide(&c, "other", p4, true, None).unwrap(), Decision::NotFound);
        assert!(coach::propose(&c, "kra3", "plan", &json!({ "A": [{ "k": "x" }] }), "bad").is_err());
        assert!(coach::propose(&c, "kra3", "days", &json!({}), "bad").is_err());
        assert!(coach::propose(&c, "kra3", "plan", &plan, " ").is_err());
        let log = coach::list_log(&c, "kra3", 50).unwrap();
        let texts: Vec<&str> = log.iter().map(|e| e["text"].as_str().unwrap()).collect();
        assert!(texts.iter().any(|t| t.starts_with("Rejected the change to your profile") && t.ends_with("Your note: not yet")));
        assert!(texts.iter().any(|t| t.contains("was not applied")));
        assert!(texts.iter().any(|t| t.contains(&format!("#{p1} for your plan was replaced"))));
        let open = coach::list_proposals(&c, "kra3").unwrap();
        assert!(open.iter().all(|p| p["status"] != "open"));
    }

    #[test]
    fn coach_log_is_append_only() {
        let c = db();
        let id = coach::add_log(&c, "kra3", "coach", "check-in", "Week 1").unwrap();
        assert!(c.execute("UPDATE coach_log SET text = 'x' WHERE id = ?1", params![id]).is_err());
        assert!(c.execute("DELETE FROM coach_log WHERE id = ?1", params![id]).is_err());
        assert!(coach::add_log(&c, "kra3", "coach", "rant", "x").is_err());
        assert!(coach::add_log(&c, "kra3", "someone", "note", "x").is_err());
        assert!(coach::add_log(&c, "kra3", "you", "note", "  ").is_err());
    }

    fn seed_month(c: &Connection) {
        let plan = json!({ "A": [{ "k": "legpress", "n": "Leg press", "sets": 3, "lo": 10, "hi": 12, "u": "kg" }],
                           "B": [{ "k": "crunch", "n": "Crunch", "sets": 2, "lo": 12, "hi": 15, "u": "reps" }] });
        call(c, "kra3", Method::Put, "/api/log/plan", Some("0"), plan);
        call(c, "kra3", Method::Put, "/api/log/profile", Some("0"), profile());
        let end = coach::day_num("2026-11-04");
        for i in 0..35 {
            let d = coach::day_str(end - 34 + i);
            let mut day = json!({ "date": d, "weight": 68.0 - 0.05 * i as f64, "kcal": 1900, "protein": 115, "steps": 9000, "sleep": 7, "bodyfat": 26.0 - 0.03 * i as f64 });
            if i % 7 == 0 {
                day["waist"] = json!(92.0 - 0.2 * i as f64);
            }
            if i % 2 == 0 {
                day["workout"] = json!("A");
                day["sets"] = json!({ "legpress": [[50 + i, 10], [50 + i, 10]], "crunch": [[null, 12]] });
            }
            call(c, "kra3", Method::Put, &format!("/api/log/{d}"), Some("0"), day);
        }
    }

    #[test]
    fn summary_reports_trends_goals_and_alerts() {
        let c = db();
        seed_month(&c);
        let s = coach::summary(&c, "kra3", "2026-11-04", 4).unwrap();
        assert_eq!(s["weeks_detail"].as_array().unwrap().len(), 4);
        assert_eq!(s["weeks_detail"][0]["end"], json!("2026-11-04"));
        assert!(s["body"]["pace_kg_week"].as_f64().unwrap() < -0.3);
        let lp = s["training"].as_array().unwrap().iter().find(|t| t["key"] == "legpress").unwrap().clone();
        assert_eq!(lp["sessions"], json!(18));
        assert!(lp["change_4w_pct"].as_f64().unwrap() > 0.0);
        let waist = &s["goals"][0];
        assert_eq!(waist["measure"], json!("waist"));
        assert!(waist["eta"].as_str().is_some_and(|d| d > "2026-11-04"));
        assert_eq!(s["goals"][1]["current"], json!(84));
        assert_eq!(s["nutrition"]["kcal_days"], json!(28));
        assert!(s["nutrition"]["maintenance"].as_f64().unwrap() > 1900.0);
        let kinds: Vec<&str> = s["alerts"].as_array().unwrap().iter().map(|a| a["kind"].as_str().unwrap()).collect();
        assert_eq!(kinds, vec!["check-in"]);
        let text = coach::summary_text(&s);
        for part in ["ALERTS", "GOALS", "BODY", "WEEKS", "TRAINING", "NUTRITION", "PLAN", "COACH LOG", "Leg press [legpress]"] {
            assert!(text.contains(part), "{part}");
        }
        // Two weeks later with nothing logged, and a check-in recorded.
        coach::add_log(&c, "kra3", "coach", "check-in", "Week 5").unwrap();
        let later = coach::summary(&c, "kra3", "2026-11-18", 2).unwrap();
        assert!(later["alerts"].as_array().unwrap().iter().any(|a| a["kind"] == "logging"));
        let empty = coach::summary(&c, "nobody", "2026-11-04", 2).unwrap();
        assert!(empty["alerts"].as_array().unwrap().iter().any(|a| a["text"] == "Nothing logged yet."));
        assert!(coach::summary_text(&empty).contains("the app's starting plan"));
    }

    #[test]
    fn export_import_carries_profile_and_log() {
        let c = db();
        seed_month(&c);
        coach::add_log(&c, "kra3", "coach", "check-in", "Week 5").unwrap();
        c.execute("INSERT INTO coach_log(user, at, author, kind, text) VALUES('kra3', 1000, 'you', 'note', 'old')", []).unwrap();
        let ex = export_map(&c, "kra3").unwrap();
        assert_eq!(ex["coach_log"].as_array().unwrap().len(), 2);
        let c2 = db();
        import_map(&c2, "kra3", &ex).unwrap();
        assert_eq!(get_doc(&c2, "kra3", "profile").unwrap().unwrap().1, get_doc(&c, "kra3", "profile").unwrap().unwrap().1);
        let log = coach::list_log(&c2, "kra3", 10).unwrap();
        assert!(log.iter().any(|e| e["at"] == json!(1000) && e["text"] == "old"));
        // A second import never doubles the log.
        import_map(&c2, "kra3", &ex).unwrap();
        assert_eq!(coach::list_log(&c2, "kra3", 10).unwrap().len(), 2);
    }

    #[test]
    fn mcp_protocol() {
        let c = db();
        seed_month(&c);
        let init = mcp::handle_message(&c, "kra3", &json!({ "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": { "protocolVersion": "2025-06-18" } })).unwrap();
        assert_eq!(init["result"]["protocolVersion"], json!("2025-06-18"));
        assert!(init["result"]["instructions"].as_str().unwrap().contains("summary"));
        assert!(mcp::handle_message(&c, "kra3", &json!({ "jsonrpc": "2.0", "method": "notifications/initialized" })).is_none());
        let list = mcp::handle_message(&c, "kra3", &json!({ "jsonrpc": "2.0", "id": 2, "method": "tools/list" })).unwrap();
        let names: Vec<&str> = list["result"]["tools"].as_array().unwrap().iter().map(|t| t["name"].as_str().unwrap()).collect();
        assert_eq!(names, vec!["summary", "propose", "log", "proposals"]);
        let call = |name: &str, args: Value| mcp::handle_message(&c, "kra3", &json!({ "jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": { "name": name, "arguments": args } })).unwrap();
        let s = call("summary", json!({ "date": "2026-11-04", "weeks": 2 }));
        assert_eq!(s["result"]["isError"], json!(false));
        assert!(s["result"]["content"][0]["text"].as_str().unwrap().starts_with("COACH SUMMARY"));
        let bad = call("propose", json!({ "target": "settings", "data": { "kcal": -1 }, "why": "x" }));
        assert_eq!(bad["result"]["isError"], json!(true));
        let ok = call("propose", json!({ "target": "settings", "data": { "kcal": 2000 }, "why": "Eat a bit more" }));
        assert!(ok["result"]["content"][0]["text"].as_str().unwrap().contains("nothing has changed yet"));
        assert_eq!(call("log", json!({ "add": "Week 5 reviewed", "kind": "check-in" }))["result"]["isError"], json!(false));
        assert!(call("log", json!({}))["result"]["content"][0]["text"].as_str().unwrap().contains("Week 5 reviewed"));
        assert_eq!(call("accept", json!({ "id": 1 }))["result"]["isError"], json!(true));
        let unknown = mcp::handle_message(&c, "kra3", &json!({ "jsonrpc": "2.0", "id": 9, "method": "resources/list" })).unwrap();
        assert_eq!(unknown["error"]["code"], json!(-32601));
    }

    #[test]
    fn http_coach_routes() {
        let a = server();
        let json = "Content-Type: application/json";
        assert_eq!(status(a, "POST /api/coach/log HTTP/1.1\r\nRemote-User: kra3\r\nContent-Type: text/plain", b"{\"text\":\"hi\"}"), 415);
        assert_eq!(status(a, &format!("POST /api/coach/log HTTP/1.1\r\nRemote-User: kra3\r\n{json}"), b"{\"text\":\"Travelling next week\"}"), 200);
        assert_eq!(status(a, "GET /api/coach/log?limit=5 HTTP/1.1\r\nRemote-User: kra3", b""), 200);
        assert_eq!(status(a, "GET /api/coach/summary?end=2026-11-04&weeks=2 HTTP/1.1\r\nRemote-User: kra3", b""), 200);
        assert_eq!(status(a, "GET /api/coach/proposals HTTP/1.1\r\nRemote-User: kra3", b""), 200);
        assert_eq!(status(a, &format!("POST /api/coach/proposals/99/accept HTTP/1.1\r\nRemote-User: kra3\r\n{json}"), b"{}"), 404);
        assert_eq!(status(a, &format!("POST /api/coach/proposals HTTP/1.1\r\nRemote-User: kra3\r\n{json}"), b"{}"), 404);
        assert_eq!(status(a, "GET /api/coach/summary HTTP/1.1", b""), 401);
    }

    #[test]
    fn me_names_the_signed_in_user() {
        let c = db();
        assert_eq!(call(&c, "anj", Method::Get, "/api/me", None, Value::Null), (200, json!({ "user": "anj" })));
    }

    #[test]
    fn if_match_parsing() {
        assert_eq!(parse_version(Some("3")), Some(3));
        assert_eq!(parse_version(Some("\"3\"")), Some(3));
        assert_eq!(parse_version(Some("W/\"3\"")), Some(3));
        assert_eq!(parse_version(Some("-1")), None);
        assert_eq!(parse_version(Some("*")), None);
        assert_eq!(parse_version(None), None);
    }
}
