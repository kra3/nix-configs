{
  flake.nixosModules.services-surveillance-alarm-person-photos =
    {
      config,
      pkgs,
      ...
    }:
    let
      frigateUrl = "http://${config.vars.network.containers.homeAuto.localAddress}:5000";
      emailAddress = config.vars.acme.email;

      script = pkgs.writeText "alarm-person-photos.py" ''
        import json, os, smtplib, subprocess, sys, threading, time, urllib.request, uuid
        from datetime import datetime
        from email.message import EmailMessage

        FRIGATE = "${frigateUrl}"
        EMAIL = "${emailAddress}"
        CRED = os.environ["CREDENTIALS_DIRECTORY"]
        THROTTLE_S = 60
        MAX_EMAIL_BYTES = 20 * 1024 * 1024


        def cred(name):
            with open(os.path.join(CRED, name)) as f:
                return f.read().strip()


        def log(*a):
            print(*a, file=sys.stderr, flush=True)


        def fetch(path):
            with urllib.request.urlopen(FRIGATE + path, timeout=60) as r:
                return r.read()


        def telegram(method, field, filename, data, caption):
            boundary = uuid.uuid4().hex
            parts = []
            for k, v in (("chat_id", cred("telegram_chat_id")), ("caption", caption)):
                parts.append(
                    f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
                )
            parts.append(
                f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"; filename="{filename}"\r\n\r\n'.encode()
                + data
                + b"\r\n"
            )
            body = b"".join(parts) + f"--{boundary}--\r\n".encode()
            req = urllib.request.Request(
                f"https://api.telegram.org/bot{cred('telegram_bot_token')}/{method}",
                data=body,
                headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
            )
            urllib.request.urlopen(req, timeout=120).read()


        def email(subject, attachments):
            password = cred("smtp_password")
            if not password or password == "unset":
                log("smtp_password not set, skipping email")
                return
            msg = EmailMessage()
            msg["From"] = msg["To"] = EMAIL
            msg["Subject"] = subject
            msg.set_content(subject)
            for filename, data in attachments:
                if len(data) > MAX_EMAIL_BYTES:
                    log("attachment too large for email:", filename)
                    continue
                kind, sub = ("video", "mp4") if filename.endswith(".mp4") else ("image", "jpeg")
                msg.add_attachment(data, maintype=kind, subtype=sub, filename=filename)
            with smtplib.SMTP("smtp.gmail.com", 587, timeout=60) as s:
                s.starttls()
                s.login(EMAIL, password)
                s.send_message(msg)


        def caption(item):
            when = datetime.fromtimestamp(item["start"]).strftime("%H:%M:%S")
            return f"Alarm triggered: person on {item['cam'].replace('_', ' ')} at {when}"


        def send_photos(item, photos):
            cap = caption(item)
            try:
                for i, jpg in enumerate(photos):
                    telegram("sendPhoto", "photo", f"{item['id']}-{i}.jpg", jpg, cap)
            except Exception as e:
                log("telegram photo failed:", e)
            try:
                email(cap, [(f"{item['id']}-{i}.jpg", jpg) for i, jpg in enumerate(photos)])
            except Exception as e:
                log("email photo failed:", e)


        def send_clip(item):
            cap = caption(item) + " (clip)"
            try:
                clip = fetch(f"/api/events/{item['id']}/clip.mp4")
            except Exception as e:
                log("clip fetch failed:", item["id"], e)
                return
            try:
                telegram("sendVideo", "video", f"{item['id']}.mp4", clip, cap)
            except Exception as e:
                log("telegram clip failed:", e)
            try:
                email(cap, [(f"{item['id']}.mp4", clip)])
            except Exception as e:
                log("email clip failed:", e)


        def snapshot(cam):
            return fetch(f"/api/{cam}/latest.jpg?h=1080&bbox=1")


        def spawn(fn, *args):
            threading.Thread(target=fn, args=args, daemon=True).start()


        # Events seen while the alarm is pending/triggered, held until it triggers or is disarmed.
        alarm = None
        events = {}
        last_sent = {}


        def release(item):
            item["released"] = True
            now = time.time()
            if now - last_sent.get(item["cam"], 0) < THROTTLE_S:
                item["skip"] = True
                return
            last_sent[item["cam"]] = now
            spawn(send_photos, item, list(item["photos"]))
            if item.get("ended"):
                spawn(send_clip, item)


        def on_alarm(state):
            global alarm
            prev, alarm = alarm, state
            log("alarm state:", state)
            if state == "triggered":
                for item in events.values():
                    if not item["released"]:
                        release(item)
            elif state == "pending":
                if prev != "pending":
                    events.clear()
            else:
                if events:
                    log("alarm", state, "- discarding", len(events), "held events")
                events.clear()


        def on_event(msg):
            after = msg.get("after") or {}
            if after.get("label") != "person" or alarm not in ("pending", "triggered"):
                return
            eid, cam, kind = after["id"], after["camera"], msg.get("type")
            item = events.get(eid)
            if kind == "new" and item is None:
                item = events[eid] = {
                    "id": eid, "cam": cam, "start": after.get("start_time", time.time()),
                    "photos": [], "released": False, "ended": False, "t": time.time(),
                }
            if item is None:
                return
            try:
                if kind == "new" or (kind == "update" and len(item["photos"]) < 2 and time.time() - item["t"] >= 3):
                    jpg = snapshot(cam)
                    item["photos"].append(jpg)
                    if item["released"] and not item.get("skip"):
                        spawn(send_photos, item, [jpg])
            except Exception as e:
                log("snapshot failed:", cam, e)
            if kind == "end":
                item["ended"] = True
                if item["released"] and not item.get("skip"):
                    spawn(send_clip, item)
            if alarm == "triggered" and not item["released"] and item["photos"]:
                release(item)


        def main():
            proc = subprocess.Popen(
                [
                    "${pkgs.mosquitto}/bin/mosquitto_sub", "-h", "localhost", "-p", "1883",
                    "-u", cred("mqtt_user"), "-P", cred("mqtt_password"),
                    "-t", "alarmo/state", "-t", "frigate/events", "-F", "%t %p",
                ],
                stdout=subprocess.PIPE, text=True,
            )
            for line in proc.stdout:
                topic, _, payload = line.rstrip("\n").partition(" ")
                try:
                    if topic == "alarmo/state":
                        on_alarm(payload.strip())
                    elif topic == "frigate/events":
                        on_event(json.loads(payload))
                except Exception as e:
                    log("handler error:", topic, e)
            sys.exit(proc.wait() or 1)


        if __name__ == "__main__":
            main()
      '';
    in
    {
      sops.secrets."alarm.smtp_password" = { };

      systemd.services.alarm-person-photos = {
        description = "Send person photos and clips to Telegram/email when the alarm triggers";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "container@home-auto.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 ${script}";
          DynamicUser = true;
          Restart = "always";
          RestartSec = 10;
          LoadCredential = [
            "mqtt_user:${config.sops.secrets."mqtt.user".path}"
            "mqtt_password:${config.sops.secrets."mqtt.password".path}"
            "telegram_bot_token:${config.sops.secrets."monitoring.grafana.telegram_bot_token".path}"
            "telegram_chat_id:${config.sops.secrets."monitoring.grafana.telegram_chat_id".path}"
            "smtp_password:${config.sops.secrets."alarm.smtp_password".path}"
          ];
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
        };
      };
    };
}
