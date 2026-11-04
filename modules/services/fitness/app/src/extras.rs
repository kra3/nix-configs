// Extras (schema v7): blood tests, cardio and sport sessions, progress photos.
// Photos live as files under the state directory (PHOTO_DIR, default `photos`
// beside the database), never in the database; only their names are stored.
// They are left out of export/import and of the coach summary (count and last
// date only).

use super::*;
use std::collections::BTreeMap;
use std::io::Write;
use std::path::PathBuf;

pub const SCHEMA_9: &str = "
CREATE TABLE labs(
  id INTEGER PRIMARY KEY, user TEXT NOT NULL, date TEXT NOT NULL, marker TEXT NOT NULL,
  name TEXT, value REAL NOT NULL, unit TEXT NOT NULL, note TEXT);
CREATE INDEX labs_user ON labs(user, date);
CREATE TABLE cardio(
  id INTEGER PRIMARY KEY, user TEXT NOT NULL, date TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('walk', 'incline-walk', 'cycle', 'cross-trainer', 'row', 'swim', 'sport', 'other')),
  minutes INTEGER NOT NULL CHECK (minutes BETWEEN 1 AND 600),
  distance_km REAL, avg_hr INTEGER CHECK (avg_hr BETWEEN 40 AND 220),
  rpe INTEGER CHECK (rpe BETWEEN 1 AND 10), note TEXT);
CREATE INDEX cardio_user ON cardio(user, date);
CREATE TABLE photos(
  id INTEGER PRIMARY KEY, user TEXT NOT NULL, date TEXT NOT NULL,
  pose TEXT NOT NULL CHECK (pose IN ('front', 'side', 'back')),
  file TEXT NOT NULL, created INTEGER NOT NULL);
CREATE INDEX photos_user ON photos(user, date);
PRAGMA user_version = 9;";

pub const MAX_PHOTO: u64 = 4 * 1024 * 1024;
const POSES: [&str; 3] = ["front", "side", "back"];
const KINDS: [&str; 8] = ["walk", "incline-walk", "cycle", "cross-trainer", "row", "swim", "sport", "other"];

// key, label, unit, typical low, typical high, recheck interval in months.
type Marker = (&'static str, &'static str, &'static str, Option<f64>, Option<f64>, u32);
const MARKERS: [Marker; 14] = [
    ("vitamin_d", "Vitamin D (25-OH)", "ng/mL", Some(30.0), Some(100.0), 3),
    ("b12", "Vitamin B12", "pg/mL", Some(200.0), Some(900.0), 6),
    ("ferritin", "Ferritin", "ng/mL", Some(30.0), Some(300.0), 6),
    ("haemoglobin", "Haemoglobin", "g/dL", Some(13.0), Some(17.5), 12),
    ("hba1c", "HbA1c", "%", None, Some(5.6), 6),
    ("glucose", "Fasting glucose", "mg/dL", Some(70.0), Some(99.0), 12),
    ("cholesterol", "Total cholesterol", "mg/dL", None, Some(200.0), 12),
    ("ldl", "LDL cholesterol", "mg/dL", None, Some(100.0), 12),
    ("hdl", "HDL cholesterol", "mg/dL", Some(40.0), None, 12),
    ("triglycerides", "Triglycerides", "mg/dL", None, Some(150.0), 12),
    ("tsh", "TSH", "mIU/L", Some(0.4), Some(4.0), 12),
    ("alt", "ALT", "U/L", Some(7.0), Some(55.0), 12),
    ("creatinine", "Creatinine", "mg/dL", Some(0.7), Some(1.3), 12),
    ("other", "Other", "", None, None, 0),
];

fn marker(k: &str) -> Option<(usize, &'static Marker)> {
    MARKERS.iter().enumerate().find(|(_, m)| m.0 == k)
}

fn query_param<'a>(query: &'a str, k: &str) -> Option<&'a str> {
    query.split('&').filter_map(|kv| kv.split_once('=')).find(|(a, _)| *a == k).map(|(_, v)| v)
}

// A real calendar date (valid_date only checks the shape).
fn ok_date(s: &str) -> bool {
    valid_date(s) && {
        let (m, d) = (s[5..7].parse::<u32>().unwrap_or(0), s[8..10].parse::<u32>().unwrap_or(0));
        (1..=12).contains(&m) && d >= 1 && d <= days_in_month(s[0..4].parse().unwrap_or(0), m)
    }
}

fn days_in_month(y: u32, m: u32) -> u32 {
    match m {
        2 if y.is_multiple_of(4) && (!y.is_multiple_of(100) || y.is_multiple_of(400)) => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

fn add_months(date: &str, n: u32) -> String {
    let (y, m, d) = (date[0..4].parse::<u32>().unwrap_or(1970), date[5..7].parse::<u32>().unwrap_or(1), date[8..10].parse::<u32>().unwrap_or(1));
    let t = y * 12 + (m - 1) + n;
    let (ny, nm) = (t / 12, t % 12 + 1);
    format!("{ny:04}-{nm:02}-{:02}", d.min(days_in_month(ny, nm)))
}

fn text(o: &Map<String, Value>, k: &str, max: usize) -> Result<Option<String>, String> {
    match o.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(s)) if s.chars().count() <= max => Ok(Some(s.trim().to_string()).filter(|s| !s.is_empty())),
        Some(_) => Err(format!("{k} must be text of at most {max} characters")),
    }
}

