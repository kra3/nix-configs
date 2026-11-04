// Coaching (schema v6): the profile, the coach log, proposals and the coach
// summary. Proposals are written only from sutala (CLI or MCP) and applied only
// when the user accepts them in the app.

use super::*;
use std::collections::BTreeMap;

pub const SCHEMA_6: &str = "
CREATE TABLE profiles(
  user TEXT NOT NULL PRIMARY KEY, data TEXT NOT NULL,
  version INTEGER NOT NULL, updated INTEGER NOT NULL) WITHOUT ROWID;
CREATE TABLE profile_history(
  user TEXT NOT NULL, version INTEGER NOT NULL, data TEXT NOT NULL, updated INTEGER NOT NULL,
  PRIMARY KEY (user, version)) WITHOUT ROWID;
CREATE TABLE proposals(
  id INTEGER PRIMARY KEY, user TEXT NOT NULL,
  target TEXT NOT NULL CHECK (target IN ('plan', 'settings', 'profile')),
  base_version INTEGER NOT NULL, data TEXT NOT NULL, why TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('open', 'accepted', 'rejected', 'outdated', 'superseded')),
  created INTEGER NOT NULL, decided INTEGER, note TEXT);
CREATE TABLE coach_log(
  id INTEGER PRIMARY KEY, user TEXT NOT NULL, at INTEGER NOT NULL,
  author TEXT NOT NULL CHECK (author IN ('you', 'coach', 'app')),
  kind TEXT NOT NULL CHECK (kind IN ('check-in', 'decision', 'note', 'alert')),
  text TEXT NOT NULL);
CREATE TRIGGER coach_log_no_update BEFORE UPDATE ON coach_log BEGIN SELECT RAISE(ABORT, 'the coach log is append-only'); END;
CREATE TRIGGER coach_log_no_delete BEFORE DELETE ON coach_log BEGIN SELECT RAISE(ABORT, 'the coach log is append-only'); END;
PRAGMA user_version = 6;";

const GOAL_KINDS: [&str; 5] = ["fat-loss", "muscle", "recomp", "strength", "health"];
const MEASURES: [&str; 4] = ["weight", "waist", "bodyfat", "exercise"];
const WEEKDAYS: [&str; 7] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
pub const TARGETS: [&str; 3] = ["plan", "settings", "profile"];
pub const LOG_KINDS: [&str; 4] = ["check-in", "decision", "note", "alert"];
const MAX_LOG: usize = 1000;
const MAX_WHY: usize = 600;
// Same defaults as the page (app.js DEF).
const DEF_TARGETS: [(&str, f64); 6] = [("kcal", 1850.0), ("protein", 110.0), ("steps", 8000.0), ("sleep", 7.0), ("workouts", 3.0), ("rest", 90.0)];
const KCAL_PER_KG: f64 = 7700.0;

/* ---------- profile ---------- */

fn text_field(o: &Map<String, Value>, k: &str, max: usize) -> Result<Option<String>, String> {
    match o.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(s)) if s.chars().count() <= max => Ok(Some(s.trim().to_string()).filter(|s| !s.is_empty())),
        Some(_) => Err(format!("{k} must be text of at most {max} characters")),
    }
}

fn opt_int(o: &Map<String, Value>, k: &str, lo: i64, hi: i64) -> Result<Option<i64>, String> {
    match o.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(_) => int_field(o, k, lo, hi).map(Some),
    }
}

fn date_field(o: &Map<String, Value>, k: &str) -> Result<Option<String>, String> {
    match o.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(s)) if valid_date(s) => Ok(Some(s.clone())),
        Some(_) => Err(format!("{k} must be a date like 2026-12-31")),
    }
}

pub fn only_keys(o: &Map<String, Value>, keys: &[&str], at: &str) -> Result<(), String> {
    match o.keys().find(|k| !keys.contains(&k.as_str())) {
        Some(k) => Err(format!("{at}unknown field {k}")),
        None => Ok(()),
    }
}

// Validates a profile and returns it normalised (trimmed text, empty fields dropped).
pub fn parse_profile(v: &Value) -> Result<Value, String> {
    let o = v.as_object().ok_or("object expected")?;
    only_keys(
        o,
        &["birth_year", "goal", "goal_notes", "experience", "days_per_week", "days", "session_minutes", "equipment", "injuries", "conditions", "diet", "notes", "goals"],
        "",
    )?;
    let mut out = Map::new();
    if let Some(y) = opt_int(o, "birth_year", 1900, 2030)? {
        out.insert("birth_year".into(), json!(y));
    }
    match o.get("goal") {
        None | Some(Value::Null) => {}
        Some(Value::String(g)) if GOAL_KINDS.contains(&g.as_str()) => {
            out.insert("goal".into(), json!(g));
        }
        Some(_) => return Err(format!("goal must be one of {}", GOAL_KINDS.join(", "))),
    }
    for (k, max) in [("goal_notes", 500), ("experience", 300), ("equipment", 1500), ("injuries", 500), ("conditions", 500), ("diet", 500), ("notes", 1000)] {
        if let Some(t) = text_field(o, k, max)? {
            out.insert(k.into(), json!(t));
        }
    }
    if let Some(n) = opt_int(o, "days_per_week", 1, 7)? {
        out.insert("days_per_week".into(), json!(n));
    }
    if let Some(n) = opt_int(o, "session_minutes", 10, 240)? {
        out.insert("session_minutes".into(), json!(n));
    }
    match o.get("days") {
        None | Some(Value::Null) => {}
        Some(Value::Array(a)) => {
            let mut days: Vec<&str> = Vec::new();
            for d in a {
                let d = d.as_str().filter(|d| WEEKDAYS.contains(d)).ok_or("days must be weekdays like mon, wed, fri")?;
                if !days.contains(&d) {
                    days.push(d);
                }
            }
            days.sort_by_key(|d| WEEKDAYS.iter().position(|w| w == d));
            if !days.is_empty() {
                out.insert("days".into(), json!(days));
            }
        }
        Some(_) => return Err("days must be a list".into()),
    }
    match o.get("goals") {
        None | Some(Value::Null) => {}
        Some(Value::Array(a)) => {
            if a.len() > 5 {
                return Err("at most 5 goals".into());
            }
            let mut goals = Vec::new();
            for (i, g) in a.iter().enumerate() {
                let at = format!("goal {}: ", i + 1);
                let g = g.as_object().ok_or_else(|| format!("{at}object expected"))?;
                only_keys(g, &["measure", "exercise", "target", "by", "label", "milestones"], &at)?;
                let measure = g.get("measure").and_then(Value::as_str).filter(|m| MEASURES.contains(m));
                let measure = measure.ok_or_else(|| format!("{at}measure must be one of {}", MEASURES.join(", ")))?;
                let mut m = Map::new();
                m.insert("measure".into(), json!(measure));
                match (measure, g.get("exercise").and_then(Value::as_str)) {
                    ("exercise", Some(k)) if valid_key(k) => {
                        m.insert("exercise".into(), json!(k));
                    }
                    ("exercise", _) => return Err(format!("{at}an exercise goal needs the exercise key")),
                    (_, None) => {}
                    (_, Some(_)) => return Err(format!("{at}exercise is only for exercise goals")),
                }
                let target = num_field(g.get("target"), "target", 1000.0).map_err(|e| format!("{at}{e}"))?.filter(|t| *t > 0.0);
                m.insert("target".into(), num_value(target.ok_or_else(|| format!("{at}target must be a number above 0"))?));
                if let Some(by) = date_field(g, "by").map_err(|e| format!("{at}{e}"))? {
                    m.insert("by".into(), json!(by));
                }
                if let Some(l) = text_field(g, "label", 60).map_err(|e| format!("{at}{e}"))? {
                    m.insert("label".into(), json!(l));
                }
                match g.get("milestones") {
                    None | Some(Value::Null) => {}
                    Some(Value::Array(ms)) => {
                        if ms.len() > 6 {
                            return Err(format!("{at}at most 6 milestones"));
                        }
                        let mut list = Vec::new();
                        for ms in ms {
                            let ms = ms.as_object().ok_or_else(|| format!("{at}a milestone is {{value, by}}"))?;
                            only_keys(ms, &["value", "by"], &at)?;
                            let value = num_field(ms.get("value"), "milestone value", 1000.0).map_err(|e| format!("{at}{e}"))?;
                            let by = date_field(ms, "by").map_err(|e| format!("{at}{e}"))?;
                            match (value, by) {
                                (Some(v), Some(b)) => list.push(json!({ "value": num_value(v), "by": b })),
                                _ => return Err(format!("{at}a milestone needs a value and a date")),
                            }
                        }
                        list.sort_by(|a, b| a["by"].as_str().cmp(&b["by"].as_str()));
                        if !list.is_empty() {
                            m.insert("milestones".into(), Value::Array(list));
                        }
                    }
                    Some(_) => return Err(format!("{at}milestones must be a list")),
                }
                goals.push(Value::Object(m));
            }
            if !goals.is_empty() {
                out.insert("goals".into(), Value::Array(goals));
            }
        }
        Some(_) => return Err("goals must be a list".into()),
    }
    Ok(Value::Object(out))
}

