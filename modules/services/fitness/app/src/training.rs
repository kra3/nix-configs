// Training detail (schema v7): effort (RIR) and pain per set, the exercise
// library, training blocks (with deload weeks) and per-exercise progression rules.

use super::*;
use std::collections::BTreeMap;

// Schema version 7: RIR and pain flag per set; the training block on the plan;
// the progression rule per plan exercise.
pub const SCHEMA_7: &str = "
ALTER TABLE sets ADD COLUMN rir INTEGER CHECK (rir BETWEEN 0 AND 5);
ALTER TABLE sets ADD COLUMN pain INTEGER CHECK (pain = 1);
ALTER TABLE plans ADD COLUMN block_start TEXT;
ALTER TABLE plans ADD COLUMN block_weeks INTEGER;
ALTER TABLE plans ADD COLUMN block_deload TEXT;
ALTER TABLE plan_exercises ADD COLUMN prog TEXT CHECK (prog IN ('double', 'reps', 'hold'));
PRAGMA user_version = 7;";

// Schema version 10: rest seconds per plan exercise; the two session names on the plan.
pub const SCHEMA_10: &str = "
ALTER TABLE plan_exercises ADD COLUMN rest INTEGER;
ALTER TABLE plans ADD COLUMN name_a TEXT;
ALTER TABLE plans ADD COLUMN name_b TEXT;
PRAGMA user_version = 10;";

pub const PROGS: [&str; 3] = ["double", "reps", "hold"];

/* ---------- sets: [kg, reps] or [kg, reps, rir, pain] ---------- */

// kg, reps, reps in reserve (0..=5), pain flag.
pub type SetRow = (Option<f64>, f64, Option<i64>, bool);

pub fn parse_set(ex: &str, i: usize, s: &Value) -> Result<SetRow, String> {
    let at = format!("set {} of {ex}", i + 1);
    let a = s.as_array().filter(|p| (2..=4).contains(&p.len())).ok_or_else(|| format!("{at} must be [kg, reps] or [kg, reps, rir, pain]"))?;
    let kg = num_field(a.first(), "kg", 1_000.0)?;
    let reps = num_field(a.get(1), "reps", 1_000.0)?.ok_or_else(|| format!("{at} needs reps"))?;
    let rir = match a.get(2) {
        None | Some(Value::Null) => None,
        Some(v) => Some(v.as_i64().filter(|r| (0..=5).contains(r)).ok_or_else(|| format!("{at}: rir must be a whole number from 0 to 5 or null"))?),
    };
    let pain = match a.get(3) {
        None => false,
        Some(Value::Bool(b)) => *b,
        Some(_) => return Err(format!("{at}: pain must be true or false")),
    };
    Ok((kg, reps, rir, pain))
}

// The short form unless there is effort or pain to report.
pub fn set_value(kg: Option<f64>, reps: f64, rir: Option<i64>, pain: bool) -> Value {
    let (kg, reps) = (kg.map(num_value).unwrap_or(Value::Null), num_value(reps));
    if rir.is_none() && !pain {
        json!([kg, reps])
    } else {
        json!([kg, reps, rir, pain])
    }
}

pub fn avg_rir(sets: &[(Option<i64>, bool)]) -> Option<f64> {
    let r: Vec<f64> = sets.iter().filter_map(|s| s.0.map(|x| x as f64)).collect();
    if r.is_empty() {
        None
    } else {
        Some(r.iter().sum::<f64>() / r.len() as f64)
    }
}

/* ---------- progression rule ---------- */

pub fn parse_prog(v: Option<&Value>) -> Result<Option<String>, String> {
    match v {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(s)) if PROGS.contains(&s.as_str()) => Ok(Some(s.clone())),
        Some(_) => Err(format!("prog must be one of {}", PROGS.join(", "))),
    }
}

/* ---------- training block ---------- */

#[derive(Debug, PartialEq, Clone)]
pub struct Block {
    pub start: String,
    pub weeks: i64,
    pub deload: Vec<i64>,
}