fn date_of(o: &Map<String, Value>) -> Result<String, String> {
    o.get("date").and_then(Value::as_str).filter(|d| ok_date(d)).map(str::to_string).ok_or_else(|| "date must be YYYY-MM-DD".to_string())
}

fn keys_ok(o: &Map<String, Value>, keys: &[&str]) -> Result<(), String> {
    match o.keys().find(|k| !keys.contains(&k.as_str())) {
        Some(k) => Err(format!("unknown field {k}")),
        None => Ok(()),
    }
}

/* ---------- blood tests ---------- */

#[derive(Debug, PartialEq)]
struct Lab {
    date: String,
    marker: &'static str,
    name: Option<String>,
    value: f64,
    unit: String,
    note: Option<String>,
}

fn parse_lab(v: &Value) -> Result<Lab, String> {
    let o = v.as_object().ok_or("object expected")?;
    keys_ok(o, &["date", "marker", "name", "value", "unit", "note"])?;
    let date = date_of(o)?;
    let (_, m) = o.get("marker").and_then(Value::as_str).and_then(marker).ok_or("unknown marker")?;
    let value = o.get("value").and_then(Value::as_f64).filter(|x| x.is_finite() && (0.0..=1e6).contains(x)).ok_or("value must be a number from 0 to 1000000")?;
    let (name, unit) = if m.0 == "other" {
        let name = text(o, "name", MAX_NAME)?.ok_or("name the test")?;
        let unit = text(o, "unit", 20)?.ok_or("give the unit")?;
        (Some(name), unit)
    } else {
        (None, m.2.to_string())
    };
    Ok(Lab { date, marker: m.0, name, value, unit, note: text(o, "note", MAX_NOTE)? })
}

fn insert_lab(c: &Connection, user: &str, l: &Lab) -> rusqlite::Result<i64> {
    c.execute(
        "INSERT INTO labs(user, date, marker, name, value, unit, note) VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![user, l.date, l.marker, l.name, l.value, l.unit, l.note],
    )?;
    Ok(c.last_insert_rowid())
}

fn lab_row(r: &rusqlite::Row) -> rusqlite::Result<Value> {
    let mut m = Map::new();
    m.insert("id".into(), json!(r.get::<_, i64>(0)?));
    m.insert("date".into(), json!(r.get::<_, String>(1)?));
    m.insert("marker".into(), json!(r.get::<_, String>(2)?));
    if let Some(n) = r.get::<_, Option<String>>(3)? {
        m.insert("name".into(), json!(n));
    }
    m.insert("value".into(), num_value(r.get::<_, f64>(4)?));
    m.insert("unit".into(), json!(r.get::<_, String>(5)?));
    if let Some(n) = r.get::<_, Option<String>>(6)? {
        m.insert("note".into(), json!(n));
    }
    Ok(Value::Object(m))
}

const LAB_COLS: &str = "id, date, marker, name, value, unit, note";

fn list_labs(c: &Connection, user: &str) -> rusqlite::Result<Vec<Value>> {
    let mut st = c.prepare_cached(&format!("SELECT {LAB_COLS} FROM labs WHERE user = ?1 ORDER BY date DESC, id DESC"))?;
    let rows = st.query_map(params![user], lab_row)?;
    rows.collect()
}

// The newest result per marker with its range flag and recheck date, as of `today`.
pub fn latest_labs(c: &Connection, user: &str, today: &str) -> rusqlite::Result<Vec<Value>> {
    let mut st = c.prepare_cached(&format!("SELECT {LAB_COLS} FROM labs WHERE user = ?1 AND date <= ?2 ORDER BY date, id"))?;
    let rows = st.query_map(params![user, today], lab_row)?;
    let mut newest: BTreeMap<(usize, String), Value> = BTreeMap::new();
    for r in rows {
        let r = r?;
        let (i, _) = marker(r["marker"].as_str().unwrap_or("")).unwrap_or((MARKERS.len() - 1, &MARKERS[MARKERS.len() - 1]));
        newest.insert((i, r["name"].as_str().unwrap_or("").to_string()), r);
    }
    Ok(newest
        .into_values()
        .map(|mut r| {
            let m = marker(r["marker"].as_str().unwrap_or("")).map(|x| x.1).unwrap_or(&MARKERS[MARKERS.len() - 1]);
            let v = r["value"].as_f64().unwrap_or(0.0);
            let dir = if m.3.is_some_and(|lo| v < lo) {
                Some("low")
            } else if m.4.is_some_and(|hi| v > hi) {
                Some("high")
            } else {
                None
            };
            let date = r["date"].as_str().unwrap_or("").to_string();
            let due = (m.5 > 0).then(|| add_months(&date, m.5));
            r["label"] = json!(r["name"].as_str().unwrap_or(m.1));
            r["low"] = json!(m.3);
            r["high"] = json!(m.4);
            r["outside"] = json!(dir.is_some());
            r["direction"] = json!(dir);
            r["flag"] = json!(dir.map(|_| "outside typical range"));
            r["next_due"] = json!(due);
            r["overdue"] = json!(due.as_deref().is_some_and(|d| d < today));
            r
        })
        .collect())
}