pub fn get_profile(c: &Connection, user: &str) -> rusqlite::Result<Option<(i64, Value)>> {
    let row = c
        .query_row("SELECT data, version FROM profiles WHERE user = ?1", params![user], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))
        .optional()?;
    Ok(row.map(|(d, v)| (v, serde_json::from_str(&d).unwrap_or(Value::Null))))
}

fn profile_updated(c: &Connection, user: &str) -> rusqlite::Result<Option<i64>> {
    c.query_row("SELECT updated FROM profiles WHERE user = ?1", params![user], |r| r.get(0)).optional()
}

// Version-checked like the other documents; the version it replaces goes to history.
pub fn write_profile(c: &Connection, user: &str, p: &Value, base: i64) -> rusqlite::Result<Option<i64>> {
    let tx = c.unchecked_transaction()?;
    let cur: Option<i64> = tx.query_row("SELECT version FROM profiles WHERE user = ?1", params![user], |r| r.get(0)).optional()?;
    if cur.unwrap_or(0) != base {
        return Ok(None);
    }
    tx.execute(
        "INSERT OR REPLACE INTO profile_history(user, version, data, updated) SELECT user, version, data, updated FROM profiles WHERE user = ?1",
        params![user],
    )?;
    let version = base + 1;
    tx.execute(
        "INSERT INTO profiles(user, data, version, updated) VALUES(?1, ?2, ?3, ?4)
         ON CONFLICT(user) DO UPDATE SET data = excluded.data, version = excluded.version, updated = excluded.updated",
        params![user, p.to_string(), version, now()],
    )?;
    tx.commit()?;
    Ok(Some(version))
}

/* ---------- coach log ---------- */

pub fn add_log(c: &Connection, user: &str, author: &str, kind: &str, text: &str) -> Result<i64, String> {
    add_log_at(c, user, now(), author, kind, text)
}

fn add_log_at(c: &Connection, user: &str, at: i64, author: &str, kind: &str, text: &str) -> Result<i64, String> {
    if !["you", "coach", "app"].contains(&author) {
        return Err("author must be you, coach or app".into());
    }
    if !LOG_KINDS.contains(&kind) {
        return Err(format!("kind must be one of {}", LOG_KINDS.join(", ")));
    }
    let text = text.trim();
    if text.is_empty() || text.chars().count() > MAX_LOG {
        return Err(format!("the entry must be 1 to {MAX_LOG} characters"));
    }
    c.execute("INSERT INTO coach_log(user, at, author, kind, text) VALUES(?1, ?2, ?3, ?4, ?5)", params![user, at, author, kind, text])
        .map_err(|e| e.to_string())?;
    Ok(c.last_insert_rowid())
}

pub fn list_log(c: &Connection, user: &str, limit: i64) -> rusqlite::Result<Vec<Value>> {
    let mut st = c.prepare_cached("SELECT id, at, author, kind, text FROM coach_log WHERE user = ?1 ORDER BY id DESC LIMIT ?2")?;
    let rows = st.query_map(params![user, limit], |r| {
        Ok(json!({ "id": r.get::<_, i64>(0)?, "at": r.get::<_, i64>(1)?, "author": r.get::<_, String>(2)?,
                   "kind": r.get::<_, String>(3)?, "text": r.get::<_, String>(4)? }))
    })?;
    rows.collect()
}

pub fn last_check_in(c: &Connection, user: &str) -> rusqlite::Result<Option<i64>> {
    c.query_row("SELECT max(at) FROM coach_log WHERE user = ?1 AND kind = 'check-in'", params![user], |r| r.get(0))
}

/* ---------- proposals ---------- */

fn target_label(t: &str) -> &'static str {
    match t {
        "plan" => "your plan",
        "settings" => "your targets",
        _ => "your profile",
    }
}

fn current_version(c: &Connection, user: &str, target: &str) -> rusqlite::Result<i64> {
    Ok(get_doc(c, user, target)?.map(|(v, _)| v).unwrap_or(0))
}

// The stored form of a proposal's data: validated with the same rules as a save.
fn checked(target: &str, data: &Value) -> Result<Value, String> {
    match target {
        "plan" => parse_plan(data).map(|_| data.clone()),
        "settings" => parse_settings(data).map(|_| data.clone()),
        "profile" => parse_profile(data),
        _ => Err(format!("target must be one of {}", TARGETS.join(", "))),
    }
}

// Stores a proposal against the current version of its target; an older open one
// for the same target is superseded. Returns the new proposal's id.
pub fn propose(c: &Connection, user: &str, target: &str, data: &Value, why: &str) -> Result<i64, String> {
    let why = why.trim();
    if why.is_empty() || why.chars().count() > MAX_WHY {
        return Err(format!("why must be 1 to {MAX_WHY} characters"));
    }
    let data = checked(target, data)?;
    let e = |e: rusqlite::Error| e.to_string();
    let tx = c.unchecked_transaction().map_err(e)?;
    let base = current_version(&tx, user, target).map_err(e)?;
    let old: Vec<i64> = {
        let mut st = tx.prepare("SELECT id FROM proposals WHERE user = ?1 AND target = ?2 AND status = 'open'").map_err(e)?;
        let rows = st.query_map(params![user, target], |r| r.get(0)).map_err(e)?;
        rows.collect::<rusqlite::Result<_>>().map_err(e)?
    };
    tx.execute(
        "INSERT INTO proposals(user, target, base_version, data, why, status, created) VALUES(?1, ?2, ?3, ?4, ?5, 'open', ?6)",
        params![user, target, base, data.to_string(), why, now()],
    )
    .map_err(e)?;
    let id = tx.last_insert_rowid();
    for o in old {
        tx.execute("UPDATE proposals SET status = 'superseded', decided = ?1 WHERE id = ?2", params![now(), o]).map_err(e)?;
        add_log(&tx, user, "app", "decision", &format!("Proposal #{o} for {} was replaced by #{id}.", target_label(target)))?;
    }
    add_log(&tx, user, "coach", "note", &format!("Proposed a change to {} (#{id}): {why}", target_label(target)))?;
    tx.commit().map_err(e)?;
    Ok(id)
}