// {"start": "YYYY-MM-DD", "weeks": 4..16, "deload": [week numbers]?}
pub fn parse_block(v: &Value) -> Result<Block, String> {
    let o = v.as_object().ok_or("block must be an object")?;
    if let Some(k) = o.keys().find(|k| !["start", "weeks", "deload"].contains(&k.as_str())) {
        return Err(format!("block: unknown field {k}"));
    }
    let start = o.get("start").and_then(Value::as_str).filter(|s| valid_date(s) && coach::day_str(coach::day_num(s)) == *s);
    let start = start.ok_or("block: start must be a date, YYYY-MM-DD")?.to_string();
    let weeks = int_field(o, "weeks", 4, 16).map_err(|m| format!("block: {m}"))?;
    let mut deload = Vec::new();
    match o.get("deload") {
        None | Some(Value::Null) => {}
        Some(Value::Array(a)) => {
            for w in a {
                let w = w.as_i64().filter(|w| (1..=weeks).contains(w) && !deload.contains(w));
                deload.push(w.ok_or_else(|| format!("block: deload weeks must be different whole numbers from 1 to {weeks}"))?);
            }
        }
        Some(_) => return Err("block: deload must be a list of week numbers".into()),
    }
    deload.sort_unstable();
    Ok(Block { start, weeks, deload })
}

// {"A": "Upper", "B": "Lower"}, each 1 to 20 characters.
pub fn parse_names(v: Option<&Value>) -> Result<[Option<String>; 2], String> {
    let mut out = [None, None];
    let o = match v {
        None | Some(Value::Null) => return Ok(out),
        Some(v) => v.as_object().ok_or("names must be an object")?,
    };
    if let Some(k) = o.keys().find(|k| !WORKOUTS.contains(&k.as_str())) {
        return Err(format!("names: unknown workout {k}"));
    }
    for (i, w) in WORKOUTS.iter().enumerate() {
        if let Some(n) = o.get(*w) {
            let n = n.as_str().map(str::trim).filter(|n| !n.is_empty() && n.chars().count() <= 20);
            out[i] = Some(n.ok_or_else(|| format!("names: {w} must be 1 to 20 characters"))?.to_string());
        }
    }
    Ok(out)
}

pub fn get_names(c: &Connection, user: &str) -> rusqlite::Result<Option<Value>> {
    let (a, b) = c.query_row("SELECT name_a, name_b FROM plans WHERE user = ?1", params![user], |r| Ok((r.get::<_, Option<String>>(0)?, r.get::<_, Option<String>>(1)?)))?;
    let mut m = Map::new();
    for (w, n) in WORKOUTS.iter().zip([a, b]) {
        if let Some(n) = n {
            m.insert((*w).into(), json!(n));
        }
    }
    Ok((!m.is_empty()).then_some(Value::Object(m)))
}

pub fn block_value(b: &Block) -> Value {
    json!({ "start": b.start, "weeks": b.weeks, "deload": b.deload })
}

pub fn get_block(c: &Connection, user: &str) -> rusqlite::Result<Option<Block>> {
    let row = c
        .query_row("SELECT block_start, block_weeks, block_deload FROM plans WHERE user = ?1", params![user], |r| {
            Ok((r.get::<_, Option<String>>(0)?, r.get::<_, Option<i64>>(1)?, r.get::<_, Option<String>>(2)?))
        })
        .optional()?;
    Ok(match row {
        Some((Some(start), Some(weeks), deload)) => {
            let deload = deload.unwrap_or_default().split(',').filter_map(|w| w.parse().ok()).collect();
            Some(Block { start, weeks, deload })
        }
        _ => None,
    })
}

pub fn write_block(c: &Connection, user: &str, b: Option<&Block>) -> rusqlite::Result<()> {
    let deload = b.map(|b| b.deload.iter().map(i64::to_string).collect::<Vec<_>>().join(","));
    c.execute(
        "UPDATE plans SET block_start = ?2, block_weeks = ?3, block_deload = ?4 WHERE user = ?1",
        params![user, b.map(|b| b.start.clone()), b.map(|b| b.weeks), deload],
    )?;
    Ok(())
}

// (week number, is a deload week) for day number `dn`, while the block runs.
pub fn block_week(b: &Block, dn: i64) -> Option<(i64, bool)> {
    let w = (dn - coach::day_num(&b.start)).div_euclid(7) + 1;
    (1..=b.weeks).contains(&w).then(|| (w, b.deload.contains(&w)))
}

// The plan's block and the current week of it, for the coach summary.
pub fn block_summary(plan: &Option<Value>, end: i64) -> Value {
    let Some(b) = plan.as_ref().and_then(|p| p.get("block")).and_then(|b| parse_block(b).ok()) else { return Value::Null };
    let wk = block_week(&b, end);
    let mut v = block_value(&b);
    v["week"] = json!(wk.map(|w| w.0));
    v["lighter_week"] = json!(wk.is_some_and(|w| w.1));
    v
}