fn markers_json() -> Value {
    Value::Array(MARKERS.iter().map(|m| json!({ "key": m.0, "label": m.1, "unit": m.2, "low": m.3, "high": m.4, "months": m.5 })).collect())
}

// The `labs` block of the coach summary.
pub fn summary_labs(c: &Connection, user: &str, end: &str) -> rusqlite::Result<Value> {
    let latest = latest_labs(c, user, end)?;
    let pick = |k: &str| -> Vec<Value> { latest.iter().filter(|l| l[k] == true).map(|l| json!({ "label": l["label"], "value": l["value"], "unit": l["unit"], "date": l["date"], "next_due": l["next_due"] })).collect() };
    Ok(json!({ "latest": latest, "out_of_range": pick("outside"), "overdue": pick("overdue") }))
}

/* ---------- cardio ---------- */

#[derive(Debug, PartialEq)]
struct Cardio {
    date: String,
    kind: &'static str,
    minutes: i64,
    distance_km: Option<f64>,
    avg_hr: Option<i64>,
    rpe: Option<i64>,
    note: Option<String>,
}

fn opt_whole(o: &Map<String, Value>, k: &str, lo: i64, hi: i64) -> Result<Option<i64>, String> {
    match o.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(_) => int_field(o, k, lo, hi).map(Some),
    }
}

fn parse_cardio(v: &Value) -> Result<Cardio, String> {
    let o = v.as_object().ok_or("object expected")?;
    keys_ok(o, &["date", "kind", "minutes", "distance_km", "avg_hr", "rpe", "note"])?;
    let kind = o.get("kind").and_then(Value::as_str).and_then(|k| KINDS.iter().find(|x| **x == k)).ok_or("unknown kind")?;
    Ok(Cardio {
        date: date_of(o)?,
        kind,
        minutes: int_field(o, "minutes", 1, 600)?,
        distance_km: match o.get("distance_km") {
            None | Some(Value::Null) => None,
            Some(x) => Some(x.as_f64().filter(|d| *d > 0.0 && *d <= 1000.0).ok_or("distance_km must be above 0 and at most 1000")?),
        },
        avg_hr: opt_whole(o, "avg_hr", 40, 220)?,
        rpe: opt_whole(o, "rpe", 1, 10)?,
        note: text(o, "note", MAX_NOTE)?,
    })
}

fn insert_cardio(c: &Connection, user: &str, s: &Cardio) -> rusqlite::Result<i64> {
    c.execute(
        "INSERT INTO cardio(user, date, kind, minutes, distance_km, avg_hr, rpe, note) VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        params![user, s.date, s.kind, s.minutes, s.distance_km, s.avg_hr, s.rpe, s.note],
    )?;
    Ok(c.last_insert_rowid())
}

fn list_cardio(c: &Connection, user: &str, from: &str) -> rusqlite::Result<Vec<Value>> {
    let mut st = c.prepare_cached("SELECT id, date, kind, minutes, distance_km, avg_hr, rpe, note FROM cardio WHERE user = ?1 AND date >= ?2 ORDER BY date DESC, id DESC")?;
    let rows = st.query_map(params![user, from], |r| {
        let mut m = Map::new();
        m.insert("id".into(), json!(r.get::<_, i64>(0)?));
        m.insert("date".into(), json!(r.get::<_, String>(1)?));
        m.insert("kind".into(), json!(r.get::<_, String>(2)?));
        m.insert("minutes".into(), json!(r.get::<_, i64>(3)?));
        put_num(&mut m, "distance_km", r.get::<_, Option<f64>>(4)?);
        for (i, k) in [(5, "avg_hr"), (6, "rpe")] {
            if let Some(x) = r.get::<_, Option<i64>>(i)? {
                m.insert(k.into(), json!(x));
            }
        }
        if let Some(n) = r.get::<_, Option<String>>(7)? {
            m.insert("note".into(), json!(n));
        }
        Ok(Value::Object(m))
    })?;
    rows.collect()
}

// (day number, kind, minutes, km) of sessions in (from, to], for the summary.
pub type CardioRow = (i64, String, i64, Option<f64>);