#[derive(Debug, PartialEq)]
pub enum Decision {
    Accepted(i64),
    Rejected,
    Outdated,
    NotFound,
    NotOpen(String),
}

pub fn decide(c: &Connection, user: &str, id: i64, accept: bool, note: Option<&str>) -> Result<Decision, String> {
    let e = |e: rusqlite::Error| e.to_string();
    let row = c
        .query_row("SELECT target, base_version, data, why, status FROM proposals WHERE id = ?1 AND user = ?2", params![id, user], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?, r.get::<_, String>(2)?, r.get::<_, String>(3)?, r.get::<_, String>(4)?))
        })
        .optional()
        .map_err(e)?;
    let Some((target, base, data, why, status)) = row else { return Ok(Decision::NotFound) };
    if status != "open" {
        return Ok(Decision::NotOpen(status));
    }
    let note = note.map(str::trim).filter(|n| !n.is_empty()).map(|n| n.chars().take(500).collect::<String>());
    let tail = note.as_ref().map(|n| format!(" Your note: {n}")).unwrap_or_default();
    let label = target_label(&target);
    let finish = |status: &str, text: String| -> Result<(), String> {
        c.execute("UPDATE proposals SET status = ?1, decided = ?2, note = ?3 WHERE id = ?4", params![status, now(), note, id]).map_err(e)?;
        add_log(c, user, "app", "decision", &text).map(|_| ())
    };
    if !accept {
        finish("rejected", format!("Rejected the change to {label} (#{id}): {why}{tail}"))?;
        return Ok(Decision::Rejected);
    }
    let outdated = |_: ()| -> Result<Decision, String> {
        finish("outdated", format!("The change to {label} (#{id}) was not applied: it changed after the proposal was written. {why}"))?;
        Ok(Decision::Outdated)
    };
    if current_version(c, user, &target).map_err(e)? != base {
        return outdated(());
    }
    let v: Value = serde_json::from_str(&data).map_err(|x| x.to_string())?;
    let written = match target.as_str() {
        "plan" => write_plan(c, user, &parse_plan(&v)?, base),
        "settings" => write_settings(c, user, &parse_settings(&v)?, base),
        _ => write_profile(c, user, &parse_profile(&v)?, base),
    }
    .map_err(e)?;
    match written {
        Some(version) => {
            finish("accepted", format!("Accepted the change to {label} (#{id}): {why}{tail}"))?;
            Ok(Decision::Accepted(version))
        }
        None => outdated(()),
    }
}

// Open proposals (with the current copy of their target, for the diff) and the
// last 10 decided ones.
pub fn list_proposals(c: &Connection, user: &str) -> rusqlite::Result<Vec<Value>> {
    let mut st = c.prepare_cached(
        "SELECT id, target, base_version, data, why, status, created, decided, note FROM proposals WHERE user = ?1
         ORDER BY status = 'open' DESC, id DESC LIMIT 20",
    )?;
    let rows = st.query_map(params![user], |r| {
        Ok((
            r.get::<_, i64>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, i64>(2)?,
            r.get::<_, String>(3)?,
            r.get::<_, String>(4)?,
            r.get::<_, String>(5)?,
            r.get::<_, i64>(6)?,
            r.get::<_, Option<i64>>(7)?,
            r.get::<_, Option<String>>(8)?,
        ))
    })?;
    let mut out = Vec::new();
    let mut decided = 0;
    for row in rows {
        let (id, target, base, data, why, status, created, dec, note) = row?;
        let open = status == "open";
        if !open {
            decided += 1;
            if decided > 10 {
                continue;
            }
        }
        let mut p = json!({ "id": id, "target": target, "base_version": base, "why": why, "status": status, "created": created,
                            "decided": dec, "note": note, "data": serde_json::from_str::<Value>(&data).unwrap_or(Value::Null) });
        if open {
            p["current"] = match get_doc(c, user, &target)? {
                Some((v, d)) => json!({ "version": v, "data": d }),
                None => Value::Null,
            };
        }
        out.push(p);
    }
    Ok(out)
}

/* ---------- dates ---------- */

// Days since 1970-01-01 for a valid YYYY-MM-DD (proleptic Gregorian).
pub fn day_num(s: &str) -> i64 {
    let (y, m, d) = (s[0..4].parse::<i64>().unwrap_or(1970), s[5..7].parse::<i64>().unwrap_or(1), s[8..10].parse::<i64>().unwrap_or(1));
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

pub fn day_str(n: i64) -> String {
    let z = n + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

// Today on the server's clock, in its local time zone (SQLite reads it from the C library).
pub fn local_today(c: &Connection) -> String {
    c.query_row("SELECT date('now', 'localtime')", [], |r| r.get::<_, String>(0)).unwrap_or_else(|_| day_str(now() / 86_400))
}

fn local_date_of(c: &Connection, ts: i64) -> String {
    c.query_row("SELECT date(?1, 'unixepoch', 'localtime')", params![ts], |r| r.get::<_, String>(0)).unwrap_or_else(|_| day_str(ts / 86_400))
}

/* ---------- summary ---------- */

const W: usize = 0;
const WAIST: usize = 1;
const KCAL: usize = 2;
const PROT: usize = 3;
const STEPS: usize = 4;
const SLEEP: usize = 5;
const BF: usize = 6;
const ENERGY: usize = 7;
const STRESS: usize = 8;
const SORE: usize = 9;
const HUNGER: usize = 10;
const MEASURES_CM: [(&str, usize); 5] = [("neck", 11), ("chest", 12), ("arm", 13), ("thigh", 14), ("hip", 15)];

struct DayRow {
    dn: i64,
    nums: [Option<f64>; NDAY],
    supps: Vec<String>,
    workout: bool,
    sets: BTreeMap<String, Vec<(Option<f64>, f64)>>,
    // Per set, parallel to `sets`: (reps in reserve, pain flag).
    effort: BTreeMap<String, Vec<(Option<i64>, bool)>>,
}

fn load_days(c: &Connection, user: &str) -> rusqlite::Result<Vec<DayRow>> {
    let mut st = c.prepare_cached(&format!("SELECT date, {}, workout, supps FROM days WHERE user = ?1 ORDER BY date", daily::day_cols()))?;
    let rows = st.query_map(params![user], |r| {
        let mut nums = [None; NDAY];
        for (i, n) in nums.iter_mut().enumerate() {
            *n = r.get::<_, Option<f64>>(i + 1)?;
        }
        let supps = r.get::<_, Option<String>>(NDAY + 2)?.and_then(|t| serde_json::from_str::<Vec<String>>(&t).ok()).unwrap_or_default();
        Ok((r.get::<_, String>(0)?, nums, r.get::<_, Option<String>>(NDAY + 1)?.is_some(), supps))
    })?;
    let mut days = Vec::new();
    let mut idx = BTreeMap::new();
    for row in rows {
        let (date, nums, workout, supps) = row?;
        idx.insert(date.clone(), days.len());
        days.push(DayRow { dn: day_num(&date), nums, supps, workout, sets: BTreeMap::new(), effort: BTreeMap::new() });
    }
    let mut st = c.prepare_cached("SELECT date, exercise, kg, reps, rir, pain FROM sets WHERE user = ?1 ORDER BY date, exercise, idx")?;
    let rows = st.query_map(params![user], |r| {
        Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, Option<f64>>(2)?, r.get::<_, f64>(3)?, r.get::<_, Option<i64>>(4)?, r.get::<_, Option<i64>>(5)? == Some(1)))
    })?;
    for row in rows {
        let (date, ex, kg, reps, rir, pain) = row?;
        if let Some(i) = idx.get(&date) {
            days[*i].effort.entry(ex.clone()).or_default().push((rir, pain));
            days[*i].sets.entry(ex).or_default().push((kg, reps));
        }
    }
    Ok(days)
}

