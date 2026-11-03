// Fitness server: one small process, SQLite storage, per-user data keyed by the
// username an authenticating reverse proxy (Authelia via nginx) passes in a header.
//
// Storage is relational: one row per day, one row per set, one row of settings per
// user. The page still exchanges whole day documents; every write carries the
// version it was based on (If-Match) and a stale write gets 409 with the current
// copy, so two devices never silently overwrite each other.
use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Map, Value};
use std::io::Read;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use std::{env, fs, process};
use tiny_http::{Header, Method, Request, Response, Server, StatusCode};

const INDEX: &str = include_str!("../index.html");
const SW: &str = include_str!("../sw.js");
const MANIFEST: &str = include_str!("../manifest.webmanifest");
const ICON_192: &[u8] = include_bytes!("../icon-192.png");
const ICON_512: &[u8] = include_bytes!("../icon-512.png");
const MAX_BODY: u64 = 262_144;
const MAX_IMPORT: u64 = 4 * 1024 * 1024;
const JSON: &str = "application/json";
const CSP: &str = "default-src 'self'; script-src 'self' 'unsafe-inline'; \
    style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; \
    img-src 'self' data:; connect-src 'self'; manifest-src 'self'; worker-src 'self'; \
    base-uri 'none'; form-action 'self'; frame-ancestors 'none'";