/* ---------- exercise library ---------- */

const LIBRARY: &str = include_str!("library.json");

pub fn library() -> Reply {
    Reply { code: 200, ctype: JSON, body: LIBRARY.as_bytes().to_vec(), extra: vec![] }
}

const MUSCLES: [&str; 11] = ["chest", "back", "shoulders", "biceps", "triceps", "quads", "hamstrings", "glutes", "calves", "abs", "other"];

fn muscle_group(m: &str) -> &'static str {
    match m {
        "chest" => "chest",
        "back" | "lats" | "rear delts" => "back",
        "shoulders" | "side delts" => "shoulders",
        "biceps" => "biceps",
        "triceps" => "triceps",
        "quads" => "quads",
        "hamstrings" => "hamstrings",
        "glutes" | "glute medius" | "inner thighs" => "glutes",
        "calves" => "calves",
        "abs" | "core" => "abs",
        _ => "other",
    }
}

fn primary_muscles() -> BTreeMap<String, &'static str> {
    let lib: Vec<Value> = serde_json::from_str(LIBRARY).unwrap_or_default();
    lib.iter().filter_map(|e| Some((e["key"].as_str()?.to_string(), muscle_group(e["muscles"][0].as_str()?)))).collect()
}

#[cfg(test)]
fn muscle_of(key: &str) -> &'static str {
    primary_muscles().get(key).copied().unwrap_or("other")
}

// Working sets in the 7 days to `end`, and planned sets for the same span, per primary muscle.
// Muscles with neither are left out.
pub fn muscle_sets(c: &Connection, user: &str, end: &str) -> rusqlite::Result<Value> {
    let map = primary_muscles();
    let group = |k: &str| map.get(k).copied().unwrap_or("other");
    let n = coach::day_num(end);
    let mut done: BTreeMap<&str, i64> = BTreeMap::new();
    let mut st = c.prepare_cached("SELECT exercise, COUNT(*) FROM sets WHERE user = ?1 AND date > ?2 AND date <= ?3 AND reps > 0 GROUP BY exercise")?;
    for r in st.query_map(params![user, coach::day_str(n - 7), end], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))? {
        let (k, x) = r?;
        *done.entry(group(&k)).or_default() += x;
    }
    let per_week = get_settings(c, user)?.and_then(|(_, s)| s["workouts"].as_f64()).unwrap_or(3.0) / 2.0;
    let mut plan: BTreeMap<&str, i64> = BTreeMap::new();
    let mut st = c.prepare_cached("SELECT key, sets FROM plan_exercises WHERE user = ?1")?;
    for r in st.query_map(params![user], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))? {
        let (k, x) = r?;
        *plan.entry(group(&k)).or_default() += x;
    }
    Ok(MUSCLES
        .iter()
        .filter_map(|m| {
            let (d, p) = (done.get(m).copied().unwrap_or(0), plan.get(m).copied().unwrap_or(0));
            (d > 0 || p > 0).then(|| json!({ "m": m, "done": d, "planned": num_value(p as f64 * per_week) }))
        })
        .collect())
}

