// `fitness coach ...`: the coach's tools on sutala, as commands and as an MCP
// server (newline-delimited JSON-RPC on stdin/stdout) for Claude Code. There is
// deliberately no way to accept a proposal here: only the app does that.

use super::*;
use coach::{LOG_KINDS, TARGETS};
use std::io::{BufRead, Write};

const INSTRUCTIONS: &str = "You are the user's fitness coach, working from their own data on their home server. \
Start every check-in with the summary tool. Deal with alerts first: weight falling faster than 1% a week, lifts \
down two weeks running, missed logging, open proposals. Changes go through propose: one target per proposal \
(plan, settings or profile), the whole new document, and a reason of one to three sentences. Nothing changes \
until the user accepts it in the app, so say so. Keep supplement advice to what the profile supports, and point \
to a doctor for anything touching a condition. End a check-in with a short log entry of kind check-in: what you \
saw, what you proposed, what to watch next week.";

fn tools() -> Value {
    json!([
        {
            "name": "summary",
            "description": "The coach summary: alerts, profile and goals with finish dates, body trends, weekly adherence, per-exercise training, nutrition and the maintenance estimate, current targets and plan (with its JSON), open proposals and the last 10 coach log entries.",
            "inputSchema": { "type": "object", "properties": {
                "weeks": { "type": "integer", "minimum": 1, "maximum": 26, "description": "Weeks of weekly rows, default 6" },
                "date": { "type": "string", "description": "Last day of the window, YYYY-MM-DD; default today" },
                "format": { "type": "string", "enum": ["text", "json"], "description": "Default text" }
            } }
        },
        {
            "name": "propose",
            "description": "Store a proposed change for the user to accept or reject in the app. `data` is the whole new document: for plan {\"A\": [{k, n, sets, lo, hi, u, inc?, prog?: double|reps|hold}], \"B\": [...], \"block\"?: {start: YYYY-MM-DD, weeks: 4-16, deload?: [week numbers]}} (exercise keys and defaults are in the app library, GET /api/library); for settings {kcal, kcal_rest (optional, non-workout days), protein, steps, sleep, workouts, rest, height, start_weight, sex}; for profile {birth_year, goal, goal_notes, experience, days_per_week, days, session_minutes, equipment, injuries, conditions, diet, notes, goals: [{measure, exercise?, target, by?, label?, milestones?: [{value, by}]}]}. Keep exercise keys (k) unchanged for exercises that stay, so their history carries over. A newer proposal for the same target replaces an open one.",
            "inputSchema": { "type": "object", "required": ["target", "data", "why"], "properties": {
                "target": { "type": "string", "enum": TARGETS },
                "data": { "type": "object" },
                "why": { "type": "string", "maxLength": 600, "description": "One to three sentences the user reads before deciding" }
            } }
        },
        {
            "name": "log",
            "description": "Read the coach log (newest first), or add an entry with `add`. Use kind check-in for the end of a weekly review.",
            "inputSchema": { "type": "object", "properties": {
                "add": { "type": "string", "maxLength": 1000 },
                "kind": { "type": "string", "enum": LOG_KINDS, "description": "For add; default note" },
                "limit": { "type": "integer", "minimum": 1, "maximum": 500, "description": "For reading; default 20" }
            } }
        },
        {
            "name": "proposals",
            "description": "Open proposals (with the current version of what they change) and the last 10 decided ones, with the user's notes.",
            "inputSchema": { "type": "object", "properties": {} }
        }
    ])
}

fn log_text(entries: &[Value]) -> String {
    if entries.is_empty() {
        return "The coach log is empty.".into();
    }
    entries.iter().map(|e| format!("#{} {} {}: {}", e["id"], e["author"].as_str().unwrap_or(""), e["kind"].as_str().unwrap_or(""), e["text"].as_str().unwrap_or(""))).collect::<Vec<_>>().join("\n")
}

pub fn tool_call(c: &Connection, user: &str, name: &str, a: &Value) -> Result<String, String> {
    let e = |e: rusqlite::Error| e.to_string();
    match name {
        "summary" => {
            let date = match a["date"].as_str() {
                Some(d) if valid_date(d) => d.to_string(),
                Some(_) => return Err("date must be YYYY-MM-DD".into()),
                None => coach::local_today(c),
            };
            let s = coach::summary(c, user, &date, a["weeks"].as_i64().unwrap_or(6)).map_err(e)?;
            Ok(if a["format"] == "json" { serde_json::to_string_pretty(&s).unwrap_or_default() } else { coach::summary_text(&s) })
        }
        "propose" => {
            let target = a["target"].as_str().ok_or("target is required")?;
            let id = coach::propose(c, user, target, &a["data"], a["why"].as_str().unwrap_or(""))?;
            Ok(format!("Stored proposal #{id} for {target}. It waits for the user to accept or reject it in the app; nothing has changed yet."))
        }
        "log" => match a["add"].as_str() {
            Some(text) => {
                let id = coach::add_log(c, user, "coach", a["kind"].as_str().unwrap_or("note"), text)?;
                Ok(format!("Logged as #{id}."))
            }
            None => Ok(log_text(&coach::list_log(c, user, a["limit"].as_i64().unwrap_or(20).clamp(1, 500)).map_err(e)?)),
        },
        "proposals" => Ok(serde_json::to_string_pretty(&coach::list_proposals(c, user).map_err(e)?).unwrap_or_default()),
        _ => Err(format!("unknown tool {name}")),
    }
}