pub fn cardio_window(c: &Connection, user: &str, from: i64, to: i64) -> rusqlite::Result<Vec<CardioRow>> {
    let mut st = c.prepare_cached("SELECT date, kind, minutes, distance_km FROM cardio WHERE user = ?1 AND date > ?2 AND date <= ?3 ORDER BY date")?;
    let rows = st.query_map(params![user, coach::day_str(from), coach::day_str(to)], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get(2)?, r.get(3)?)))?;
    rows.map(|r| r.map(|(d, k, m, km)| (coach::day_num(&d), k, m, km))).collect()
}

pub fn cardio_by_kind(rows: &[CardioRow]) -> Value {
    let mut by: BTreeMap<&str, (i64, i64, f64)> = BTreeMap::new();
    for (_, k, m, km) in rows {
        let e = by.entry(k.as_str()).or_default();
        *e = (e.0 + 1, e.1 + m, e.2 + km.unwrap_or(0.0));
    }
    Value::Array(by.into_iter().map(|(k, (n, m, km))| json!({ "kind": k, "sessions": n, "minutes": m, "km": (km > 0.0).then(|| (km * 10.0).round() / 10.0) })).collect())
}

/* ---------- photos (files on disk) ---------- */

fn photo_dir(c: &Connection) -> PathBuf {
    if let Ok(d) = env::var("PHOTO_DIR") {
        if !d.is_empty() {
            return PathBuf::from(d);
        }
    }
    let db: String = c.query_row("SELECT file FROM pragma_database_list WHERE name = 'main'", [], |r| r.get(0)).unwrap_or_default();
    PathBuf::from(db).parent().map(|p| p.join("photos")).unwrap_or_else(|| PathBuf::from("photos"))
}

// Account names become a single safe path component.
fn safe_user(u: &str) -> String {
    u.chars().map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' }).collect()
}

fn add_photo(c: &Connection, user: &str, date: &str, pose: &str, body: &[u8]) -> Result<i64, Reply> {
    if !ok_date(date) {
        return Err(err(400, "date must be YYYY-MM-DD"));
    }
    if !POSES.contains(&pose) {
        return Err(err(400, "pose must be front, side or back"));
    }
    if body.len() as u64 > MAX_PHOTO {
        return Err(err(413, "photo too large"));
    }
    if !body.starts_with(&[0xFF, 0xD8, 0xFF]) {
        return Err(err(415, "a JPEG image is expected"));
    }
    let dir = photo_dir(c);
    let sub = safe_user(user);
    fs::create_dir_all(dir.join(&sub)).map_err(|e| {
        eprintln!("cannot create photo directory: {e}");
        err(500, "cannot store photo")
    })?;
    let mut made = None;
    for n in 1..1000 {
        let rel = format!("{sub}/{date}-{n}.jpg");
        match fs::OpenOptions::new().write(true).create_new(true).open(dir.join(&rel)) {
            Ok(f) => {
                made = Some((rel, f));
                break;
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => {
                eprintln!("cannot write photo: {e}");
                return Err(err(500, "cannot store photo"));
            }
        }
    }
    let Some((rel, mut f)) = made else { return Err(err(400, "too many photos for that day")) };
    if let Err(e) = f.write_all(body).and_then(|_| f.sync_all()) {
        eprintln!("cannot write photo: {e}");
        let _ = fs::remove_file(dir.join(&rel));
        return Err(err(500, "cannot store photo"));
    }
    match c.execute("INSERT INTO photos(user, date, pose, file, created) VALUES(?1, ?2, ?3, ?4, ?5)", params![user, date, pose, rel, now()]) {
        Ok(_) => Ok(c.last_insert_rowid()),
        Err(e) => {
            let _ = fs::remove_file(dir.join(&rel));
            Err(db_err(e))
        }
    }
}

fn photo_file(c: &Connection, user: &str, id: i64) -> rusqlite::Result<Option<String>> {
    c.query_row("SELECT file FROM photos WHERE id = ?1 AND user = ?2", params![id, user], |r| r.get(0)).optional()
}

// Photos are never summarised beyond how many there are and when the last was taken.
pub fn summary_photos(c: &Connection, user: &str) -> rusqlite::Result<Value> {
    c.query_row("SELECT count(*), max(date) FROM photos WHERE user = ?1", params![user], |r| Ok(json!({ "count": r.get::<_, i64>(0)?, "last_date": r.get::<_, Option<String>>(1)? })))
}

/* ---------- export / import ---------- */

pub fn export_lists(c: &Connection, user: &str, m: &mut Map<String, Value>) -> rusqlite::Result<()> {
    let strip = |mut v: Value| {
        if let Value::Object(o) = &mut v {
            o.remove("id");
        }
        v
    };
    let labs: Vec<Value> = list_labs(c, user)?.into_iter().rev().map(strip).collect();
    if !labs.is_empty() {
        m.insert("labs".into(), Value::Array(labs));
    }
    let cardio: Vec<Value> = list_cardio(c, user, "0000-00-00")?.into_iter().rev().map(strip).collect();
    if !cardio.is_empty() {
        m.insert("cardio".into(), Value::Array(cardio));
    }
    Ok(())
}

// Returns (imported, kept because already present, invalid).
pub fn import_list(c: &Connection, user: &str, id: &str, v: &Value) -> Result<(u32, u32, u32), String> {
    let list = v.as_array().ok_or_else(|| format!("{id} must be a list"))?;
    let (mut ok, mut dup, mut bad) = (0, 0, 0);
    for e in list {
        let res = if id == "labs" {
            parse_lab(e).and_then(|l| {
                let n: i64 = c
                    .query_row(
                        "SELECT count(*) FROM labs WHERE user = ?1 AND date = ?2 AND marker = ?3 AND ifnull(name, '') = ?4 AND value = ?5",
                        params![user, l.date, l.marker, l.name.clone().unwrap_or_default(), l.value],
                        |r| r.get(0),
                    )
                    .map_err(|e| e.to_string())?;
                if n > 0 { Ok(false) } else { insert_lab(c, user, &l).map(|_| true).map_err(|e| e.to_string()) }
            })
        } else {
            parse_cardio(e).and_then(|s| {
                let n: i64 = c
                    .query_row(
                        "SELECT count(*) FROM cardio WHERE user = ?1 AND date = ?2 AND kind = ?3 AND minutes = ?4 AND distance_km IS ?5",
                        params![user, s.date, s.kind, s.minutes, s.distance_km],
                        |r| r.get(0),
                    )
                    .map_err(|e| e.to_string())?;
                if n > 0 { Ok(false) } else { insert_cardio(c, user, &s).map(|_| true).map_err(|e| e.to_string()) }
            })
        };
        match res {
            Ok(true) => ok += 1,
            Ok(false) => dup += 1,
            Err(_) => bad += 1,
        }
    }
    Ok((ok, dup, bad))
}

/* ---------- HTTP ---------- */

// "/api/<what>/<id>/<action>" -> (id, action)
fn id_action<'a>(path: &'a str, prefix: &str) -> Option<(i64, &'a str)> {
    let (id, action) = path.strip_prefix(prefix)?.split_once('/').unwrap_or((path.strip_prefix(prefix)?, ""));
    Some((id.parse().ok()?, action))
}