// Numeric day fields and their upper bounds (all must be >= 0).
const DAY_NUM: [(&str, f64); 6] = [
    ("weight", 500.0),
    ("waist", 300.0),
    ("kcal", 20_000.0),
    ("protein", 1_000.0),
    ("steps", 200_000.0),
    ("sleep", 24.0),
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

const SCHEMA: &str = "
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

fn init(c: &Connection) -> rusqlite::Result<()> {
    c.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;")?;
    let v: i64 = c.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    match v {
        0 => c.execute_batch(SCHEMA),
        1 => Ok(()),
        _ => {
            eprintln!("database schema version {v} is newer than this build understands");
            process::exit(1);
        }
    }
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
    nums: [Option<f64>; 6],
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
    let mut nums = [None; 6];
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

fn parse_settings(v: &Value) -> Result<[Option<f64>; 8], String> {
    let o = v.as_object().ok_or("object expected")?;
    if let Some(k) = o.keys().find(|k| !SETTING_NUM.iter().any(|(n, _)| n == k)) {
        return Err(format!("unknown field {k}"));
    }
    let mut out = [None; 8];
    for (i, (name, max)) in SETTING_NUM.iter().enumerate() {
        out[i] = num_field(o.get(*name), name, *max)?;
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
            "SELECT weight, waist, kcal, protein, steps, sleep, note, workout, version FROM days WHERE user = ?1 AND date = ?2",
            params![user, date],
            |r| {
                let mut nums = [None; 6];
                for (i, n) in nums.iter_mut().enumerate() {
                    *n = r.get::<_, Option<f64>>(i)?;
                }
                Ok((nums, r.get::<_, Option<String>>(6)?, r.get::<_, Option<String>>(7)?, r.get::<_, i64>(8)?))
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
        "SELECT kcal, protein, steps, sleep, workouts, height, start_weight, rest, version FROM settings WHERE user = ?1",
        params![user],
        |r| {
            let mut m = Map::new();
            for (i, (name, _)) in SETTING_NUM.iter().enumerate() {
                put_num(&mut m, name, r.get::<_, Option<f64>>(i)?);
            }
            Ok((r.get::<_, i64>(8)?, Value::Object(m)))
        },
    )
    .optional()
}

fn list_dates(c: &Connection, user: &str) -> rusqlite::Result<Vec<String>> {
    let mut st = c.prepare_cached("SELECT date FROM days WHERE user = ?1 ORDER BY date")?;
    let rows = st.query_map(params![user], |r| r.get::<_, String>(0))?;
    rows.collect()
}

fn get_doc(c: &Connection, user: &str, id: &str) -> rusqlite::Result<Option<(i64, Value)>> {
    if id == "settings" {
        get_settings(c, user)
    } else {
        get_day(c, user, id)
    }
}

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
        "INSERT INTO days(user, date, weight, waist, kcal, protein, steps, sleep, note, workout, version, updated)
         VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
         ON CONFLICT(user, date) DO UPDATE SET weight = excluded.weight, waist = excluded.waist, kcal = excluded.kcal,
           protein = excluded.protein, steps = excluded.steps, sleep = excluded.sleep, note = excluded.note,
           workout = excluded.workout, version = excluded.version, updated = excluded.updated",
        params![user, date, n[0], n[1], n[2], n[3], n[4], n[5], d.note, d.workout, version, now()],
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

fn write_settings(c: &Connection, user: &str, s: &[Option<f64>; 8], base: i64) -> rusqlite::Result<Option<i64>> {
    let tx = c.unchecked_transaction()?;
    let cur: Option<i64> = tx.query_row("SELECT version FROM settings WHERE user = ?1", params![user], |r| r.get(0)).optional()?;
    if cur.unwrap_or(0) != base {
        return Ok(None);
    }
    let version = base + 1;
    tx.execute(
        "INSERT INTO settings(user, kcal, protein, steps, sleep, workouts, height, start_weight, rest, version, updated)
         VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
         ON CONFLICT(user) DO UPDATE SET kcal = excluded.kcal, protein = excluded.protein, steps = excluded.steps,
           sleep = excluded.sleep, workouts = excluded.workouts, height = excluded.height,
           start_weight = excluded.start_weight, rest = excluded.rest, version = excluded.version, updated = excluded.updated",
        params![user, s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7], version, now()],
    )?;
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
    if let Some((_, s)) = get_settings(c, user)? {
        m.insert("settings".into(), s);
    }
    Ok(Value::Object(m))
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

fn api(c: &Connection, user: &str, method: &Method, path: &str, if_match: Option<&str>, body: &[u8]) -> Reply {
    match (method, path) {
        (Method::Get, "/api/log") => {
            let mut docs = Vec::new();
            let dates = match list_dates(c, user) {
                Ok(d) => d,
                Err(e) => return db_err(e),
            };
            for id in dates.iter().map(String::as_str).chain(std::iter::once("settings")) {
                match get_doc(c, user, id) {
                    Ok(Some((v, d))) => docs.push(json!({ "id": id, "version": v, "data": d })),
                    Ok(None) => {}
                    Err(e) => return db_err(e),
                }
            }
            reply(200, json!({ "docs": docs }))
        }
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
            if id != "settings" && !valid_date(id) {
                return err(400, "bad id");
            }
            let Some(base) = parse_version(if_match) else {
                return err(428, "If-Match with the base version is required");
            };
            if *method == Method::Delete {
                if id == "settings" {
                    return err(400, "settings cannot be deleted");
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
        "/sw.js" => ("text/javascript; charset=utf-8", SW.as_bytes()),
        "/manifest.webmanifest" => ("application/manifest+json", MANIFEST.as_bytes()),
        "/icon-192.png" => ("image/png", ICON_192),
        "/icon-512.png" => ("image/png", ICON_512),
        _ => return None,
    })
}

fn respond(rq: Request, r: Reply) {
    let h = |k: &str, v: &str| Header::from_bytes(k.as_bytes(), v.as_bytes()).unwrap();
    let mut resp = Response::from_data(r.body)
        .with_status_code(StatusCode(r.code))
        .with_header(h("Content-Type", r.ctype))
        .with_header(h("Cache-Control", "no-store"))
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
    let path = url.split('?').next().unwrap_or("/").to_string();
    let method = rq.method().clone();

    if method == Method::Get {
        if let Some((ctype, body)) = static_file(&path) {
            return respond(rq, Reply { code: 200, ctype, body: body.to_vec(), extra: vec![] });
        }
    }
    if !path.starts_with("/api/") {
        return respond(rq, err(404, "not found"));
    }
    let Some(user) = user_of(&rq, header, fallback) else {
        return respond(rq, err(401, "no user"));
    };
    let if_match = header_of(&rq, "If-Match").map(str::to_string);
    let limit = if path == "/api/import" { MAX_IMPORT } else { MAX_BODY };
    let mut body = Vec::new();
    if rq.as_reader().take(limit + 1).read_to_end(&mut body).is_err() {
        return respond(rq, err(400, "read failed"));
    }
    if body.len() as u64 > limit {
        return respond(rq, err(413, "too large"));
    }
    let r = {
        let c = db.lock().unwrap_or_else(|p| p.into_inner());
        api(&c, &user, &method, &path, if_match.as_deref(), &body)
    };
    respond(rq, r)
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
        let r = api(c, user, &m, path, if_match, &b);
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