fn mean(v: &[f64]) -> Option<f64> {
    if v.is_empty() {
        None
    } else {
        Some(v.iter().sum::<f64>() / v.len() as f64)
    }
}

// (day, value) of field `i` over (from, to].
fn points(days: &[DayRow], i: usize, from: i64, to: i64) -> Vec<(i64, f64)> {
    days.iter().filter(|d| d.dn > from && d.dn <= to).filter_map(|d| d.nums[i].map(|v| (d.dn, v))).collect()
}

// Least-squares slope per day, given enough points over enough days.
fn slope(p: &[(i64, f64)], min_pts: usize, min_span: i64) -> Option<f64> {
    if p.len() < min_pts || p.last()?.0 - p.first()?.0 < min_span {
        return None;
    }
    let n = p.len() as f64;
    let x0 = p[0].0;
    let (mut sx, mut sy, mut sxy, mut sxx) = (0.0, 0.0, 0.0, 0.0);
    for (d, v) in p {
        let x = (d - x0) as f64;
        sx += x;
        sy += v;
        sxy += x * v;
        sxx += x * x;
    }
    let den = n * sxx - sx * sx;
    if den == 0.0 {
        None
    } else {
        Some((n * sxy - sx * sy) / den)
    }
}

fn e1rm(w: Option<f64>, r: f64) -> Option<f64> {
    w.filter(|w| *w > 0.0 && r > 0.0).map(|w| w * (1.0 + r / 30.0))
}

#[derive(Clone)]
struct ExInfo {
    name: String,
    unit: String,
}

fn plan_info(plan: &Option<Value>) -> BTreeMap<String, ExInfo> {
    let mut m = BTreeMap::new();
    if let Some(p) = plan {
        for w in WORKOUTS {
            for e in p[w].as_array().into_iter().flatten() {
                if let (Some(k), Some(n), Some(u)) = (e["k"].as_str(), e["n"].as_str(), e["u"].as_str()) {
                    m.entry(k.to_string()).or_insert(ExInfo { name: n.into(), unit: u.into() });
                }
            }
        }
    }
    m
}

// Best set of each session of exercise k: (day, score, kg, reps). Score is the
// estimated 1-rep max for weighted work, reps or seconds otherwise.
fn sessions(days: &[DayRow], k: &str, unit: &str) -> Vec<(i64, f64, Option<f64>, f64)> {
    days.iter()
        .filter_map(|d| {
            let sets = d.sets.get(k)?;
            sets.iter()
                .filter_map(|(w, r)| {
                    let s = if unit == "kg" { e1rm(*w, *r) } else { Some(*r) };
                    s.map(|s| (d.dn, s, *w, *r))
                })
                .max_by(|a, b| a.1.total_cmp(&b.1))
        })
        .collect()
}

// Same rule as the page: 4+ sessions, the last 3 within 5% of the earlier best without beating it.
fn stalled(s: &[(i64, f64, Option<f64>, f64)]) -> bool {
    if s.len() < 4 {
        return false;
    }
    let prev = s[..s.len() - 3].iter().map(|x| x.1).fold(f64::MIN, f64::max);
    s[s.len() - 3..].iter().all(|x| x.1 <= prev + 1e-9 && x.1 >= prev * 0.95)
}

fn best_in(days: &[DayRow], info: &BTreeMap<String, ExInfo>, from: i64, to: i64) -> BTreeMap<String, f64> {
    let mut out: BTreeMap<String, f64> = BTreeMap::new();
    for d in days.iter().filter(|d| d.dn > from && d.dn <= to) {
        for (k, sets) in &d.sets {
            let unit = info.get(k).map(|i| i.unit.as_str()).unwrap_or("kg");
            for (w, r) in sets {
                if let Some(s) = if unit == "kg" { e1rm(*w, *r) } else { Some(*r) } {
                    let e = out.entry(k.clone()).or_insert(s);
                    *e = e.max(s);
                }
            }
        }
    }
    out
}

// Mean % change of each exercise's best over (end - span, end] against the span before.
fn strength_change(days: &[DayRow], info: &BTreeMap<String, ExInfo>, end: i64, span: i64) -> Option<(f64, usize)> {
    let now = best_in(days, info, end - span, end);
    let before = best_in(days, info, end - 2 * span, end - span);
    let ch: Vec<f64> = now.iter().filter_map(|(k, v)| before.get(k).filter(|b| **b > 0.0).map(|b| (v - b) / b * 100.0)).collect();
    mean(&ch).map(|m| (m, ch.len()))
}

fn r1(x: f64) -> Value {
    num_value((x * 10.0).round() / 10.0)
}

fn r2(x: f64) -> Value {
    num_value((x * 100.0).round() / 100.0)
}

fn target_of(t: &Map<String, Value>, k: &str) -> f64 {
    t.get(k).and_then(Value::as_f64).unwrap_or(0.0)
}