// One JSON-RPC message in, at most one response out (none for notifications).
pub fn handle_message(c: &Connection, user: &str, msg: &Value) -> Option<Value> {
    let id = msg.get("id").cloned()?;
    let result = match msg["method"].as_str().unwrap_or("") {
        "initialize" => json!({
            "protocolVersion": msg["params"]["protocolVersion"].as_str().unwrap_or("2025-06-18"),
            "capabilities": { "tools": { "listChanged": false } },
            "serverInfo": { "name": "fitness", "version": env!("CARGO_PKG_VERSION") },
            "instructions": INSTRUCTIONS,
        }),
        "ping" => json!({}),
        "tools/list" => json!({ "tools": tools() }),
        "tools/call" => {
            let p = &msg["params"];
            match tool_call(c, user, p["name"].as_str().unwrap_or(""), &p["arguments"]) {
                Ok(text) => json!({ "content": [{ "type": "text", "text": text }], "isError": false }),
                Err(text) => json!({ "content": [{ "type": "text", "text": text }], "isError": true }),
            }
        }
        _ => return Some(json!({ "jsonrpc": "2.0", "id": id, "error": { "code": -32601, "message": "method not found" } })),
    };
    Some(json!({ "jsonrpc": "2.0", "id": id, "result": result }))
}

fn serve_mcp(c: &Connection, user: &str) {
    let stdin = std::io::stdin();
    let mut out = std::io::stdout();
    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        if line.trim().is_empty() {
            continue;
        }
        let resp = match serde_json::from_str::<Value>(&line) {
            Ok(msg) => handle_message(c, user, &msg),
            Err(_) => Some(json!({ "jsonrpc": "2.0", "id": null, "error": { "code": -32700, "message": "parse error" } })),
        };
        if let Some(r) = resp {
            if writeln!(out, "{r}").and_then(|_| out.flush()).is_err() {
                break;
            }
        }
    }
}

fn flag<'a>(args: &'a [String], name: &str) -> Option<&'a str> {
    args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).map(String::as_str)
}

const USAGE: &str = "usage: fitness coach summary [--weeks N] [--date YYYY-MM-DD] [--json]
       fitness coach propose <plan|settings|profile> <file.json|-> --why \"reason\"
       fitness coach log [--add \"text\" [--kind check-in|decision|note|alert]] [--limit N]
       fitness coach proposals
       fitness coach mcp
FITNESS_USER names the user; DB_FILE the database.";

pub fn cli(db_path: &str, args: &[String]) {
    let Some(user) = env::var("FITNESS_USER").ok().filter(|u| !u.is_empty()) else {
        eprintln!("FITNESS_USER is not set\n{USAGE}");
        process::exit(2);
    };
    let c = open(db_path);
    let sub = args.first().map(String::as_str).unwrap_or("");
    let a = match sub {
        "mcp" => return serve_mcp(&c, &user),
        "summary" => json!({
            "weeks": flag(args, "--weeks").and_then(|w| w.parse::<i64>().ok()),
            "date": flag(args, "--date"),
            "format": if args.iter().any(|a| a == "--json") { "json" } else { "text" },
        }),
        "propose" => {
            let (Some(target), Some(file)) = (args.get(1), args.get(2)) else {
                eprintln!("{USAGE}");
                process::exit(2);
            };
            let text = if file == "-" {
                let mut s = String::new();
                std::io::stdin().read_to_string(&mut s).map(|_| s)
            } else {
                fs::read_to_string(file)
            };
            let data: Value = match text.map_err(|e| e.to_string()).and_then(|t| serde_json::from_str(&t).map_err(|e| e.to_string())) {
                Ok(v) => v,
                Err(e) => {
                    eprintln!("cannot read {file}: {e}");
                    process::exit(1);
                }
            };
            json!({ "target": target, "data": data, "why": flag(args, "--why") })
        }
        "log" => json!({ "add": flag(args, "--add"), "kind": flag(args, "--kind"), "limit": flag(args, "--limit").and_then(|l| l.parse::<i64>().ok()) }),
        "proposals" => json!({}),
        _ => {
            eprintln!("{USAGE}");
            process::exit(2);
        }
    };
    match tool_call(&c, &user, sub, &a) {
        Ok(text) => println!("{text}"),
        Err(e) => {
            eprintln!("{e}");
            process::exit(1);
        }
    }
}