pub fn library_count() -> usize {
    serde_json::from_str::<Vec<Value>>(LIBRARY).map(|l| l.len()).unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn db() -> Connection {
        let c = Connection::open_in_memory().unwrap();
        init(&c).unwrap();
        c
    }

    fn put(c: &Connection, id: &str, base: &str, body: Value) -> (u16, Value) {
        let r = api(c, "kra3", &Method::Put, &format!("/api/log/{id}"), "", Some(base), body.to_string().as_bytes());
        (r.code, serde_json::from_slice(&r.body).unwrap_or(Value::Null))
    }

    #[test]
    fn sets_round_trip_long_and_short() {
        let c = db();
        let sets = json!({ "legpress": [[40, 10], [40, 10, 2, false], [40, 9, null, true], [null, 12, 0, true]] });
        assert_eq!(put(&c, "2026-11-03", "0", json!({ "date": "2026-11-03", "sets": sets })).0, 200);
        let got = get_day(&c, "kra3", "2026-11-03").unwrap().unwrap().1;
        // The short form stays short; anything with effort or pain comes back in full.
        assert_eq!(got["sets"]["legpress"], json!([[40, 10], [40, 10, 2, false], [40, 9, null, true], [null, 12, 0, true]]));
        let three = json!({ "date": "2026-11-04", "sets": { "row": [[30, 12, 3]] } });
        put(&c, "2026-11-04", "0", three);
        assert_eq!(get_day(&c, "kra3", "2026-11-04").unwrap().unwrap().1["sets"]["row"], json!([[30, 12, 3, false]]));
        let (rir, pain): (Option<i64>, Option<i64>) = c.query_row("SELECT rir, pain FROM sets WHERE date = '2026-11-03' AND idx = 2", [], |r| Ok((r.get(0)?, r.get(1)?))).unwrap();
        assert_eq!((rir, pain), (None, Some(1)));
    }

    #[test]
    fn rir_and_pain_are_validated() {
        let c = db();
        for bad in [json!([40, 10, 6]), json!([40, 10, -1]), json!([40, 10, 2.5]), json!([40, 10, "2"]), json!([40, 10, 1, "yes"]), json!([40, 10, 1, 1]), json!([40, 10, 1, true, 0]), json!([40])] {
            let (code, _) = put(&c, "2026-11-03", "0", json!({ "sets": { "legpress": [bad.clone()] } }));
            assert_eq!(code, 400, "{bad}");
        }
        assert_eq!(put(&c, "2026-11-03", "0", json!({ "sets": { "legpress": [[40, 10, 5, true], [40, 10, null]] } })).0, 200);
    }

    fn plan_with(f: &dyn Fn(&mut Value)) -> Value {
        let mut p = json!({ "A": [{ "k": "legpress", "n": "Leg press", "sets": 3, "lo": 10, "hi": 12, "u": "kg" }], "B": [] });
        f(&mut p);
        p
    }

    #[test]
    fn plan_block_and_prog_round_trip_and_validate() {
        let c = db();
        let good = plan_with(&|p| {
            p["block"] = json!({ "start": "2026-11-02", "weeks": 6, "deload": [6, 3] });
            p["A"][0]["prog"] = json!("reps");
        });
        assert_eq!(put(&c, "plan", "0", good).0, 200);
        let got = get_plan(&c, "kra3").unwrap().unwrap().1;
        assert_eq!(got["block"], json!({ "start": "2026-11-02", "weeks": 6, "deload": [3, 6] }));
        assert_eq!(got["A"][0]["prog"], json!("reps"));
        // Saving a plan without a block clears it.
        assert_eq!(put(&c, "plan", "1", plan_with(&|_| {})).0, 200);
        assert!(get_plan(&c, "kra3").unwrap().unwrap().1.get("block").is_none());
        for bad in [
            plan_with(&|p| p["block"] = json!({ "start": "2026-11-02", "weeks": 3 })),
            plan_with(&|p| p["block"] = json!({ "start": "2026-11-02", "weeks": 17 })),
            plan_with(&|p| p["block"] = json!({ "start": "2026-02-30", "weeks": 6 })),
            plan_with(&|p| p["block"] = json!({ "start": "soon", "weeks": 6 })),
            plan_with(&|p| p["block"] = json!({ "start": "2026-11-02", "weeks": 6, "deload": [7] })),
            plan_with(&|p| p["block"] = json!({ "start": "2026-11-02", "weeks": 6, "deload": [2, 2] })),
            plan_with(&|p| p["block"] = json!({ "start": "2026-11-02", "weeks": 6, "extra": 1 })),
            plan_with(&|p| p["block"] = json!("now")),
            plan_with(&|p| p["extra"] = json!(1)),
            plan_with(&|p| p["A"][0]["prog"] = json!("max")),
        ] {
            assert_eq!(put(&c, "plan", "2", bad.clone()).0, 400, "{bad}");
        }
    }

    #[test]
    fn block_weeks() {
        let b = Block { start: "2026-11-02".into(), weeks: 4, deload: vec![4] };
        let wk = |d: &str| block_week(&b, coach::day_num(d));
        assert_eq!(wk("2026-11-01"), None);
        assert_eq!(wk("2026-11-02"), Some((1, false)));
        assert_eq!(wk("2026-11-08"), Some((1, false)));
        assert_eq!(wk("2026-11-09"), Some((2, false)));
        assert_eq!(wk("2026-11-23"), Some((4, true)));
        assert_eq!(wk("2026-11-30"), None);
    }

    #[test]
    fn library_is_consistent() {
        let lib: Vec<Value> = serde_json::from_str(LIBRARY).unwrap();
        assert!(lib.len() >= 40 && library_count() == lib.len());
        let keys: Vec<&str> = lib.iter().map(|e| e["key"].as_str().unwrap()).collect();
        for k in ["legpress", "chestpress", "row", "legcurl", "crunch", "curl", "pushdown", "legext", "pulldown", "shoulder"] {
            assert!(keys.contains(&k), "{k}");
        }
        for e in &lib {
            let k = e["key"].as_str().unwrap();
            assert!(valid_key(k) && keys.iter().filter(|x| **x == k).count() == 1, "{k}");
            assert!(["machine", "cable", "dumbbell", "barbell", "bodyweight"].contains(&e["equipment"].as_str().unwrap()), "{k}");
            assert!(UNITS.contains(&e["unit"].as_str().unwrap()), "{k}");
            assert!(e["lo"].as_i64().unwrap() <= e["hi"].as_i64().unwrap() && !e["muscles"].as_array().unwrap().is_empty(), "{k}");
            assert!((1..=3).contains(&e["cues"].as_array().unwrap().len()), "{k}");
            assert!(e["knee_friendly"].is_boolean() && e["ankle_friendly"].is_boolean(), "{k}");
            for s in e["swaps"].as_array().unwrap() {
                assert!(keys.contains(&s.as_str().unwrap()), "{k} swaps {s}");
            }
        }
        let r = api(&db(), "kra3", &Method::Get, "/api/library", "", None, b"");
        assert_eq!((r.code, serde_json::from_slice::<Vec<Value>>(&r.body).unwrap().len()), (200, lib.len()));
    }

    #[test]
    fn migrates_a_version_6_database_keeping_sets() {
        let c = Connection::open_in_memory().unwrap();
        for m in &MIGRATIONS[..6] {
            c.execute_batch(&format!("BEGIN; {m} COMMIT;")).unwrap();
        }
        c.execute("INSERT INTO days(user, date, version, updated) VALUES('kra3', '2026-11-03', 1, 0)", []).unwrap();
        c.execute("INSERT INTO sets(user, date, exercise, idx, kg, reps) VALUES('kra3', '2026-11-03', 'legpress', 0, 40, 10)", []).unwrap();
        c.execute("INSERT INTO plans(user, version, updated) VALUES('kra3', 1, 0)", []).unwrap();
        init(&c).unwrap();
        let v: i64 = c.query_row("PRAGMA user_version", [], |r| r.get(0)).unwrap();
        assert_eq!(v, MIGRATIONS.len() as i64);
        assert_eq!(get_day(&c, "kra3", "2026-11-03").unwrap().unwrap().1["sets"], json!({ "legpress": [[40, 10]] }));
        assert_eq!(get_block(&c, "kra3").unwrap(), None);
    }

    #[test]
    fn summary_flags_pain_and_effort() {
        let c = db();
        put(&c, "plan", "0", plan_with(&|p| p["block"] = json!({ "start": "2026-11-02", "weeks": 4, "deload": [2] })));
        put(&c, "2026-11-01", "0", json!({ "sets": { "legpress": [[40, 10, 3, false]] } }));
        put(&c, "2026-11-03", "0", json!({ "sets": { "legpress": [[40, 10, 2, true], [40, 9, 1, false], [40, 9]] } }));
        put(&c, "2026-10-01", "0", json!({ "sets": { "legpress": [[30, 10, null, true]] } }));
        let s = coach::summary(&c, "kra3", "2026-11-04", 2).unwrap();
        let alert = s["alerts"].as_array().unwrap().iter().find(|a| a["kind"] == "pain").unwrap();
        assert!(alert["text"].as_str().unwrap().contains("Leg press"));
        let t = s["training"].as_array().unwrap().iter().find(|t| t["key"] == "legpress").unwrap();
        assert_eq!((t["pain_sessions_14d"].clone(), t["avg_rir_last"].clone()), (json!(1), json!(1.5)));
        assert_eq!(s["library_count"], json!(library_count()));
        assert_eq!(s["block"]["week"], json!(1));
        let text = coach::summary_text(&s);
        assert!(text.contains("PAIN in 1 session in the last 14 days") && text.contains("avg RIR 1.5") && text.contains("Block: week 1 of 4"), "{text}");
        let none = coach::summary(&c, "kra3", "2026-12-20", 2).unwrap();
        assert!(none["alerts"].as_array().unwrap().iter().all(|a| a["kind"] != "pain"));
        assert_eq!(none["block"]["week"], Value::Null);
    }

    #[test]
    fn plan_rest_round_trips_and_validates() {
        let c = db();
        let good = plan_with(&|p| p["A"][0]["rest"] = json!(150));
        assert_eq!(put(&c, "plan", "0", good.clone()).0, 200);
        assert_eq!(get_plan(&c, "kra3").unwrap().unwrap().1, good);
        for (base, ok) in [("1", 15), ("2", 900)] {
            assert_eq!(put(&c, "plan", base, plan_with(&|p| p["A"][0]["rest"] = json!(ok))).0, 200);
        }
        for bad in [json!(14), json!(901), json!(60.5), json!("60")] {
            assert_eq!(put(&c, "plan", "3", plan_with(&|p| p["A"][0]["rest"] = bad.clone())).0, 400, "{bad}");
        }
        assert_eq!(put(&c, "plan", "3", plan_with(&|_| {})).0, 200);
        assert!(get_plan(&c, "kra3").unwrap().unwrap().1["A"][0].get("rest").is_none());
    }

    #[test]
    fn plan_names_round_trip_and_validate() {
        let c = db();
        let good = plan_with(&|p| p["names"] = json!({ "A": "Upper", "B": "Lower" }));
        assert_eq!(put(&c, "plan", "0", good.clone()).0, 200);
        assert_eq!(get_plan(&c, "kra3").unwrap().unwrap().1, good);
        for bad in [json!({ "A": "" }), json!({ "A": "x".repeat(21) }), json!({ "C": "Core" }), json!("Upper"), json!({ "A": 1 })] {
            assert_eq!(put(&c, "plan", "1", plan_with(&|p| p["names"] = bad.clone())).0, 400, "{bad}");
        }
        assert_eq!(put(&c, "plan", "1", plan_with(&|p| p["names"] = json!({ "A": "x".repeat(20) }))).0, 200);
        assert_eq!(put(&c, "plan", "2", plan_with(&|_| {})).0, 200);
        assert!(get_plan(&c, "kra3").unwrap().unwrap().1.get("names").is_none());
    }

    #[test]
    fn sets_per_muscle() {
        let c = db();
        put(&c, "settings", "0", json!({ "workouts": 4 }));
        put(
            &c,
            "plan",
            "0",
            json!({ "A": [{ "k": "chestpress", "n": "Chest press", "sets": 3, "lo": 8, "hi": 12, "u": "kg" },
                          { "k": "pulldown", "n": "Pulldown", "sets": 2, "lo": 8, "hi": 12, "u": "kg" }],
                    "B": [{ "k": "chestpress", "n": "Chest press", "sets": 1, "lo": 8, "hi": 12, "u": "kg" }] }),
        );
        put(&c, "2026-11-10", "0", json!({ "sets": { "chestpress": [[40, 10], [40, 10], [40, 0]], "pulldown": [[30, 10]], "mystery": [[5, 5]] } }));
        put(&c, "2026-11-03", "0", json!({ "sets": { "chestpress": [[40, 10]] } }));
        put(&c, "2026-11-11", "0", json!({ "sets": { "chestpress": [[40, 10]] } }));
        let m = muscle_sets(&c, "kra3", "2026-11-10").unwrap();
        let get = |k: &str| m.as_array().unwrap().iter().find(|x| x["m"] == k).cloned();
        assert_eq!(get("chest"), Some(json!({ "m": "chest", "done": 2, "planned": 8 })));
        assert_eq!(get("back"), Some(json!({ "m": "back", "done": 1, "planned": 4 })));
        assert_eq!(get("other"), Some(json!({ "m": "other", "done": 1, "planned": 0 })));
        assert_eq!(get("quads"), None);
        assert_eq!(muscle_of("legpress"), "quads");
        assert_eq!(muscle_of("reardelt"), "back");
        assert_eq!(muscle_of("nope"), "other");
    }

    #[test]
    fn migrates_a_version_9_database_with_a_plan() {
        let c = Connection::open_in_memory().unwrap();
        for m in &MIGRATIONS[..9] {
            c.execute_batch(&format!("BEGIN; {m} COMMIT;")).unwrap();
        }
        c.execute("INSERT INTO plans(user, version, updated) VALUES('kra3', 1, 0)", []).unwrap();
        c.execute("INSERT INTO plan_exercises(user, workout, pos, key, name, sets, lo, hi, unit) VALUES('kra3', 'A', 0, 'legpress', 'Leg press', 3, 10, 12, 'kg')", []).unwrap();
        init(&c).unwrap();
        let plan = get_plan(&c, "kra3").unwrap().unwrap().1;
        assert_eq!(plan["A"][0]["k"], json!("legpress"));
        assert!(plan.get("names").is_none() && plan["A"][0].get("rest").is_none());
    }
}