// The coach summary as data; `summary_text` renders it. `end` is the last day
// of the window (YYYY-MM-DD), `weeks` how many weeks of weekly rows to include.
pub fn summary(c: &Connection, user: &str, end_s: &str, weeks: i64) -> rusqlite::Result<Value> {
    let end = day_num(end_s);
    let weeks = weeks.clamp(1, 26);
    let days = load_days(c, user)?;
    let settings = get_settings(c, user)?.map(|(_, s)| s).unwrap_or(json!({}));
    let mut targets = Map::new();
    for (k, v) in DEF_TARGETS {
        targets.insert(k.into(), num_value(v));
    }
    if let Value::Object(s) = &settings {
        for (k, v) in s {
            targets.insert(k.clone(), v.clone());
        }
    }
    let plan = get_plan(c, user)?;
    let plan_v = plan.as_ref().map(|(_, p)| p.clone());
    let info = plan_info(&plan_v);
    let profile = get_profile(c, user)?;
    let log = list_log(c, user, 10)?;
    let open_props = list_proposals(c, user)?.into_iter().filter(|p| p["status"] == "open").count();
    let check_in = last_check_in(c, user)?;
    let since_check_in = check_in.map(|t| end - day_num(&local_date_of(c, t)));
    let profile_changed = match (profile_updated(c, user)?, check_in) {
        (Some(u), Some(ci)) => Some(u > ci),
        (Some(_), None) => Some(true),
        _ => None,
    };

    // Body.
    let w7 = points(&days, W, end - 7, end);
    let w_avg7 = mean(&w7.iter().map(|p| p.1).collect::<Vec<_>>());
    let pace = slope(&points(&days, W, end - 28, end), 3, 6).map(|s| s * 7.0);
    let win = end - 7 * weeks;
    let waist = points(&days, WAIST, i64::MIN / 2, end);
    let waist_win = points(&days, WAIST, win, end);
    let bf7 = mean(&points(&days, BF, end - 7, end).iter().map(|p| p.1).collect::<Vec<_>>());
    let bf_win = points(&days, BF, win, end);
    let height = settings["height"].as_f64();
    let sex = settings["sex"].as_str();
    let waist_now = waist.last().map(|p| p.1);
    let rfm = match (height, waist_now, sex) {
        (Some(h), Some(w), Some(s)) if w > 0.0 => Some(if s == "f" { 76.0 } else { 64.0 } - 20.0 * h / w),
        _ => None,
    };
    let mut measurements = Map::new();
    for (name, i) in MEASURES_CM {
        let p = points(&days, i, i64::MIN / 2, end);
        if let (Some(first), Some(last)) = (p.first(), p.last()) {
            measurements.insert(name.into(), json!({ "latest": r1(last.1), "date": day_str(last.0), "change": r1(last.1 - first.1), "since": day_str(first.0) }));
        }
    }
    let body = json!({
        "measurements": measurements,
        "weight_avg7": w_avg7.map(r1), "pace_kg_week": pace.map(r2),
        "bmi": match (w_avg7, height) { (Some(w), Some(h)) if h > 0.0 => Some(r1(w / (h / 100.0).powi(2))), _ => None },
        "waist_latest": waist_now.map(r1), "waist_latest_date": waist.last().map(|p| day_str(p.0)),
        "waist_change": if waist_win.len() >= 2 { Some(r1(waist_win[waist_win.len() - 1].1 - waist_win[0].1)) } else { None },
        "bodyfat_avg7": bf7.map(r1),
        "bodyfat_change": if bf_win.len() >= 2 { Some(r1(bf_win[bf_win.len() - 1].1 - bf_win[0].1)) } else { None },
        "bodyfat_from_waist": rfm.map(r1),
        "lean_kg": match (w_avg7, bf7) { (Some(w), Some(b)) => Some(r1(w * (1.0 - b / 100.0))), _ => None },
    });

    // Extras: blood tests, cardio, photo count.
    let labs = extras::summary_labs(c, user, end_s)?;
    let cardio = extras::cardio_window(c, user, win, end)?;

    // Weekly adherence, newest first.
    let mut week_rows = Vec::new();
    for i in 0..weeks {
        let (to, from) = (end - 7 * i, end - 7 * (i + 1));
        let wd: Vec<&DayRow> = days.iter().filter(|d| d.dn > from && d.dn <= to).collect();
        let count = |f: &dyn Fn(&DayRow) -> bool| wd.iter().filter(|d| f(d)).count();
        let hit = |i: usize, t: f64| count(&|d| d.nums[i].is_some_and(|v| v >= t));
        let avg = |i: usize| mean(&wd.iter().filter_map(|d| d.nums[i]).collect::<Vec<_>>()).map(r1);
        // Rest days (no workout) use the rest-day calorie target when one is set.
        let kcal_cap = |d: &DayRow| match (d.workout, targets.get("kcal_rest").and_then(Value::as_f64)) {
            (false, Some(r)) => r,
            _ => target_of(&targets, "kcal"),
        };
        week_rows.push(json!({
            "start": day_str(from + 1), "end": day_str(to),
            "workouts": count(&|d| d.workout), "planned": num_value(target_of(&targets, "workouts")),
            "protein_days": hit(PROT, target_of(&targets, "protein")),
            "kcal_ok_days": count(&|d| d.nums[KCAL].is_some_and(|v| v <= kcal_cap(d) * 1.05)),
            "kcal_logged": count(&|d| d.nums[KCAL].is_some()),
            "steps_days": hit(STEPS, target_of(&targets, "steps")),
            "sleep_days": hit(SLEEP, target_of(&targets, "sleep")),
            "empty_days": 7 - wd.len(),
            "energy_avg": avg(ENERGY), "stress_avg": avg(STRESS), "soreness_avg": avg(SORE), "hunger_avg": avg(HUNGER),
            "cardio_minutes": cardio.iter().filter(|x| x.0 > from && x.0 <= to).map(|x| x.2).sum::<i64>(),
            "weight_avg": mean(&wd.iter().filter_map(|d| d.nums[W]).collect::<Vec<_>>()).map(r1),
        }));
    }

    // Training, plan exercises first, then anything else logged in the window.
    let mut keys: Vec<String> = Vec::new();
    if let Some(p) = &plan_v {
        for w in WORKOUTS {
            for e in p[w].as_array().into_iter().flatten() {
                if let Some(k) = e["k"].as_str() {
                    if !keys.iter().any(|x| x == k) {
                        keys.push(k.into());
                    }
                }
            }
        }
    }
    for d in days.iter().filter(|d| d.dn > win && d.dn <= end) {
        for k in d.sets.keys() {
            if !keys.contains(k) {
                keys.push(k.clone());
            }
        }
    }
    let mut training = Vec::new();
    for k in &keys {
        let inf = info.get(k).cloned().unwrap_or(ExInfo { name: k.clone(), unit: "kg".into() });
        let s: Vec<_> = sessions(&days, k, &inf.unit).into_iter().filter(|x| x.0 <= end).collect();
        let set_v = |x: &(i64, f64, Option<f64>, f64)| json!({ "date": day_str(x.0), "kg": x.2.map(num_value), "reps": num_value(x.3), "score": r1(x.1) });
        let week_best = s.iter().filter(|x| x.0 > end - 7).max_by(|a, b| a.1.total_cmp(&b.1));
        let best = s.iter().max_by(|a, b| a.1.total_cmp(&b.1));
        let change = s.last().and_then(|l| s.iter().rev().find(|x| x.0 <= l.0 - 28).map(|r| (l.1 - r.1) / r.1 * 100.0));
        let no_effort = Vec::new();
        let effort = |d: &DayRow| d.effort.get(k).unwrap_or(&no_effort).clone();
        let pain_sessions = days.iter().filter(|d| d.dn > end - 14 && d.dn <= end).filter(|d| effort(d).iter().any(|e| e.1)).count();
        let last_day = days.iter().rfind(|d| d.dn <= end && d.sets.contains_key(k));
        training.push(json!({
            "pain_sessions_14d": pain_sessions, "avg_rir_last": last_day.and_then(|d| training::avg_rir(&effort(d))).map(r1),
            "key": k, "name": inf.name, "unit": inf.unit, "sessions": s.len(),
            "last": s.last().map(set_v), "best_this_week": week_best.map(set_v), "best_ever": best.map(set_v),
            "change_4w_pct": change.map(r1), "stalled": stalled(&s),
        }));
    }
    let lifts_week = strength_change(&days, &info, end, 7);
    let lifts_prev_week = strength_change(&days, &info, end - 7, 7);
    let lifts_2w = strength_change(&days, &info, end, 14);

    // Nutrition over 28 days.
    let kc: Vec<f64> = points(&days, KCAL, end - 28, end).iter().map(|p| p.1).collect();
    let pr: Vec<f64> = points(&days, PROT, end - 28, end).iter().map(|p| p.1).collect();
    let s28 = slope(&points(&days, W, end - 28, end), 8, 14);
    let (maint, suggest) = match (mean(&kc), s28) {
        (Some(avg), Some(sl)) if kc.len() >= 14 => {
            let tdee = avg - sl * KCAL_PER_KG;
            (Some((tdee / 10.0).round() * 10.0), Some((((tdee - 0.375 * KCAL_PER_KG / 7.0) / 50.0).round() * 50.0).max(1200.0)))
        }
        _ => (None, None),
    };
    let nutrition = json!({
        "kcal_avg": mean(&kc).map(|x| num_value(x.round())), "kcal_days": kc.len(),
        "protein_avg": mean(&pr).map(|x| num_value(x.round())), "protein_days": pr.len(),
        "maintenance": maint.map(num_value), "suggested_kcal": suggest.map(num_value), "current_kcal": targets.get("kcal").cloned(),
    });

    // Supplements: share of the logged days in the window on which each was ticked.
    let logged: Vec<&DayRow> = days.iter().filter(|d| d.dn > win && d.dn <= end).collect();
    let supplements: Vec<Value> = daily::get_doc(c, user, "supplements")?
        .map(|(_, d)| d["items"].as_array().cloned().unwrap_or_default())
        .unwrap_or_default()
        .iter()
        .filter_map(|i| i["name"].as_str())
        .map(|n| {
            let taken = logged.iter().filter(|d| d.supps.iter().any(|s| s == n)).count();
            json!({ "name": n, "taken_days": taken, "logged_days": logged.len(),
                    "pct": if logged.is_empty() { Value::Null } else { json!((taken as f64 * 100.0 / logged.len() as f64).round() as i64) } })
        })
        .collect();

    // Goals.
    let mut goals = Vec::new();
    if let Some((_, p)) = &profile {
        for g in p["goals"].as_array().into_iter().flatten() {
            goals.push(goal_progress(&days, &info, g, end, w_avg7, waist_now, bf7));
        }
    }

    // Alerts, most urgent first.
    let mut alerts = Vec::new();
    let overdue: Vec<String> = labs["overdue"].as_array().into_iter().flatten().map(|l| format!("{} (last {}, due {})", f(&l["label"]), f(&l["date"]), f(&l["next_due"]))).collect();
    let mut alert = |kind: &str, text: String| alerts.push(json!({ "kind": kind, "text": text }));
    let sore: Vec<String> = training.iter().filter(|t| t["pain_sessions_14d"].as_i64().unwrap_or(0) > 0).map(|t| f(&t["name"])).collect();
    if !sore.is_empty() {
        alert("pain", format!("Pain flagged in the last 14 days: {}. Progression is paused on these; consider a swap from the library if it keeps happening.", sore.join(", ")));
    }
    if let (Some(p), Some(w)) = (pace, w_avg7) {
        if p < -0.01 * w {
            alert("weight", format!("Weight is falling {:.2} kg a week, faster than 1% of body weight. Eat more before muscle goes with it.", -p));
        }
    }
    if let (Some((a, _)), Some((b, _))) = (lifts_week, lifts_prev_week) {
        if a <= -2.0 && b <= -2.0 {
            alert("strength", format!("Lifts are down two weeks running ({a:+.1}% this week, {b:+.1}% the week before)."));
        }
    }
    match days.iter().rfind(|d| d.dn <= end) {
        None => alert("logging", "Nothing logged yet.".into()),
        Some(d) if end - d.dn >= 4 => alert("logging", format!("Nothing logged for {} days (last on {}).", end - d.dn, day_str(d.dn))),
        _ => {}
    }
    if !overdue.is_empty() {
        alert("labs", format!("Blood test recheck overdue: {}.", overdue.join("; ")));
    }
    if open_props > 0 {
        alert("proposal", format!("{open_props} proposal{} waiting for you in the app.", if open_props == 1 { "" } else { "s" }));
    }
    match since_check_in {
        None => alert("check-in", "No check-in yet.".into()),
        Some(n) if n >= 7 => alert("check-in", format!("Weekly check-in due: the last was {n} days ago.")),
        _ => {}
    }

    Ok(json!({
        "user": user, "end": end_s, "weeks": weeks,
        "alerts": alerts,
        "last_check_in": check_in.map(|t| local_date_of(c, t)), "days_since_check_in": since_check_in,
        "profile": profile.as_ref().map(|(v, d)| json!({ "version": v, "data": d })),
        "profile_changed_since_check_in": profile_changed,
        "goals": goals, "body": body, "weeks_detail": week_rows, "training": training,
        "cardio": extras::cardio_by_kind(&cardio), "labs": labs, "photos": extras::summary_photos(c, user)?,
        "lifts": {
            "this_week_pct": lifts_week.map(|x| r1(x.0)), "two_weeks_pct": lifts_2w.map(|x| r1(x.0)),
            "two_weeks_exercises": lifts_2w.map(|x| x.1),
        },
        "nutrition": nutrition, "supplements": supplements, "targets": Value::Object(targets),
        "block": training::block_summary(&plan_v, end), "library_count": training::library_count(),
        "plan": plan.map(|(v, p)| json!({ "version": v, "data": p })),
        "open_proposals": open_props, "log": log,
    }))
}

