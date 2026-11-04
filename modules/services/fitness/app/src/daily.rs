// Daily inputs (schema v7): the four-tap check-in and body measurements (extra
// numeric day fields, see DAY_NUM), saved meals and the supplement list (small
// versioned documents), which supplements were taken (day field "supps"), the
// rest-day calorie target (settings.kcal_rest) and `fitness remind`.

use super::*;

pub const SCHEMA_7: &str = "
ALTER TABLE days ADD COLUMN energy REAL;
ALTER TABLE days ADD COLUMN stress REAL;
ALTER TABLE days ADD COLUMN soreness REAL;
ALTER TABLE days ADD COLUMN hunger REAL;
ALTER TABLE days ADD COLUMN neck REAL;
ALTER TABLE days ADD COLUMN chest REAL;
ALTER TABLE days ADD COLUMN arm REAL;
ALTER TABLE days ADD COLUMN thigh REAL;
ALTER TABLE days ADD COLUMN hip REAL;
ALTER TABLE days ADD COLUMN supps TEXT;
ALTER TABLE settings ADD COLUMN kcal_rest REAL;
CREATE TABLE user_docs(
  user TEXT NOT NULL, id TEXT NOT NULL CHECK (id IN ('meals', 'supplements')), data TEXT NOT NULL,
  version INTEGER NOT NULL, updated INTEGER NOT NULL,
  PRIMARY KEY (user, id)) WITHOUT ROWID;
PRAGMA user_version = 7;";

const MAX_MEALS: usize = 40;
const MAX_SUPPS: usize = 15;
const MAX_LABEL: usize = 40;
const MAX_WHY: usize = 200;
pub const TIMINGS: [&str; 5] = ["morning", "pre-workout", "post-workout", "evening", "any"];
// The check-in fields (a 1 to 5 scale) sit at these places in DAY_NUM.
const SCALE: std::ops::Range<usize> = 7..11;

pub fn day_cols() -> String {
    DAY_NUM.iter().map(|(n, _)| *n).collect::<Vec<_>>().join(", ")
}

// Check-in answers are whole numbers from 1 to 5.
pub fn check_scale(nums: &[Option<f64>; NDAY]) -> Result<(), String> {
    for i in SCALE {
        if nums[i].is_some_and(|x| x.fract() != 0.0 || x < 1.0) {
            return Err(format!("{} must be a whole number from 1 to 5", DAY_NUM[i].0));
        }
    }
    Ok(())
}

// Names of the supplements taken that day.
pub fn parse_taken(v: Option<&Value>) -> Result<Vec<String>, String> {
    let list = match v {
        None | Some(Value::Null) => return Ok(vec![]),
        Some(Value::Array(a)) => a,
        Some(_) => return Err("supps must be a list".into()),
    };
    if list.len() > MAX_SUPPS {
        return Err("too many supplements".into());
    }
    let mut out: Vec<String> = Vec::new();
    for x in list {
        let s = x.as_str().map(str::trim).filter(|s| !s.is_empty() && s.chars().count() <= MAX_LABEL);
        let s = s.ok_or_else(|| format!("each supplement must be 1 to {MAX_LABEL} characters"))?;
        if !out.iter().any(|o| o == s) {
            out.push(s.into());
        }
    }
    Ok(out)
}

// Insert or replace one day's row (not its sets).
pub fn upsert_day(c: &Connection, user: &str, date: &str, d: &Day, version: i64) -> rusqlite::Result<()> {
    let cols = day_cols();
    let n = NDAY + 7;
    let holders = (1..=n).map(|i| format!("?{i}")).collect::<Vec<_>>().join(", ");
    let sets = DAY_NUM.iter().map(|(k, _)| format!("{k} = excluded.{k}")).collect::<Vec<_>>().join(", ");
    let supps = if d.supps.is_empty() { None } else { Some(json!(d.supps).to_string()) };
    let ts = now();
    let mut p: Vec<&dyn rusqlite::ToSql> = vec![&user, &date];
    p.extend(d.nums.iter().map(|x| x as &dyn rusqlite::ToSql));
    p.extend([&d.note as &dyn rusqlite::ToSql, &d.workout, &supps, &version, &ts]);
    c.execute(
        &format!(
            "INSERT INTO days(user, date, {cols}, note, workout, supps, version, updated) VALUES({holders})
             ON CONFLICT(user, date) DO UPDATE SET {sets}, note = excluded.note, workout = excluded.workout,
               supps = excluded.supps, version = excluded.version, updated = excluded.updated"
        ),
        rusqlite::params_from_iter(p),
    )?;
    Ok(())
}

