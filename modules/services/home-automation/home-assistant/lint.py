import re
import sys
from pathlib import Path

import yaml

yaml.SafeLoader.add_multi_constructor("!", lambda _, tag, node: f"!{tag} {node.value}")

cfg = Path(sys.argv[1])
TV = ("media_player.lg_webos_tv_oled77c35la", "media_player.home_theater_2")
bad = []


def load(p):
    return yaml.safe_load(p.read_text())


def walk(x):
    yield x
    for v in x.values() if isinstance(x, dict) else x if isinstance(x, list) else ():
        yield from walk(v)


def seconds(d):
    if isinstance(d, (int, float)):
        return d
    if isinstance(d, dict):
        return sum(float(d.get(k) or 0) * m for k, m in (("days", 86400), ("hours", 3600), ("minutes", 60), ("seconds", 1), ("milliseconds", 0.001)))
    if isinstance(d, str) and re.fullmatch(r"[\d:.]+", d):
        return sum(float(p) * 60**i for i, p in enumerate(reversed(d.split(":"))))
    return 0


def long_wait(n):
    if not isinstance(n, dict):
        return False
    if "delay" in n:
        return seconds(n["delay"]) >= 60
    return bool({"wait_for_trigger", "wait_template"} & n.keys()) and (n.get("timeout") is None or seconds(n["timeout"]) >= 60)


def lint(path, id, item, owner_alarm=False, owner_notify=False, owner_tv=False):
    def fail(rule, detail):
        bad.append(f"{path.relative_to(cfg)}:{id}: {rule}: {detail}")

    nodes = list(walk(item))
    for n in nodes:
        if isinstance(n, str) and re.search(r"\{[{%].*automation\.\w", n, re.S):
            fail("entity-coupling", "automation entity id inside a template")
        if not isinstance(n, dict):
            continue
        if "delay" in n and seconds(n["delay"]) >= 60 and id not in {"wakeup_lighting"}:
            fail("long-delay", f"delay {n['delay']}")
        act = n.get("action") or n.get("service")
        if not isinstance(act, str):
            continue
        if (act == "alarmo.arm" or act.startswith("alarm_control_panel.alarm_")) and not owner_alarm:
            fail("alarm-owner", act)
        if act.startswith("notify.") and not owner_notify:
            fail("notify-owner", act)
        if act in ("media_player.turn_on", "media_player.turn_off", "media_player.toggle") and any(t in str(n) for t in TV) and not owner_tv:
            fail("tv-owner", act)

    triggers = item.get("triggers") or item.get("trigger") or []
    if item.get("mode") == "restart" and isinstance(triggers, list) and len(triggers) > 1:
        if any(isinstance(n, dict) and long_wait(n) for n in walk(item.get("actions") or item.get("action"))):
            fail("restart-wait", "mode: restart with several triggers and a wait/delay of 60 s or more")

    tv = item.get("trigger_variables")
    if tv:
        declared = item.get("variables") or {}
        text = " ".join(n for k in ("actions", "conditions") for n in walk(item.get(k)) if isinstance(n, str) and "{" in n)
        for name in tv:
            if name not in declared and re.search(rf"\b{re.escape(name)}\b", text):
                fail("blueprint-vars", f"trigger_variable {name} used in actions/conditions but not in variables")


for p in sorted((cfg / "automations").glob("*.yaml")):
    for a in load(p):
        lint(p, a.get("id", a.get("alias")), a, owner_alarm=p.name == "alarm.yaml", owner_tv=p.name == "tv.yaml")

p = cfg / "scripts.yaml"
for k, s in load(p).items():
    lint(p, k, s, owner_alarm=True, owner_notify=k == "notify", owner_tv=True)

for p in sorted((cfg / "packages").glob("*.yaml")):
    doc = load(p)
    for a in doc.get("automation") if isinstance(doc.get("automation"), list) else []:
        lint(p, a.get("id", a.get("alias")), a)
    for k, s in (doc.get("script") if isinstance(doc.get("script"), dict) else {}).items():
        lint(p, k, s, owner_alarm=True, owner_tv=True)

for p in sorted((cfg / "blueprints/automation/local").glob("*.yaml")):
    lint(p, p.stem, load(p))

alarm = load(cfg / "automations/alarm.yaml")
sync = next(a for a in load(cfg / "automations/modes.yaml") if a.get("id") == "automations_paused_sync")
keep = re.compile(sync["variables"]["keep_running"].strip())
for a in alarm:
    if not (a["id"].startswith("alarm_") and keep.match(a["id"])):
        bad.append(f"automations/alarm.yaml:{a['id']}: alarm-keep-running: id not alarm_-prefixed or not matched by keep_running")

print("\n".join(bad))
sys.exit(bool(bad))