// Current value, finish date from the 28-day trend, and milestone status of one goal.
fn goal_progress(days: &[DayRow], info: &BTreeMap<String, ExInfo>, g: &Value, end: i64, w7: Option<f64>, waist: Option<f64>, bf7: Option<f64>) -> Value {
    let measure = g["measure"].as_str().unwrap_or("");
    let target = g["target"].as_f64().unwrap_or(0.0);
    let (current, trend_pts, unit, name): (Option<f64>, Vec<(i64, f64)>, &str, String) = match measure {
        "weight" => (w7, points(days, W, end - 28, end), "kg", "Weight".into()),
        "waist" => (waist, points(days, WAIST, end - 56, end), "cm", "Waist".into()),
        "bodyfat" => (bf7, points(days, BF, end - 28, end), "%", "Body fat".into()),
        _ => {
            // Exercise goals are a working weight: the heaviest set in the last 4 weeks.
            let k = g["exercise"].as_str().unwrap_or("");
            let heavy: Vec<(i64, f64)> = days
                .iter()
                .filter(|d| d.dn > end - 56 && d.dn <= end)
                .filter_map(|d| d.sets.get(k).and_then(|s| s.iter().filter_map(|x| x.0).reduce(f64::max)).map(|w| (d.dn, w)))
                .collect();
            let cur = heavy.iter().filter(|p| p.0 > end - 28).map(|p| p.1).reduce(f64::max);
            (cur, heavy, "kg", info.get(k).map(|i| i.name.clone()).unwrap_or_else(|| k.to_string()))
        }
    };
    let rate = slope(&trend_pts, 3, 10);
    let down = current.is_some_and(|c| target < c);
    // Day the trend reaches `v`, if it is heading that way and gets there within 3 years.
    let reach = |v: f64| -> Option<i64> {
        let (c, r) = (current?, rate?);
        if (v - c).abs() < 1e-9 {
            return Some(end);
        }
        let d = (v - c) / r;
        (d > 0.0 && d < 1095.0).then(|| end + d.round() as i64)
    };
    let met = |v: f64| current.is_some_and(|c| if down { c <= v } else { c >= v });
    let milestones: Vec<Value> = g["milestones"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|m| {
            let (v, by) = (m["value"].as_f64().unwrap_or(0.0), m["by"].as_str().unwrap_or("1970-01-01"));
            let status = if met(v) {
                "met"
            } else if day_num(by) < end {
                "missed"
            } else {
                match reach(v) {
                    Some(d) if d <= day_num(by) => "on track",
                    Some(_) => "behind",
                    None => "no trend yet",
                }
            };
            json!({ "value": m["value"], "by": by, "status": status })
        })
        .collect();
    json!({
        "label": g.get("label").cloned().unwrap_or_else(|| json!(name)), "measure": measure, "exercise": g.get("exercise"),
        "unit": unit, "current": current.map(r1), "target": g["target"], "by": g.get("by"),
        "rate_per_week": rate.map(|r| r2(r * 7.0)),
        "eta": if met(target) { Some("reached".to_string()) } else { reach(target).map(day_str) },
        "milestones": milestones,
    })
}