/* ---------- meals and supplements documents ---------- */

fn label(o: &Map<String, Value>, k: &str, max: usize, at: &str, required: bool) -> Result<Option<String>, String> {
    match o.get(k) {
        None | Some(Value::Null) if !required => Ok(None),
        Some(Value::String(s)) if s.trim().chars().count() <= max && (!required || !s.trim().is_empty()) => Ok(Some(s.trim().to_string()).filter(|s| !s.is_empty())),
        _ => Err(format!("{at}: {k} must be text of at most {max} characters{}", if required { ", not empty" } else { "" })),
    }
}

fn items<'a>(v: &'a Value, key: &str, max: usize) -> Result<&'a Vec<Value>, String> {
    let o = v.as_object().ok_or("object expected")?;
    if let Some(k) = o.keys().find(|k| *k != key) {
        return Err(format!("unknown field {k}"));
    }
    let list = o.get(key).and_then(Value::as_array).ok_or_else(|| format!("{key} must be a list"))?;
    if list.len() > max {
        return Err(format!("at most {max} {key}"));
    }
    Ok(list)
}

// {"meals": [{"name", "kcal", "protein"}, ...]}
pub fn parse_meals(v: &Value) -> Result<Value, String> {
    let mut out = Vec::new();
    for (i, m) in items(v, "meals", MAX_MEALS)?.iter().enumerate() {
        let at = format!("meal {}", i + 1);
        let o = m.as_object().ok_or_else(|| format!("{at} must be an object"))?;
        coach::only_keys(o, &["name", "kcal", "protein"], &format!("{at}: "))?;
        let name = label(o, "name", MAX_LABEL, &at, true)?;
        let kcal = num_field(o.get("kcal"), "kcal", 5_000.0).map_err(|e| format!("{at}: {e}"))?.ok_or_else(|| format!("{at}: kcal is required"))?;
        let protein = num_field(o.get("protein"), "protein", 300.0).map_err(|e| format!("{at}: {e}"))?.ok_or_else(|| format!("{at}: protein is required"))?;
        out.push(json!({ "name": name, "kcal": num_value(kcal), "protein": num_value(protein) }));
    }
    Ok(json!({ "meals": out }))
}

// {"items": [{"name", "dose"?, "timing"?, "why"?}, ...]}
pub fn parse_supplements(v: &Value) -> Result<Value, String> {
    let mut out: Vec<Value> = Vec::new();
    for (i, m) in items(v, "items", MAX_SUPPS)?.iter().enumerate() {
        let at = format!("supplement {}", i + 1);
        let o = m.as_object().ok_or_else(|| format!("{at} must be an object"))?;
        coach::only_keys(o, &["name", "dose", "timing", "why"], &format!("{at}: "))?;
        let name = label(o, "name", MAX_LABEL, &at, true)?.unwrap_or_default();
        if out.iter().any(|x| x["name"] == name.as_str()) {
            return Err(format!("{at}: {name} appears twice"));
        }
        let timing = match o.get("timing") {
            None | Some(Value::Null) => "any",
            Some(Value::String(t)) if TIMINGS.contains(&t.as_str()) => t.as_str(),
            Some(_) => return Err(format!("{at}: timing must be one of {}", TIMINGS.join(", "))),
        };
        let mut e = json!({ "name": name, "timing": timing });
        if let Some(d) = label(o, "dose", MAX_LABEL, &at, false)? {
            e["dose"] = json!(d);
        }
        if let Some(w) = label(o, "why", MAX_WHY, &at, false)? {
            e["why"] = json!(w);
        }
        out.push(e);
    }
    Ok(json!({ "items": out }))
}