fn deleted(r: rusqlite::Result<usize>) -> Reply {
    match r {
        Ok(0) => err(404, "not found"),
        Ok(_) => reply(200, json!({ "deleted": true })),
        Err(e) => db_err(e),
    }
}

// Routes under /api/labs, /api/cardio and /api/photos. The caller has already
// required Content-Type image/jpeg for the photo upload and JSON for the rest.
pub fn api(c: &Connection, user: &str, method: &Method, path: &str, query: &str, body: &[u8]) -> Reply {
    let json_body = || serde_json::from_slice::<Value>(body);
    if path == "/api/labs" {
        return match method {
            Method::Get => match list_labs(c, user).and_then(|l| Ok((l, latest_labs(c, user, &coach::local_today(c))?))) {
                Ok((labs, latest)) => reply(200, json!({ "labs": labs, "latest": latest, "markers": markers_json() })),
                Err(e) => db_err(e),
            },
            Method::Post => match json_body().map_err(|_| "bad json".to_string()).and_then(|v| parse_lab(&v)) {
                Ok(l) => insert_lab(c, user, &l).map(|id| reply(200, json!({ "id": id }))).unwrap_or_else(db_err),
                Err(e) => err(400, &e),
            },
            _ => err(404, "not found"),
        };
    }
    if path == "/api/cardio" {
        return match method {
            Method::Get => {
                let days = query_param(query, "days").and_then(|d| d.parse::<i64>().ok()).unwrap_or(14).clamp(1, 36_500);
                let from = coach::day_str(coach::day_num(&coach::local_today(c)) - days + 1);
                list_cardio(c, user, &from).map(|l| reply(200, json!({ "cardio": l, "kinds": KINDS }))).unwrap_or_else(db_err)
            }
            Method::Post => match json_body().map_err(|_| "bad json".to_string()).and_then(|v| parse_cardio(&v)) {
                Ok(s) => insert_cardio(c, user, &s).map(|id| reply(200, json!({ "id": id }))).unwrap_or_else(db_err),
                Err(e) => err(400, &e),
            },
            _ => err(404, "not found"),
        };
    }
    if let (Method::Post, Some((id, "delete"))) = (method, id_action(path, "/api/labs/")) {
        return deleted(c.execute("DELETE FROM labs WHERE id = ?1 AND user = ?2", params![id, user]));
    }
    if let (Method::Post, Some((id, "delete"))) = (method, id_action(path, "/api/cardio/")) {
        return deleted(c.execute("DELETE FROM cardio WHERE id = ?1 AND user = ?2", params![id, user]));
    }
    if path == "/api/photos" {
        return match method {
            Method::Get => {
                let mut st = match c.prepare_cached("SELECT id, date, pose FROM photos WHERE user = ?1 ORDER BY date DESC, id DESC") {
                    Ok(s) => s,
                    Err(e) => return db_err(e),
                };
                let rows = st.query_map(params![user], |r| Ok(json!({ "id": r.get::<_, i64>(0)?, "date": r.get::<_, String>(1)?, "pose": r.get::<_, String>(2)? })));
                match rows.and_then(|r| r.collect::<rusqlite::Result<Vec<_>>>()) {
                    Ok(l) => reply(200, json!({ "photos": l })),
                    Err(e) => db_err(e),
                }
            }
            Method::Post => match add_photo(c, user, query_param(query, "date").unwrap_or(""), query_param(query, "pose").unwrap_or(""), body) {
                Ok(id) => reply(200, json!({ "id": id })),
                Err(r) => r,
            },
            _ => err(404, "not found"),
        };
    }
    match (method, id_action(path, "/api/photos/")) {
        (Method::Get, Some((id, ""))) => match photo_file(c, user, id) {
            Ok(Some(rel)) => match fs::read(photo_dir(c).join(rel)) {
                Ok(b) => Reply { code: 200, ctype: "image/jpeg", body: b, extra: vec![("Cache-Control", "private, no-store".into())] },
                Err(_) => err(404, "photo file missing"),
            },
            Ok(None) => err(404, "not found"),
            Err(e) => db_err(e),
        },
        (Method::Post, Some((id, "delete"))) => match photo_file(c, user, id) {
            Ok(Some(rel)) => {
                if let Err(e) = fs::remove_file(photo_dir(c).join(&rel)) {
                    if e.kind() != std::io::ErrorKind::NotFound {
                        eprintln!("cannot remove photo: {e}");
                        return err(500, "cannot remove photo");
                    }
                }
                deleted(c.execute("DELETE FROM photos WHERE id = ?1 AND user = ?2", params![id, user]))
            }
            Ok(None) => err(404, "not found"),
            Err(e) => db_err(e),
        },
        _ => err(404, "not found"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // A file database in its own directory, so the photo directory beside it is private to the test.
    fn db(name: &str) -> (Connection, PathBuf) {
        let dir = env::temp_dir().join(format!("fitness-extras-{}-{name}", process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let c = Connection::open(dir.join("fitness.db")).unwrap();
        init(&c).unwrap();
        (c, dir)
    }

    fn call(c: &Connection, user: &str, m: Method, path: &str, body: Value) -> (u16, Value) {
        let b = if body.is_null() { vec![] } else { body.to_string().into_bytes() };
        let (path, query) = path.split_once('?').unwrap_or((path, ""));
        let r = api(c, user, &m, path, query, &b);
        (r.code, serde_json::from_slice(&r.body).unwrap_or(Value::Null))
    }

    fn upload(c: &Connection, user: &str, q: &str, body: &[u8]) -> Reply {
        api(c, user, &Method::Post, "/api/photos", q, body)
    }

    const JPEG: [u8; 6] = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0];

    #[test]
    fn labs_validate_and_round_trip() {
        let (c, _) = db("labs");
        let ok = json!({ "date": "2026-10-01", "marker": "vitamin_d", "value": 24.5, "note": "fasting" });
        assert_eq!(call(&c, "kra3", Method::Post, "/api/labs", ok).0, 200);
        for bad in [
            json!({ "date": "2026-13-01", "marker": "tsh", "value": 2 }),
            json!({ "date": "2026-10-01", "marker": "nope", "value": 2 }),
            json!({ "date": "2026-10-01", "marker": "tsh", "value": -1 }),
            json!({ "date": "2026-10-01", "marker": "tsh", "value": "2" }),
            json!({ "date": "2026-10-01", "marker": "other", "value": 2, "name": "CRP" }),
            json!({ "date": "2026-10-01", "marker": "tsh", "value": 2, "extra": 1 }),
        ] {
            assert_eq!(call(&c, "kra3", Method::Post, "/api/labs", bad.clone()).0, 400, "{bad}");
        }
        let other = json!({ "date": "2026-10-02", "marker": "other", "name": "CRP", "unit": "mg/L", "value": 1.2 });
        assert_eq!(call(&c, "kra3", Method::Post, "/api/labs", other).0, 200);
        let (_, v) = call(&c, "kra3", Method::Get, "/api/labs", Value::Null);
        assert_eq!(v["labs"].as_array().unwrap().len(), 2);
        let vd = v["latest"].as_array().unwrap().iter().find(|l| l["marker"] == "vitamin_d").unwrap().clone();
        assert_eq!((vd["outside"].clone(), vd["flag"].clone(), vd["direction"].clone()), (json!(true), json!("outside typical range"), json!("low")));
        assert_eq!(vd["next_due"], json!("2027-01-01"));
        let id = v["labs"][1]["id"].as_i64().unwrap();
        assert_eq!(call(&c, "someone", Method::Post, &format!("/api/labs/{id}/delete"), Value::Null).0, 404);
        assert_eq!(call(&c, "kra3", Method::Post, &format!("/api/labs/{id}/delete"), Value::Null).0, 200);
        assert_eq!(call(&c, "kra3", Method::Get, "/api/labs", Value::Null).1["labs"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn cardio_validates_and_round_trips() {
        let (c, _) = db("cardio");
        let today = coach::local_today(&c);
        let ok = json!({ "date": today, "kind": "incline-walk", "minutes": 40, "distance_km": 3.5, "avg_hr": 120, "rpe": 5 });
        assert_eq!(call(&c, "kra3", Method::Post, "/api/cardio", ok).0, 200);
        for bad in [
            json!({ "date": today, "kind": "run", "minutes": 40 }),
            json!({ "date": today, "kind": "walk", "minutes": 0 }),
            json!({ "date": today, "kind": "walk", "minutes": 601 }),
            json!({ "date": today, "kind": "walk", "minutes": 30, "avg_hr": 39 }),
            json!({ "date": today, "kind": "walk", "minutes": 30, "rpe": 11 }),
            json!({ "date": today, "kind": "walk", "minutes": 30, "distance_km": 0 }),
            json!({ "date": "soon", "kind": "walk", "minutes": 30 }),
        ] {
            assert_eq!(call(&c, "kra3", Method::Post, "/api/cardio", bad.clone()).0, 400, "{bad}");
        }
        let (_, v) = call(&c, "kra3", Method::Get, "/api/cardio", Value::Null);
        assert_eq!(v["cardio"][0]["minutes"], 40);
        assert_eq!(v["cardio"][0]["distance_km"], 3.5);
        assert!(call(&c, "other", Method::Get, "/api/cardio", Value::Null).1["cardio"].as_array().unwrap().is_empty());
        let id = v["cardio"][0]["id"].as_i64().unwrap();
        assert_eq!(call(&c, "other", Method::Post, &format!("/api/cardio/{id}/delete"), Value::Null).0, 404);
        assert_eq!(call(&c, "kra3", Method::Post, &format!("/api/cardio/{id}/delete"), Value::Null).0, 200);
    }

    #[test]
    fn photo_upload_serve_and_delete() {
        let (c, dir) = db("photos");
        assert_eq!(upload(&c, "kra3", "date=2026-11-01&pose=front", b"GIF89a....").code, 415);
        assert_eq!(upload(&c, "kra3", "date=2026-11-01&pose=front", &[]).code, 415);
        assert_eq!(upload(&c, "kra3", "date=2026-11-01&pose=left", &JPEG).code, 400);
        assert_eq!(upload(&c, "kra3", "date=2026-11-31x&pose=front", &JPEG).code, 400);
        let big = [&JPEG[..], &vec![0u8; MAX_PHOTO as usize]].concat();
        assert_eq!(upload(&c, "kra3", "date=2026-11-01&pose=front", &big).code, 413);
        assert!(!dir.join("photos").exists() || fs::read_dir(dir.join("photos/kra3")).map(|d| d.count()).unwrap_or(0) == 0);

        let r = upload(&c, "kra3", "date=2026-11-01&pose=front", &JPEG);
        assert_eq!(r.code, 200);
        let id = serde_json::from_slice::<Value>(&r.body).unwrap()["id"].as_i64().unwrap();
        let second = upload(&c, "kra3", "date=2026-11-01&pose=side", &JPEG);
        assert_eq!(second.code, 200);
        assert!(dir.join("photos/kra3/2026-11-01-1.jpg").exists() && dir.join("photos/kra3/2026-11-01-2.jpg").exists());
        let blobs: i64 = c.query_row("SELECT count(*) FROM photos WHERE typeof(file) <> 'text'", [], |r| r.get(0)).unwrap();
        assert_eq!(blobs, 0);

        let get = api(&c, "kra3", &Method::Get, &format!("/api/photos/{id}"), "", b"");
        assert_eq!((get.code, get.ctype, get.body.clone()), (200, "image/jpeg", JPEG.to_vec()));
        assert_eq!(get.extra, vec![("Cache-Control", "private, no-store".to_string())]);
        // Another account sees neither the file nor the row, and cannot delete it.
        assert_eq!(api(&c, "mallory", &Method::Get, &format!("/api/photos/{id}"), "", b"").code, 404);
        assert_eq!(api(&c, "mallory", &Method::Post, &format!("/api/photos/{id}/delete"), "", b"").code, 404);
        assert!(dir.join("photos/kra3/2026-11-01-1.jpg").exists());
        assert_eq!(api(&c, "mallory", &Method::Get, "/api/photos", "", b"").body, br#"{"photos":[]}"#);

        assert_eq!(api(&c, "kra3", &Method::Post, &format!("/api/photos/{id}/delete"), "", b"").code, 200);
        assert!(!dir.join("photos/kra3/2026-11-01-1.jpg").exists());
        assert_eq!(api(&c, "kra3", &Method::Get, &format!("/api/photos/{id}"), "", b"").code, 404);
        // A hostile account name stays inside the photo directory.
        assert_eq!(upload(&c, "../../etc", "date=2026-11-01&pose=back", &JPEG).code, 200);
        assert!(dir.join("photos/______etc/2026-11-01-1.jpg").exists());
        let ph = summary_photos(&c, "kra3").unwrap();
        assert_eq!(ph, json!({ "count": 1, "last_date": "2026-11-01" }));
    }

    #[test]
    fn summary_flags_overdue_recheck_and_includes_cardio() {
        let (c, _) = db("summary");
        let lab = |d: &str, m: &str, v: f64| call(&c, "kra3", Method::Post, "/api/labs", json!({ "date": d, "marker": m, "value": v }));
        lab("2026-05-01", "vitamin_d", 45.0);
        lab("2026-10-20", "ldl", 130.0);
        let cardio = |d: &str, k: &str, m: i64| call(&c, "kra3", Method::Post, "/api/cardio", json!({ "date": d, "kind": k, "minutes": m }));
        cardio("2026-11-02", "cycle", 30);
        cardio("2026-11-03", "cycle", 20);
        cardio("2026-11-04", "swim", 45);
        let s = coach::summary(&c, "kra3", "2026-11-04", 4).unwrap();
        let alerts = s["alerts"].as_array().unwrap();
        let a = alerts.iter().find(|a| a["kind"] == "labs").expect("labs alert");
        assert!(a["text"].as_str().unwrap().contains("Vitamin D (25-OH) (last 2026-05-01, due 2026-08-01)"), "{a}");
        assert_eq!(s["labs"]["overdue"].as_array().unwrap().len(), 1);
        assert_eq!(s["labs"]["out_of_range"][0]["label"], "LDL cholesterol");
        assert_eq!(s["weeks_detail"][0]["cardio_minutes"], 95);
        assert_eq!(s["cardio"][0], json!({ "kind": "cycle", "sessions": 2, "minutes": 50, "km": null }));
        let t = coach::summary_text(&s);
        assert!(t.contains("BLOOD TESTS") && t.contains("OVERDUE") && t.contains("outside typical range") && t.contains("swim: 1 sessions, 45 min"), "{t}");
        // Up to date: no alert.
        lab("2026-10-30", "vitamin_d", 50.0);
        let s = coach::summary(&c, "kra3", "2026-11-04", 4).unwrap();
        assert!(s["alerts"].as_array().unwrap().iter().all(|a| a["kind"] != "labs"));
    }

    #[test]
    fn export_import_labs_and_cardio_not_photos() {
        let (c, _) = db("export");
        call(&c, "kra3", Method::Post, "/api/labs", json!({ "date": "2026-10-01", "marker": "tsh", "value": 2.1 }));
        call(&c, "kra3", Method::Post, "/api/cardio", json!({ "date": "2026-10-01", "kind": "row", "minutes": 15 }));
        upload(&c, "kra3", "date=2026-10-01&pose=front", &JPEG);
        let exp = export_map(&c, "kra3").unwrap();
        assert!(exp.get("photos").is_none() && exp["labs"].as_array().unwrap().len() == 1 && exp["cardio"].as_array().unwrap().len() == 1);
        let (d, _) = db("export2");
        let r = import_map(&d, "kra3", &exp).unwrap();
        assert_eq!((r.imported, r.skipped, r.invalid), (2, 0, 0));
        let r = import_map(&d, "kra3", &exp).unwrap();
        assert_eq!((r.imported, r.skipped, r.invalid), (0, 2, 0));
        assert_eq!(export_map(&d, "kra3").unwrap(), exp);
    }

    #[test]
    fn migrates_a_version_6_database() {
        let c = Connection::open_in_memory().unwrap();
        for m in &MIGRATIONS[..6] {
            c.execute_batch(&format!("BEGIN; {m} COMMIT;")).unwrap();
        }
        c.execute("INSERT INTO days(user, date, weight, version, updated) VALUES('kra3', '2026-11-03', 66, 1, 0)", []).unwrap();
        init(&c).unwrap();
        let v: i64 = c.query_row("PRAGMA user_version", [], |r| r.get(0)).unwrap();
        assert_eq!(v, MIGRATIONS.len() as i64);
        assert_eq!(get_day(&c, "kra3", "2026-11-03").unwrap().unwrap().1["weight"], 66);
        assert_eq!(c.query_row("SELECT count(*) FROM labs", [], |r| r.get::<_, i64>(0)).unwrap(), 0);
    }

    #[test]
    fn month_arithmetic_clamps() {
        assert_eq!(add_months("2026-08-31", 6), "2027-02-28");
        assert_eq!(add_months("2026-11-15", 12), "2027-11-15");
        assert!(ok_date("2028-02-29") && !ok_date("2027-02-29"));
    }
}