fn f(v: &Value) -> String {
    match v {
        Value::Null => "—".into(),
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}

// Plain-text rendering of `summary` for a coach to read.
pub fn summary_text(s: &Value) -> String {
    use std::fmt::Write;
    let mut o = String::new();
    let _ = writeln!(o, "COACH SUMMARY for {}, {} weeks to {}", f(&s["user"]), s["weeks"], f(&s["end"]));
    let _ = writeln!(
        o,
        "Last check-in: {}{}. Profile changed since then: {}.",
        f(&s["last_check_in"]),
        s["days_since_check_in"].as_i64().map(|n| format!(" ({n} days ago)")).unwrap_or_default(),
        match s["profile_changed_since_check_in"].as_bool() {
            Some(true) => "yes",
            Some(false) => "no",
            None => "no profile",
        }
    );
    let _ = writeln!(o, "\nALERTS");
    let alerts = s["alerts"].as_array().cloned().unwrap_or_default();
    if alerts.is_empty() {
        let _ = writeln!(o, "  none");
    }
    for a in alerts {
        let _ = writeln!(o, "  - [{}] {}", f(&a["kind"]), f(&a["text"]));
    }
    let _ = writeln!(o, "\nPROFILE");
    match s["profile"]["data"].as_object() {
        None => {
            let _ = writeln!(o, "  none yet");
        }
        Some(p) => {
            let _ = writeln!(o, "  version {}", s["profile"]["version"]);
            for (k, v) in p {
                if k != "goals" {
                    let _ = writeln!(o, "  {k}: {}", if let Value::Array(a) = v { a.iter().map(f).collect::<Vec<_>>().join(", ") } else { f(v) });
                }
            }
        }
    }
    let _ = writeln!(o, "\nGOALS");
    let goals = s["goals"].as_array().cloned().unwrap_or_default();
    if goals.is_empty() {
        let _ = writeln!(o, "  none set");
    }
    for g in goals {
        let _ = writeln!(
            o,
            "  - {}: now {} {u}, target {} {u}{}; trend {} {u}/week; reaches it: {}",
            f(&g["label"]),
            f(&g["current"]),
            f(&g["target"]),
            g["by"].as_str().map(|b| format!(" by {b}")).unwrap_or_default(),
            f(&g["rate_per_week"]),
            f(&g["eta"]),
            u = f(&g["unit"])
        );
        for m in g["milestones"].as_array().into_iter().flatten() {
            let _ = writeln!(o, "      milestone {} by {}: {}", f(&m["value"]), f(&m["by"]), f(&m["status"]));
        }
    }
    let b = &s["body"];
    let _ = writeln!(o, "\nBODY");
    let _ = writeln!(o, "  Weight 7-day avg {} kg, pace {} kg/week (28 days), BMI {}", f(&b["weight_avg7"]), f(&b["pace_kg_week"]), f(&b["bmi"]));
    let _ = writeln!(o, "  Waist {} cm on {}, change {} cm over the window", f(&b["waist_latest"]), f(&b["waist_latest_date"]), f(&b["waist_change"]));
    let _ = writeln!(
        o,
        "  Body fat (scale) 7-day avg {}%, change {} points over the window; from waist {}%; lean mass {} kg",
        f(&b["bodyfat_avg7"]),
        f(&b["bodyfat_change"]),
        f(&b["bodyfat_from_waist"]),
        f(&b["lean_kg"])
    );
    let m = b["measurements"].as_object().cloned().unwrap_or_default();
    if m.is_empty() {
        let _ = writeln!(o, "  Measurements: none logged");
    }
    for (k, v) in &m {
        let _ = writeln!(o, "  {k} {} cm on {}, change {} cm since {}", f(&v["latest"]), f(&v["date"]), f(&v["change"]), f(&v["since"]));
    }
    let _ = writeln!(o, "\nWEEKS (newest first): workouts/planned, protein days, kcal on target/logged, steps days, sleep days, empty days, weight avg, check-in averages 1-5 (energy/stress/soreness/hunger)");
    for w in s["weeks_detail"].as_array().into_iter().flatten() {
        let _ = writeln!(
            o,
            "  {}..{}  {}/{}  protein {}  kcal {}/{}  steps {}  sleep {}  empty {}  weight {}  checkin {}/{}/{}/{}  cardio {} min",
            f(&w["start"]),
            f(&w["end"]),
            w["workouts"],
            w["planned"],
            w["protein_days"],
            w["kcal_ok_days"],
            w["kcal_logged"],
            w["steps_days"],
            w["sleep_days"],
            w["empty_days"],
            f(&w["weight_avg"]),
            f(&w["energy_avg"]),
            f(&w["stress_avg"]),
            f(&w["soreness_avg"]),
            f(&w["hunger_avg"]),
            w["cardio_minutes"]
        );
    }
    let l = &s["lifts"];
    let _ = writeln!(
        o,
        "\nTRAINING (lifts {}% over the last 2 weeks vs the 2 before, {} exercises; {}% this week vs last)",
        f(&l["two_weeks_pct"]),
        f(&l["two_weeks_exercises"]),
        f(&l["this_week_pct"])
    );
    let set = |v: &Value, u: &str| -> String {
        if v.is_null() {
            return "—".into();
        }
        if u == "kg" {
            format!("{} kg x {} ({})", f(&v["kg"]), f(&v["reps"]), f(&v["date"]))
        } else {
            format!("{} {u} ({})", f(&v["reps"]), f(&v["date"]))
        }
    };
    for t in s["training"].as_array().into_iter().flatten() {
        let u = t["unit"].as_str().unwrap_or("kg");
        let _ = writeln!(
            o,
            "  - {} [{}]: {} sessions; last {}; best this week {}; best ever {}; 4 weeks {}%{}",
            f(&t["name"]),
            f(&t["key"]),
            t["sessions"],
            set(&t["last"], u),
            set(&t["best_this_week"], u),
            set(&t["best_ever"], u),
            f(&t["change_4w_pct"]),
            if t["stalled"] == true { "; STALLED (no new best in 3 sessions)" } else { "" }
        );
        let pain = t["pain_sessions_14d"].as_i64().unwrap_or(0);
        if pain > 0 || !t["avg_rir_last"].is_null() {
            let _ = writeln!(
                o,
                "      {}{}",
                if pain > 0 { format!("PAIN in {pain} session{} in the last 14 days. ", if pain == 1 { "" } else { "s" }) } else { String::new() },
                if t["avg_rir_last"].is_null() { String::new() } else { format!("Last session avg RIR {} (reps in reserve).", f(&t["avg_rir_last"])) }
            );
        }
    }
    let _ = writeln!(o, "  Cardio and sport in the window (low impact preferred; ankle pain when running fast):");
    let cardio = s["cardio"].as_array().cloned().unwrap_or_default();
    if cardio.is_empty() {
        let _ = writeln!(o, "    none logged");
    }
    for k in cardio {
        let km = k["km"].as_f64().map(|x| format!(", {x} km")).unwrap_or_default();
        let _ = writeln!(o, "    - {}: {} sessions, {} min{km}", f(&k["kind"]), k["sessions"], k["minutes"]);
    }
    let n = &s["nutrition"];
    let _ = writeln!(o, "\nNUTRITION (28 days)");
    let _ = writeln!(
        o,
        "  Calories avg {} on {} logged days; protein avg {} g on {} days",
        f(&n["kcal_avg"]),
        n["kcal_days"],
        f(&n["protein_avg"]),
        n["protein_days"]
    );
    let _ = writeln!(
        o,
        "  Maintenance estimate {} kcal; suggested target {} kcal (current {})",
        f(&n["maintenance"]),
        f(&n["suggested_kcal"]),
        f(&n["current_kcal"])
    );
    let _ = writeln!(o, "\nSUPPLEMENTS (days ticked, of logged days in the window)");
    let sup = s["supplements"].as_array().cloned().unwrap_or_default();
    if sup.is_empty() {
        let _ = writeln!(o, "  none configured");
    }
    for x in sup {
        let _ = writeln!(o, "  - {}: {}/{} days ({}%)", f(&x["name"]), x["taken_days"], x["logged_days"], f(&x["pct"]));
    }
    let _ = writeln!(o, "\nBLOOD TESTS (typical ranges are general references, not a diagnosis)");
    let labs = s["labs"]["latest"].as_array().cloned().unwrap_or_default();
    if labs.is_empty() {
        let _ = writeln!(o, "  none logged");
    }
    for l in labs {
        let _ = writeln!(
            o,
            "  - {}: {} {} on {}{}; recheck {}{}",
            f(&l["label"]),
            f(&l["value"]),
            f(&l["unit"]),
            f(&l["date"]),
            if l["outside"] == true { format!(" ({} - outside typical range)", f(&l["direction"])) } else { String::new() },
            f(&l["next_due"]),
            if l["overdue"] == true { " (OVERDUE)" } else { "" }
        );
    }
    let _ = writeln!(o, "PROGRESS PHOTOS: {} stored, last on {} (not shown to the coach)", s["photos"]["count"], f(&s["photos"]["last_date"]));
    let _ = writeln!(o, "\nTARGETS (settings): {}", s["targets"]);
    let _ = writeln!(o, "\nPLAN");
    match s["plan"]["data"].as_object() {
        None => {
            let _ = writeln!(o, "  the app's starting plan (never saved; propose a full plan to replace it)");
        }
        Some(p) => {
            let _ = writeln!(o, "  version {}", s["plan"]["version"]);
            for w in WORKOUTS {
                let list: Vec<String> = p
                    .get(w)
                    .and_then(Value::as_array)
                    .into_iter()
                    .flatten()
                    .map(|e| {
                        format!(
                            "{} [{}] {}x{}-{} {}{}",
                            f(&e["n"]),
                            f(&e["k"]),
                            e["sets"],
                            e["lo"],
                            e["hi"],
                            f(&e["u"]),
                            e["inc"].as_f64().map(|i| format!(" +{i}")).unwrap_or_default()
                        )
                    })
                    .collect();
                let _ = writeln!(o, "  {w}: {}", list.join("; "));
            }
            if let Some(w) = s["block"]["week"].as_i64() {
                let _ = writeln!(o, "  Block: week {w} of {}{}", s["block"]["weeks"], if s["block"]["lighter_week"] == true { " (lighter week)" } else { "" });
            } else if !s["block"].is_null() {
                let _ = writeln!(o, "  Block: {} weeks from {}, not running on this date", s["block"]["weeks"], f(&s["block"]["start"]));
            }
            let _ = writeln!(o, "  Exercise library: {} exercises (GET /api/library)", s["library_count"]);
            let _ = writeln!(o, "  as JSON: {}", s["plan"]["data"]);
        }
    }
    let _ = writeln!(o, "\nOPEN PROPOSALS: {}", s["open_proposals"]);
    let _ = writeln!(o, "\nCOACH LOG (last 10, newest first)");
    let log = s["log"].as_array().cloned().unwrap_or_default();
    if log.is_empty() {
        let _ = writeln!(o, "  empty");
    }
    for e in log {
        let _ = writeln!(o, "  #{} {} {}: {}", e["id"], f(&e["author"]), f(&e["kind"]), f(&e["text"]));
    }
    o
}

/* ---------- HTTP ---------- */

fn query_param<'a>(query: &'a str, k: &str) -> Option<&'a str> {
    query.split('&').filter_map(|kv| kv.split_once('=')).find(|(a, _)| *a == k).map(|(_, v)| v)
}

