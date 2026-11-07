// Training detail (schema v7): effort (RIR) and pain per set, the exercise
// library, training blocks (with deload weeks) and per-exercise progression rules.

use super::*;

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
}