pub fn parse_doc(id: &str, v: &Value) -> Result<Value, String> {
    if id == "meals" {
        parse_meals(v)
    } else {
        parse_supplements(v)
    }
}

pub fn get_doc(c: &Connection, user: &str, id: &str) -> rusqlite::Result<Option<(i64, Value)>> {
    let row: Option<(String, i64)> =
        c.query_row("SELECT data, version FROM user_docs WHERE user = ?1 AND id = ?2", params![user, id], |r| Ok((r.get(0)?, r.get(1)?))).optional()?;
    Ok(row.map(|(d, v)| (v, serde_json::from_str(&d).unwrap_or(Value::Null))))
}

// Version-checked like the other documents; `p` is already validated.
pub fn write_doc(c: &Connection, user: &str, id: &str, p: &Value, base: i64) -> rusqlite::Result<Option<i64>> {
    let tx = c.unchecked_transaction()?;
    let cur: Option<i64> = tx.query_row("SELECT version FROM user_docs WHERE user = ?1 AND id = ?2", params![user, id], |r| r.get(0)).optional()?;
    if cur.unwrap_or(0) != base {
        return Ok(None);
    }
    let version = base + 1;
    tx.execute(
        "INSERT INTO user_docs(user, id, data, version, updated) VALUES(?1, ?2, ?3, ?4, ?5)
         ON CONFLICT(user, id) DO UPDATE SET data = excluded.data, version = excluded.version, updated = excluded.updated",
        params![user, id, p.to_string(), version, now()],
    )?;
    tx.commit()?;
    Ok(Some(version))
}

/* ---------- reminders ---------- */

pub const KINDS: [&str; 4] = ["weigh-in", "food", "supps", "checkin"];

fn today_has(c: &Connection, user: &str, today: &str, field: &str) -> Result<bool, String> {
    let day = get_day(c, user, today).map_err(|e| e.to_string())?;
    Ok(day.is_some_and(|(_, d)| d.get(field).is_some()))
}

// The reminder text for `kind`, or None when there is nothing to remind about.
pub fn remind(c: &Connection, user: &str, kind: &str) -> Result<Option<String>, String> {
    let today = coach::local_today(c);
    Ok(match kind {
        "weigh-in" => (!today_has(c, user, &today, "weight")?).then(|| "No weigh-in yet today. Step on the scale or log your weight.".to_string()),
        "food" => (!today_has(c, user, &today, "kcal")?).then(|| "No food logged today. Add your calories and protein before bed.".to_string()),
        "supps" => {
            let list = get_doc(c, user, "supplements").map_err(|e| e.to_string())?.map(|(_, d)| d).unwrap_or(Value::Null);
            let taken = get_day(c, user, &today).map_err(|e| e.to_string())?.map(|(_, d)| d["supps"].clone()).unwrap_or(Value::Null);
            let left: Vec<&str> = list["items"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|i| i["name"].as_str())
                .filter(|n| !taken.as_array().is_some_and(|t| t.iter().any(|x| x == n)))
                .collect();
            (!left.is_empty()).then(|| format!("Supplements not ticked today: {}.", left.join(", ")))
        }
        "checkin" => {
            let last = coach::last_check_in(c, user).map_err(|e| e.to_string())?;
            match last {
                Some(t) if now() - t < 7 * 86_400 => None,
                Some(_) => Some("Your weekly coach check-in is due: it has been over a week.".into()),
                None => Some("No coach check-in yet. Start one from ~/fitness-coach.".into()),
            }
        }
        _ => return Err(format!("kind must be one of {}", KINDS.join(", "))),
    })
}

// fitness remind <user> <kind>: prints the message, or nothing; exit 0 either way.
pub fn cli(db_path: &str, args: &[String]) {
    let (Some(user), Some(kind)) = (args.first(), args.get(1)) else {
        eprintln!("usage: fitness remind <user> <weigh-in|food|supps|checkin>");
        process::exit(2);
    };
    match remind(&open(db_path), user, kind) {
        Ok(Some(msg)) => println!("{msg}"),
        Ok(None) => {}
        Err(e) => {
            eprintln!("{e}");
            process::exit(2);
        }
    }
}