// /api/coach/... routes. Proposals are never created over HTTP.
pub fn api(c: &Connection, user: &str, method: &Method, path: &str, query: &str, body: &[u8]) -> Reply {
    let rest = &path["/api/coach/".len()..];
    let json_body = || serde_json::from_slice::<Value>(if body.is_empty() { b"{}" } else { body });
    match (method, rest) {
        (Method::Get, "summary") => {
            let end = query_param(query, "end").filter(|d| valid_date(d)).map(str::to_string).unwrap_or_else(|| local_today(c));
            let weeks = query_param(query, "weeks").and_then(|w| w.parse().ok()).unwrap_or(6);
            match summary(c, user, &end, weeks) {
                Ok(mut s) => {
                    s["text"] = json!(summary_text(&s));
                    reply(200, s)
                }
                Err(e) => db_err(e),
            }
        }
        (Method::Get, "proposals") => match list_proposals(c, user) {
            Ok(p) => reply(200, json!({ "proposals": p })),
            Err(e) => db_err(e),
        },
        (Method::Post, p) if p.starts_with("proposals/") => {
            let mut parts = p["proposals/".len()..].splitn(2, '/');
            let (Some(id), Some(action)) = (parts.next().and_then(|i| i.parse::<i64>().ok()), parts.next()) else {
                return err(404, "not found");
            };
            if action != "accept" && action != "reject" {
                return err(404, "not found");
            }
            let Ok(v) = json_body() else { return err(400, "bad json") };
            let note = v["note"].as_str();
            match decide(c, user, id, action == "accept", note) {
                Ok(Decision::Accepted(version)) => reply(200, json!({ "status": "accepted", "version": version })),
                Ok(Decision::Rejected) => reply(200, json!({ "status": "rejected" })),
                Ok(Decision::Outdated) => reply(409, json!({ "status": "outdated", "error": "it changed after the proposal was written" })),
                Ok(Decision::NotFound) => err(404, "no such proposal"),
                Ok(Decision::NotOpen(s)) => reply(409, json!({ "status": s, "error": format!("already {s}") })),
                Err(e) => err(400, &e),
            }
        }
        (Method::Get, "log") => {
            let limit = query_param(query, "limit").and_then(|l| l.parse().ok()).unwrap_or(50i64).clamp(1, 500);
            match list_log(c, user, limit) {
                Ok(l) => reply(200, json!({ "entries": l })),
                Err(e) => db_err(e),
            }
        }
        (Method::Post, "log") => {
            let Ok(v) = json_body() else { return err(400, "bad json") };
            match add_log(c, user, "you", "note", v["text"].as_str().unwrap_or("")) {
                Ok(id) => reply(200, json!({ "id": id })),
                Err(e) => err(400, &e),
            }
        }
        _ => err(404, "not found"),
    }
}

/* ---------- export / import of the log ---------- */

pub fn export_log(c: &Connection, user: &str) -> rusqlite::Result<Value> {
    let mut l = list_log(c, user, i64::MAX)?;
    l.reverse();
    Ok(Value::Array(l))
}

// Imports a log only into an empty one, so history is never mixed or doubled.
// Returns (imported, invalid).
pub fn import_log(c: &Connection, user: &str, v: &Value) -> Result<(u32, u32), String> {
    let n: i64 = c.query_row("SELECT count(*) FROM coach_log WHERE user = ?1", params![user], |r| r.get(0)).map_err(|e| e.to_string())?;
    let list = v.as_array().ok_or("coach_log must be a list")?;
    if n > 0 {
        return Ok((0, 0));
    }
    let (mut ok, mut bad) = (0, 0);
    for e in list {
        let (Some(at), Some(author), Some(kind), Some(text)) = (e["at"].as_i64(), e["author"].as_str(), e["kind"].as_str(), e["text"].as_str()) else {
            bad += 1;
            continue;
        };
        if add_log_at(c, user, at, author, kind, text).is_err() {
            bad += 1;
            continue;
        }
        ok += 1;
    }
    Ok((ok, bad))
}
