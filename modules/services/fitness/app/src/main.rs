// Fitness server: one small process, SQLite storage, per-user data keyed by the
// username an authenticating reverse proxy (Authelia via nginx) passes in a header.
use rusqlite::{params, Connection};
use serde_json::{json, Value};
use std::io::Read;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use std::{env, fs, process};
use tiny_http::{Header, Method, Request, Response, Server, StatusCode};

const INDEX: &str = include_str!("../index.html");
const MAX_BODY: u64 = 262_144;
const JSON: &str = "application/json";

fn open(path: &str) -> Connection {
    let c = Connection::open(path).unwrap_or_else(|e| {
        eprintln!("cannot open database {path}: {e}");
        process::exit(1);
    });
    c.execute_batch(
        "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;
         CREATE TABLE IF NOT EXISTS docs(
           user TEXT NOT NULL, id TEXT NOT NULL, data TEXT NOT NULL, updated INTEGER NOT NULL,
           PRIMARY KEY(user, id)) WITHOUT ROWID;",
    )
    .expect("init database");
    c
}

// Ids are a day (YYYY-MM-DD) or the single settings document.
fn valid_id(s: &str) -> bool {
    if s == "settings" {
        return true;
    }
    let b = s.as_bytes();
    b.len() == 10
        && b.iter()
            .enumerate()
            .all(|(i, c)| if i == 4 || i == 7 { *c == b'-' } else { c.is_ascii_digit() })
}

fn now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

fn put_doc(c: &Connection, user: &str, id: &str, data: &str) -> rusqlite::Result<usize> {
    c.execute(
        "INSERT INTO docs(user,id,data,updated) VALUES(?1,?2,?3,?4)
         ON CONFLICT(user,id) DO UPDATE SET data=excluded.data, updated=excluded.updated",
        params![user, id, data, now()],
    )
}

fn respond(rq: Request, code: u16, ctype: &str, body: String) {
    let h = |k: &str, v: &str| Header::from_bytes(k.as_bytes(), v.as_bytes()).unwrap();
    let r = Response::from_string(body)
        .with_status_code(StatusCode(code))
        .with_header(h("Content-Type", ctype))
        .with_header(h("Cache-Control", "no-store"))
        .with_header(h("X-Content-Type-Options", "nosniff"))
        .with_header(h("Referrer-Policy", "no-referrer"));
    let _ = rq.respond(r);
}

fn user_of(rq: &Request, header: &str, fallback: Option<&str>) -> Option<String> {
    for h in rq.headers() {
        if h.field.as_str().as_str().eq_ignore_ascii_case(header) {
            let v = h.value.as_str().trim();
            if !v.is_empty() && v.len() <= 128 {
                return Some(v.to_string());
            }
        }
    }
    fallback.map(|s| s.to_string())
}

fn handle(mut rq: Request, db: &Mutex<Connection>, header: &str, fallback: Option<&str>) {
    let url = rq.url().to_string();
    let path = url.split('?').next().unwrap_or("/").to_string();
    let method = rq.method().clone();

    if method == Method::Get && (path == "/" || path == "/index.html") {
        return respond(rq, 200, "text/html; charset=utf-8", INDEX.to_string());
    }
    if !path.starts_with("/api/log") {
        return respond(rq, 404, JSON, json!({"error": "not found"}).to_string());
    }
    let user = match user_of(&rq, header, fallback) {
        Some(u) => u,
        None => return respond(rq, 401, JSON, json!({"error": "no user"}).to_string()),
    };

    if method == Method::Get && path == "/api/log" {
        let docs: Vec<Value> = {
            let c = db.lock().unwrap();
            let mut st = c.prepare("SELECT id, data FROM docs WHERE user = ?1 ORDER BY id").unwrap();
            let rows = st
                .query_map(params![user], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
                .unwrap();
            rows.filter_map(|x| x.ok())
                .map(|(id, d)| json!({"id": id, "data": serde_json::from_str::<Value>(&d).unwrap_or(Value::Null)}))
                .collect()
        };
        return respond(rq, 200, JSON, json!({"docs": docs}).to_string());
    }

    if method == Method::Put {
        if let Some(id) = path.strip_prefix("/api/log/") {
            if !valid_id(id) {
                return respond(rq, 400, JSON, json!({"error": "bad id"}).to_string());
            }
            let id = id.to_string();
            let mut buf = Vec::new();
            if rq.as_reader().take(MAX_BODY + 1).read_to_end(&mut buf).is_err() {
                return respond(rq, 400, JSON, json!({"error": "read failed"}).to_string());
            }
            if buf.len() as u64 > MAX_BODY {
                return respond(rq, 413, JSON, json!({"error": "too large"}).to_string());
            }
            let v: Value = match serde_json::from_slice(&buf) {
                Ok(v) => v,
                Err(_) => return respond(rq, 400, JSON, json!({"error": "bad json"}).to_string()),
            };
            if !v.is_object() {
                return respond(rq, 400, JSON, json!({"error": "object expected"}).to_string());
            }
            let res = {
                let c = db.lock().unwrap();
                put_doc(&c, &user, &id, &v.to_string())
            };
            return match res {
                Ok(_) => respond(rq, 200, JSON, json!({"ok": true}).to_string()),
                Err(_) => respond(rq, 500, JSON, json!({"error": "write failed"}).to_string()),
            };
        }
    }
    respond(rq, 404, JSON, json!({"error": "not found"}).to_string())
}

// fitness import <data.json> <user>: load a {"YYYY-MM-DD": {...}} file once; skipped if the user already has data.
fn import(db_path: &str, file: &str, user: &str) {
    let c = open(db_path);
    let n: i64 = c.query_row("SELECT COUNT(*) FROM docs WHERE user = ?1", params![user], |r| r.get(0)).unwrap_or(0);
    if n > 0 {
        println!("{user} already has {n} entries, skipping import");
        return;
    }
    let text = fs::read_to_string(file).unwrap_or_else(|e| {
        eprintln!("cannot read {file}: {e}");
        process::exit(1);
    });
    let v: Value = serde_json::from_str(&text).unwrap_or_else(|e| {
        eprintln!("bad json in {file}: {e}");
        process::exit(1);
    });
    let mut count = 0;
    if let Some(map) = v.as_object() {
        for (id, d) in map {
            if valid_id(id) && d.is_object() && put_doc(&c, user, id, &d.to_string()).is_ok() {
                count += 1;
            }
        }
    }
    println!("imported {count} entries for {user}");
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let db_path = env::var("DB_FILE").unwrap_or_else(|_| "fitness.db".into());
    if args.get(1).map(String::as_str) == Some("import") {
        if args.len() != 4 {
            eprintln!("usage: fitness import <data.json> <user>");
            process::exit(2);
        }
        return import(&db_path, &args[2], &args[3]);
    }
    let host = env::var("HOST").unwrap_or_else(|_| "127.0.0.1".into());
    let port = env::var("PORT").unwrap_or_else(|_| "8787".into());
    let header = env::var("USER_HEADER").unwrap_or_else(|_| "Remote-User".into());
    // Set ANON_USER only to run without a login proxy (local testing).
    let fallback = env::var("ANON_USER").ok();
    let db = Mutex::new(open(&db_path));
    let server = Server::http(format!("{host}:{port}")).unwrap_or_else(|e| {
        eprintln!("cannot listen on {host}:{port}: {e}");
        process::exit(1);
    });
    println!("Fitness on http://{host}:{port}, database {db_path}, user header {header}");
    for rq in server.incoming_requests() {
        handle(rq, &db, &header, fallback.as_deref());
    }
}
