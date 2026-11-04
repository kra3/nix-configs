(function(){
'use strict';
var DEF = {kcal:1850, protein:110, steps:8000, sleep:7, workouts:3, rest:90};
var ARMS = [
  {k:'curl', n:'Biceps curl machine', sets:2, lo:10, hi:12, u:'kg'},
  {k:'pushdown', n:'Triceps press machine', sets:2, lo:10, hi:12, u:'kg'}
];
var CORE = {k:'crunch', n:'Abdominal crunch machine', sets:2, lo:12, hi:15, u:'kg'};
// Starting plan for anyone who has not saved their own; "Edit plan" stores a copy
// in the database (doc id "plan") and that replaces this.
var DEFAULT_PLAN = {
  A: [
    {k:'legpress', n:'Leg press', sets:3, lo:10, hi:12, u:'kg'},
    {k:'chestpress', n:'Chest press machine', sets:3, lo:8, hi:12, u:'kg'},
    {k:'row', n:'Seated row', sets:3, lo:10, hi:12, u:'kg'},
    {k:'legcurl', n:'Seated leg curl', sets:3, lo:10, hi:12, u:'kg'},
    CORE
  ].concat(ARMS),
  B: [
    {k:'legext', n:'Leg extension', sets:3, lo:10, hi:12, u:'kg'},
    {k:'pulldown', n:'Lat pulldown', sets:3, lo:10, hi:12, u:'kg'},
    {k:'shoulder', n:'Shoulder press machine', sets:3, lo:8, hi:12, u:'kg'},
    {k:'legcurl', n:'Seated leg curl', sets:3, lo:10, hi:12, u:'kg'},
    CORE
  ].concat(ARMS)
};
var PLAN = DEFAULT_PLAN;

var docs = {}, settings = Object.assign({}, DEF);
var sel = todayStr(), wsel = 'A';
var firstSnap = true;

function $(id){ return document.getElementById(id); }
function pad(n){ return n < 10 ? '0' + n : '' + n; }
function todayStr(){ var d = new Date(); return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }
function dayNum(s){ var p = s.split('-'); return Math.round(Date.UTC(+p[0], +p[1] - 1, +p[2]) / 864e5); }
function dayStr(n){ var d = new Date(n * 864e5); return d.getUTCFullYear() + '-' + pad(d.getUTCMonth() + 1) + '-' + pad(d.getUTCDate()); }
function fmtDay(s){ var p = s.split('-'); return new Date(Date.UTC(+p[0], +p[1] - 1, +p[2])).toLocaleDateString('en-GB', {day:'numeric', month:'short', timeZone:'UTC'}); }
function num(v){ if (v == null) return null; v = String(v).trim().replace(',', '.'); if (v === '') return null; var n = Number(v); return isFinite(n) ? n : null; }
function fmt(n, dec){ if (n == null || !isFinite(n)) return '—'; return Number(n).toLocaleString('en-GB', {maximumFractionDigits: dec == null ? 1 : dec, minimumFractionDigits: 0}); }
function sgn(n, dec, u){ var a = Math.abs(n); var s = a < Math.pow(10, -(dec == null ? 1 : dec)) / 2 ? '0' : (n > 0 ? '+' : '−') + fmt(a, dec); return s + (u ? ' ' + u : ''); }
function dates(){ return Object.keys(docs).filter(function(k){ return /^\d{4}-\d{2}-\d{2}$/.test(k); }).sort(); }
function val(d, k){ return docs[d] ? num(docs[d][k]) : null; }
function setStatus(id, msg, err){ var el = $(id); el.textContent = msg || ''; el.className = 'status' + (err ? ' err' : ''); }

/* ---------- saving ---------- */
// Every save lands in the outbox first, so it survives going offline or closing
// the page; flush() then sends it. The status line says which of the two happened.
function savedText(id, okMsg){ return outbox[id] ? 'Saved on this device, will sync when online' : okMsg; }
function saveDoc(id, next, stId, okMsg){
  setStatus(stId, 'Saving…');
  return queue(id, 'put', next).then(function(){ setStatus(stId, savedText(id, okMsg)); renderDerived(); });
}

function saveDay(){
  var d = sel;
  var next = Object.assign({}, docs[d] || {});
  next.date = d;
  var map = {weight:'f-weight', waist:'f-waist', kcal:'f-kcal', protein:'f-protein', steps:'f-steps', sleep:'f-sleep', bodyfat:'f-bodyfat'};
  Object.keys(map).forEach(function(k){
    var v = num($(map[k]).value);
    if (v == null) delete next[k]; else next[k] = v;
  });
  var note = $('f-note').value.trim();
  if (note) next.note = note; else delete next.note;
  docs[d] = next;
  saveDoc(d, next, 'st-day', 'Saved').then(updateDelete);
}

var delArmed = 0;
function deleteDay(){
  var b = $('del-day');
  if (!delArmed){
    b.textContent = 'Tap again to delete ' + fmtDay(sel); b.classList.add('armed');
    delArmed = setTimeout(disarmDelete, 4000);
    return;
  }
  disarmDelete();
  var d = sel;
  delete docs[d];
  fillForm(); renderWorkout(); renderDerived(); updateDelete();
  setStatus('st-day', 'Deleting…');
  queue(d, 'delete', null).then(function(){ setStatus('st-day', outbox[d] ? 'Deleted on this device, will sync when online' : 'Day deleted'); });
}
function disarmDelete(){
  clearTimeout(delArmed); delArmed = 0;
  var b = $('del-day'); b.textContent = 'Delete day'; b.classList.remove('armed');
}
function updateDelete(){ $('del-day').hidden = !docs[sel]; }

function nSets(ex, saved){ return Math.max(ex.sets, saved && saved[ex.k] ? saved[ex.k].length : 0); }
function saveWorkout(){
  var d = sel, collected = {}, any = false, sv0 = (docs[sel] && docs[sel].sets) || {};
  PLAN[wsel].forEach(function(ex){
    var arr = [];
    for (var i = 0; i < nSets(ex, sv0); i++){
      var r = num($('in-' + ex.k + '-' + i + '-r').value);
      var w = ex.u === 'kg' ? num($('in-' + ex.k + '-' + i + '-w').value) : null;
      if (r != null) arr.push([w, r]);
    }
    if (arr.length){ collected[ex.k] = arr; any = true; }
  });
  if (!any){ setStatus('st-workout', 'Enter at least one set first.', true); return; }
  // New bests against everything logged before this day.
  var prs = [];
  Object.keys(collected).forEach(function(k){
    var u = exUnit(k), prev = exSeries(k).filter(function(p){ return p.date < d; }), nb = bestSet(collected[k], u);
    if (!prev.length || !nb) return;
    var pb = Math.max.apply(null, prev.map(function(p){ return p.v; }));
    if (nb.score > pb + 1e-9){ var e = planEx(k); prs.push((e ? e.n : k) + ' ' + setText(nb, u)); }
  });
  var next = Object.assign({}, docs[d] || {});
  next.date = d;
  next.workout = wsel;
  next.sets = Object.assign({}, next.sets || {}, collected);
  docs[d] = next;
  saveDoc(d, next, 'st-workout', prs.length ? 'Workout saved. New best: ' + prs.join(', ') + '.' : 'Workout saved').then(updateDelete);
}

function saveTargets(){
  var s = {
    kcal: num($('t-kcal').value) || DEF.kcal,
    protein: num($('t-protein').value) || DEF.protein,
    steps: num($('t-steps').value) || DEF.steps,
    sleep: num($('t-sleep').value) || DEF.sleep,
    workouts: num($('t-workouts').value) || DEF.workouts,
    rest: Math.min(900, Math.max(15, num($('t-rest').value) || DEF.rest))
  };
  var h = num($('t-height').value), sw = num($('t-start').value), sx = $('t-sex').value;
  if (h) s.height = h;
  if (sx) s.sex = sx;
  if (sw) s.start_weight = sw;
  settings = Object.assign({}, DEF, s);
  saveDoc('settings', s, 'st-targets', 'Saved');
}

/* ---------- forms ---------- */
function fillForm(){
  var d = docs[sel] || {};
  ['weight','waist','kcal','protein','steps','sleep','bodyfat'].forEach(function(k){ $('f-' + k).value = d[k] != null ? d[k] : ''; });
  $('f-note').value = d.note || '';
  setStatus('st-day', '');
  disarmDelete(); updateDelete();
}
function fillTargets(){
  ['kcal','protein','steps','sleep','workouts','rest'].forEach(function(k){ $('t-' + k).value = settings[k]; });
  $('t-height').value = settings.height != null ? settings.height : '';
  $('t-start').value = settings.start_weight != null ? settings.start_weight : '';
  $('t-sex').value = settings.sex || '';
}

/* ---------- today bars ---------- */
function weekWorkouts(){
  var end = dayNum(sel), n = 0;
  dates().forEach(function(d){ var x = dayNum(d); if (x <= end && x > end - 7 && docs[d].workout) n++; });
  return n;
}
function renderBars(){
  var d = docs[sel] || {};
  $('h-today').textContent = sel === todayStr() ? 'Today' : fmtDay(sel);
  var rows = [
    {l:'Protein', v:num(d.protein), t:settings.protein, u:'g', mode:'min'},
    {l:'Calories', v:num(d.kcal), t:settings.kcal, u:'kcal', mode:'max'},
    {l:'Steps', v:num(d.steps), t:settings.steps, u:'', mode:'min'},
    {l:'Sleep', v:num(d.sleep), t:settings.sleep, u:'h', mode:'min'},
    {l:'Workouts', v:weekWorkouts(), t:settings.workouts, u:'this week', mode:'min'}
  ];
  var host = $('bars'); host.textContent = '';
  rows.forEach(function(r){
    var row = document.createElement('div'); row.className = 'bar-row';
    var nm = document.createElement('div'); nm.className = 'name'; nm.textContent = r.l;
    var tr = document.createElement('div'); tr.className = 'track';
    var fl = document.createElement('div'); fl.className = 'fill';
    var vl = document.createElement('div'); vl.className = 'val';
    if (r.v == null){
      vl.textContent = '— / ' + fmt(r.t, 1) + (r.u ? ' ' + r.u : '');
    } else {
      var pct = Math.max(0, Math.min(100, r.v / r.t * 100));
      fl.style.width = pct + '%';
      if (r.mode === 'min' && r.v >= r.t) fl.classList.add('ok');
      if (r.mode === 'max') fl.classList.add(r.v <= r.t * 1.05 ? 'ok' : 'warn');
      vl.textContent = fmt(r.v, 1) + ' / ' + fmt(r.t, 1) + (r.u ? ' ' + r.u : '');
    }
    tr.appendChild(fl); row.appendChild(nm); row.appendChild(tr); row.appendChild(vl); host.appendChild(row);
  });
}

/* ---------- charts ---------- */
function series(key){
  return dates().filter(function(d){ return val(d, key) != null; }).map(function(d){ return {d:dayNum(d), date:d, v:val(d, key)}; });
}
function niceStep(x){ var p = Math.pow(10, Math.floor(Math.log10(x))), f = x / p; return (f < 1.5 ? 1 : f < 3 ? 2 : f < 7 ? 5 : 10) * p; }
function avgSeries(pts){
  return pts.map(function(p){
    var s = 0, n = 0;
    pts.forEach(function(q){ if (q.d <= p.d && q.d > p.d - 7){ s += q.v; n++; } });
    return {d:p.d, v:s / n};
  });
}
function drawChart(hostId, roId, key, unit, emptyMsg){
  var pts = series(key);
  drawLine(hostId, roId, pts, {id: key, unit: unit, empty: emptyMsg, avg: avgSeries(pts), since: 13,
    label: unit + ' over time with 7-day average',
    text: function(i, a){ return fmtDay(pts[i].date) + ' · ' + fmt(pts[i].v, 1) + ' ' + unit + ' · 7-day avg ' + fmt(a[i].v, 1); }});
}
// pts: [{d, date, v}]. o.avg: a smoothed line drawn instead of joining the dots
// (omit to join them); o.text(i, line): the readout for point i.
function drawLine(hostId, roId, pts, o){
  var host = $(hostId), ro = $(roId), emptyMsg = o.empty, key = o.id;
  host.textContent = '';
  if (!pts.length){
    var e = document.createElement('div'); e.className = 'empty'; e.textContent = emptyMsg; host.appendChild(e);
    ro.textContent = ''; return;
  }
  var W = Math.max(host.clientWidth || 340, 240), H = 200;
  var t = dayNum(todayStr());
  var d0 = Math.min(pts[0].d, t - (o.since || 0)), d1 = Math.max(pts[pts.length - 1].d, t);
  var avg = o.avg || pts;
  var all = pts.map(function(p){ return p.v; }).concat(avg.map(function(a){ return a.v; }));
  var mn = Math.min.apply(null, all), mx = Math.max.apply(null, all);
  var rg = Math.max(mx - mn, 1), lo = mn - rg * 0.3, hi = mx + rg * 0.3;
  var m = {l:40, r:12, t:12, b:26}, iw = W - m.l - m.r, ih = H - m.t - m.b;
  function X(d){ return m.l + (d1 === d0 ? iw / 2 : (d - d0) / (d1 - d0) * iw); }
  function Y(v){ return m.t + (1 - (v - lo) / (hi - lo)) * ih; }
  var step = niceStep((hi - lo) / 3), s = '';
  var first = Math.ceil(lo / step);
  for (var i = first; i * step <= hi; i++){
    var tv = i * step, y = Y(tv).toFixed(1);
    s += '<line class="gl" x1="' + m.l + '" x2="' + (W - m.r) + '" y1="' + y + '" y2="' + y + '"/>';
    s += '<text class="tx" x="' + (m.l - 6) + '" y="' + (+y + 4) + '" text-anchor="end">' + fmt(tv, step < 1 ? 1 : 0) + '</text>';
  }
  s += '<text class="tx" x="' + m.l + '" y="' + (H - 6) + '" text-anchor="start">' + fmtDay(dayStr(d0)) + '</text>';
  s += '<text class="tx" x="' + (W - m.r) + '" y="' + (H - 6) + '" text-anchor="end">' + fmtDay(dayStr(d1)) + '</text>';
  s += '<polyline class="ln" points="' + avg.map(function(a){ return X(a.d).toFixed(1) + ',' + Y(a.v).toFixed(1); }).join(' ') + '"/>';
  pts.forEach(function(p){ s += '<circle class="dot" cx="' + X(p.d).toFixed(1) + '" cy="' + Y(p.v).toFixed(1) + '" r="3"/>'; });
  var la = avg[avg.length - 1];
  s += '<circle class="end" cx="' + X(la.d).toFixed(1) + '" cy="' + Y(la.v).toFixed(1) + '" r="5"/>';
  s += '<circle class="mk" id="mk-' + key + '" cx="-20" cy="-20" r="7"/>';
  host.innerHTML = '<svg viewBox="0 0 ' + W + ' ' + H + '" width="100%" role="img" aria-label="' + o.label + '">' + s + '</svg>';
  function text(i){ return o.text(i, avg); }
  var last = pts.length - 1;
  ro.textContent = text(last);
  var svg = host.querySelector('svg'), mk = svg.querySelector('.mk');
  function move(ev){
    var r = svg.getBoundingClientRect(), x = (ev.clientX - r.left) * (W / r.width), best = 0, bd = 1e9;
    pts.forEach(function(p, i){ var dx = Math.abs(X(p.d) - x); if (dx < bd){ bd = dx; best = i; } });
    mk.setAttribute('cx', X(pts[best].d).toFixed(1)); mk.setAttribute('cy', Y(pts[best].v).toFixed(1));
    ro.textContent = text(best);
  }
  function leave(){ mk.setAttribute('cx', -20); mk.setAttribute('cy', -20); ro.textContent = text(last); }
  svg.addEventListener('pointermove', move);
  svg.addEventListener('pointerdown', move);
  svg.addEventListener('pointerleave', leave);
}
function drawCharts(){
  drawChart('ch-weight', 'ro-weight', 'weight', 'kg', 'Log your weight to start the trend. Weigh at the same time each morning.');
  drawChart('ch-waist', 'ro-waist', 'waist', 'cm', 'Measure at navel level every two weeks and log it here.');
  drawChart('ch-bf', 'ro-bf', 'bodyfat', '%', 'Body fat from the scale fills in each morning, or log it with your weight.');
}

/* ---------- stats ---------- */
function stat(host, n, label, sub){
  var el = document.createElement('div'); el.className = 'stat';
  var a = document.createElement('div'); a.className = 'n'; a.textContent = n;
  var b = document.createElement('div'); b.className = 'lbl'; b.textContent = label;
  el.appendChild(a); el.appendChild(b);
  if (sub){ var c = document.createElement('div'); c.className = 's'; c.textContent = sub; el.appendChild(c); }
  host.appendChild(el);
}
// Relative fat mass: body fat % from height and waist alone (Woolcott & Bergman 2018).
function rfm(waist){
  var h = num(settings.height), sx = settings.sex;
  if (!h || !waist || (sx !== 'm' && sx !== 'f')) return null;
  return (sx === 'f' ? 76 : 64) - 20 * h / waist;
}
function bmi(kg){ var h = num(settings.height); return h ? 'BMI ' + fmt(kg / Math.pow(h / 100, 2), 1) : null; }
function renderStats(){
  var w = $('wstats'); w.textContent = '';
  var pts = series('weight'), pace = $('pace');
  var start = num(settings.start_weight) || (pts.length ? pts[0].v : null);
  pace.className = 'pace';
  if (!pts.length){
    stat(w, start != null ? fmt(start, 1) + ' kg' : '—', 'Start', start != null ? bmi(start) : null);
    stat(w, '—', '7-day avg');
    stat(w, '—', 'Change');
    pace.textContent = 'Target pace: lose 0.25 to 0.5 kg per week.';
  } else {
    var av = avgSeries(pts), cur = av[av.length - 1].v;
    stat(w, fmt(start, 1) + ' kg', 'Start');
    stat(w, fmt(cur, 1) + ' kg', '7-day avg', bmi(cur));
    stat(w, sgn(cur - start, 1, 'kg'), 'Change');
    var lastD = pts[pts.length - 1].d;
    var win = pts.filter(function(p){ return p.d >= lastD - 27; });
    if (win.length >= 3 && win[win.length - 1].d - win[0].d >= 6){
      var n = win.length, sx = 0, sy = 0, sxy = 0, sxx = 0, x0 = win[0].d;
      win.forEach(function(p){ var x = p.d - x0; sx += x; sy += p.v; sxy += x * p.v; sxx += x * x; });
      var slope = (n * sxy - sx * sy) / (n * sxx - sx * sx), wk = slope * 7, note;
      if (wk <= -0.15 && wk >= -0.6){ note = 'on the target pace'; pace.classList.add('ok'); }
      else if (wk < -0.6){ note = 'faster than target, so eat a little more'; pace.classList.add('warn'); }
      else if (wk < 0.2){ note = 'flat, which is normal early in a recomp; check your waist'; }
      else { note = 'trending up'; pace.classList.add('warn'); }
      pace.textContent = 'Pace: ' + sgn(wk, 2, 'kg/week') + ', ' + note + '. Target is −0.25 to −0.5.';
    } else {
      pace.textContent = 'Pace appears after a week of weigh-ins. Target: lose 0.25 to 0.5 kg per week.';
    }
  }
  var c = $('cstats'); c.textContent = '';
  var ws = series('waist');
  if (!ws.length){
    stat(c, '—', 'First'); stat(c, '—', 'Latest'); stat(c, '—', 'Change');
  } else {
    var f = ws[0].v, l = ws[ws.length - 1].v;
    stat(c, fmt(f, 1) + ' cm', 'First', fmtDay(ws[0].date));
    stat(c, fmt(l, 1) + ' cm', 'Latest', fmtDay(ws[ws.length - 1].date));
    stat(c, sgn(l - f, 1, 'cm'), 'Change');
  }
  // Body fat: the scale's reading (7-day average) and the waist-based estimate side by side.
  var b = $('bstats'); b.textContent = '';
  var bs = series('bodyfat');
  if (bs.length){
    var bav = avgSeries(bs), bcur = bav[bav.length - 1].v;
    stat(b, fmt(bcur, 1) + '%', 'Scale, 7-day avg', fmtDay(bs[bs.length - 1].date));
    stat(b, sgn(bcur - bs[0].v, 1, 'points'), 'Change', 'since ' + fmtDay(bs[0].date));
    var wNow = pts.length ? avgSeries(pts).at(-1).v : null;
    if (wNow != null){
      var lean = wNow * (1 - bcur / 100);
      stat(b, fmt(lean, 1) + ' kg', 'Lean mass', 'fat ' + fmt(wNow - lean, 1) + ' kg');
    }
  } else {
    stat(b, '—', 'Scale, 7-day avg'); stat(b, '—', 'Change');
  }
  var est = ws.length ? rfm(ws[ws.length - 1].v) : null;
  if (est != null){
    var est0 = rfm(ws[0].v);
    stat(b, fmt(est, 1) + '%', 'From waist, est.', ws.length > 1 ? sgn(est - est0, 1) + ' points since ' + fmtDay(ws[0].date) : 'waist and height');
  } else {
    stat(b, '—', 'From waist, est.', ws.length ? 'set height and sex in Daily targets' : 'log your waist');
  }
}

/* ---------- habits ---------- */
function renderHabits(){
  var host = $('habits'); host.textContent = '';
  var t = dayNum(todayStr()), days = [], i;
  for (i = 0; i < 14; i++) days.push(dayStr(t - 13 + i));
  host.appendChild(document.createElement('div'));
  days.forEach(function(ds){
    var h = document.createElement('div'); h.className = 'dh';
    h.textContent = 'SMTWTFS'.charAt(new Date(dayNum(ds) * 864e5).getUTCDay()); host.appendChild(h);
  });
  var defs = [
    {l:'Workout', f:function(d){ return d && d.workout ? 'on' : null; }},
    {l:'Protein', f:function(d){ var v = d ? num(d.protein) : null; return v == null ? null : (v >= settings.protein ? 'on' : 'none'); }},
    {l:'Calories', f:function(d){ var v = d ? num(d.kcal) : null; return v == null ? null : (v <= settings.kcal * 1.05 ? 'on' : 'miss'); }},
    {l:'Steps', f:function(d){ var v = d ? num(d.steps) : null; return v == null ? null : (v >= settings.steps ? 'on' : 'none'); }},
    {l:'Sleep', f:function(d){ var v = d ? num(d.sleep) : null; return v == null ? null : (v >= settings.sleep ? 'on' : 'none'); }}
  ];
  var counts = {};
  defs.forEach(function(df){
    var rl = document.createElement('div'); rl.className = 'rl'; rl.textContent = df.l; host.appendChild(rl);
    days.forEach(function(ds, idx){
      var r = df.f(docs[ds]), c = document.createElement('div');
      c.className = 'cell' + (r === 'on' ? ' on' : r === 'miss' ? ' miss' : '');
      c.setAttribute('role', 'img');
      c.setAttribute('aria-label', fmtDay(ds) + ', ' + df.l + ': ' + (r === 'on' ? 'met' : r === 'miss' ? 'over target' : r === 'none' ? 'below target' : 'not logged'));
      if (idx >= 7 && r === 'on') counts[df.l] = (counts[df.l] || 0) + 1;
      host.appendChild(c);
    });
  });
  $('hsum').textContent = 'Last 7 days: ' + (counts.Workout || 0) + ' workouts, protein met on ' + (counts.Protein || 0) + ' days, steps on ' + (counts.Steps || 0) + ' days, sleep on ' + (counts.Sleep || 0) + ' days. Green means target met, amber means calories over target.';
}

/* ---------- workout sheet ---------- */
function suggestWorkout(d){
  if (docs[d] && docs[d].workout) return docs[d].workout;
  var prev = dates().filter(function(x){ return x < d && docs[x].workout; });
  if (!prev.length) return 'A';
  return docs[prev[prev.length - 1]].workout === 'A' ? 'B' : 'A';
}
function lastFor(k){
  var ds = dates().filter(function(x){ return x < sel && docs[x].sets && docs[x].sets[k]; });
  if (!ds.length) return null;
  var d = ds[ds.length - 1];
  return {date:d, sets:docs[d].sets[k]};
}
function lastText(ex, last){
  var parts = last.sets.map(function(s){ return ex.u === 'kg' ? fmt(s[0], 2) + '×' + fmt(s[1], 0) : fmt(s[1], 0); });
  var suffix = ex.u === 'kg' ? ' (kg × reps)' : ex.u === 'sec' ? ' sec' : ' reps';
  return 'Last, ' + fmtDay(last.date) + ': ' + parts.join(' · ') + suffix + '.';
}
function suggestText(ex, sg){
  var first = sg.sets[0], what = ex.u === 'kg' ? fmt(first[0], 2) + ' kg × ' + first[1] : first[1] + (ex.u === 'sec' ? ' sec' : ' reps');
  if (sg.deload) return 'No new best in 3 sessions. Today: a lighter session, ' + what + ', then build back up from there.';
  if (ex.u !== 'kg' && stalled(ex.k, sel)) return 'No new best in 3 sessions. Try a harder variation or a slower tempo, or rest a day longer before it.';
  if (sg.up) return 'Today: ' + what + (ex.u === 'kg' ? '. Every set hit ' + ex.hi + ', so one step heavier.' : '. Top of the range last time; make it harder (slower, or a harder variation).');
  return 'Today: ' + (ex.u === 'kg' ? 'same weight, one more rep per set (' + what + ' first).' : 'one more per set (' + what + ' first).');
}
// Tap the set number to log the set as suggested (or as last time), then rest.
function logAsSuggested(ex, i, sg){
  var s0 = sg ? sg.sets[i] : null, r = $('in-' + ex.k + '-' + i + '-r'), w = $('in-' + ex.k + '-' + i + '-w');
  if (!s0){ r.focus(); return; }
  if (w && w.value === '' && s0[0] != null) w.value = s0[0];
  if (r.value === '') r.value = s0[1];
  restStart();
}
function mkInput(id, ph, label){
  var el = document.createElement('input');
  el.type = 'number'; el.inputMode = 'decimal'; el.step = 'any'; el.min = '0';
  el.id = id; el.placeholder = ph || ''; el.setAttribute('aria-label', label);
  return el;
}
function renderWorkout(){
  var tabs = $('tabs'); tabs.textContent = '';
  var next = suggestWorkout(sel), logged = docs[sel] && docs[sel].workout;
  ['A','B'].forEach(function(k){
    var b = document.createElement('button'); b.type = 'button'; b.className = 'tab';
    b.setAttribute('role', 'tab'); b.setAttribute('aria-selected', k === wsel ? 'true' : 'false');
    b.textContent = 'Workout ' + k;
    if (k === next && !logged){ var s = document.createElement('span'); s.className = 'nx'; s.textContent = 'next up'; b.appendChild(s); }
    b.addEventListener('click', function(){ if (draft) readEditor(); wsel = k; setStatus('st-workout', ''); renderWorkout(); });
    tabs.appendChild(b);
  });
  var editing = !!draft;
  $('exlist').hidden = editing; $('planed').hidden = !editing;
  $('save-workout').hidden = editing; $('edit-plan').hidden = editing;
  if (editing){ renderEditor(); return; }
  $('planed').textContent = '';
  var host = $('exlist'); host.textContent = '';
  var saved = (docs[sel] && docs[sel].sets) || {};
  PLAN[wsel].forEach(function(ex){
    var box = document.createElement('div'); box.className = 'ex';
    var head = document.createElement('div'); head.className = 'ex-head';
    var nm = document.createElement('button'); nm.type = 'button'; nm.className = 'nm linkish'; nm.textContent = ex.n;
    nm.setAttribute('aria-label', ex.n + ': show progress');
    nm.addEventListener('click', function(){ showProgress(ex.k); });
    var tg = document.createElement('span'); tg.className = 'tg';
    tg.textContent = ex.sets + ' sets · ' + (ex.u === 'sec' ? ex.lo + '–' + ex.hi + ' sec' : ex.lo + '–' + ex.hi + ' reps');
    head.appendChild(nm); head.appendChild(tg); box.appendChild(head);
    var last = lastFor(ex.k);
    var sg = suggestSets(ex, last);
    if (last){ var h = document.createElement('p'); h.className = 'hint'; h.textContent = lastText(ex, last); box.appendChild(h); }
    if (sg){ var h2 = document.createElement('p'); h2.className = 'hint sg'; h2.textContent = suggestText(ex, sg); box.appendChild(h2); }
    var sets = document.createElement('div'); sets.className = 'sets';
    for (var i = 0; i < nSets(ex, saved); i++){
      var row = document.createElement('div'); row.className = 'set';
      var ls = sg ? sg.sets[i] : null, sv = saved[ex.k] && saved[ex.k][i] ? saved[ex.k][i] : null;
      var no = document.createElement('button'); no.type = 'button'; no.className = 'no'; no.textContent = (i + 1);
      no.setAttribute('aria-label', 'Set ' + (i + 1) + (ls ? ': log as ' + (ex.u === 'kg' ? fmt(ls[0], 2) + ' kg × ' + ls[1] : ls[1]) + ' and start rest' : ': enter it'));
      no.addEventListener('click', (function(i_){ return function(){ logAsSuggested(ex, i_, sg); }; })(i));
      row.appendChild(no);
      if (ex.u === 'kg'){
        var w = mkInput('in-' + ex.k + '-' + i + '-w', ls ? fmt(ls[0], 2) : 'kg', ex.n + ' set ' + (i + 1) + ' weight in kg');
        if (sv && sv[0] != null) w.value = sv[0];
        var x = document.createElement('span'); x.className = 'x'; x.textContent = '×';
        var r = mkInput('in-' + ex.k + '-' + i + '-r', ls ? fmt(ls[1], 0) : 'reps', ex.n + ' set ' + (i + 1) + ' reps');
        if (sv) r.value = sv[1];
        r.addEventListener('change', onRepsEntered);
        row.appendChild(w); row.appendChild(x); row.appendChild(r);
      } else {
        var r2 = mkInput('in-' + ex.k + '-' + i + '-r', ls ? fmt(ls[1], 0) : (ex.u === 'sec' ? 'sec' : 'reps'), ex.n + ' set ' + (i + 1) + (ex.u === 'sec' ? ' seconds' : ' reps'));
        if (sv) r2.value = sv[1];
        r2.addEventListener('change', onRepsEntered);
        row.appendChild(r2);
      }
      sets.appendChild(row);
    }
    box.appendChild(sets); host.appendChild(box);
  });
}

/* ---------- plan editor ---------- */
var draft = null;   // {A: [...], B: [...]} while editing, else null
function slug(s){ return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 32) || 'exercise'; }
function keyFor(name, list){
  // Reuse the key of an exercise with the same name, so history carries over
  // (a leg curl in both A and B shares its log).
  var all = draft.A.concat(draft.B, DEFAULT_PLAN.A, DEFAULT_PLAN.B);
  for (var i = 0; i < all.length; i++) if (all[i].n.trim().toLowerCase() === name.trim().toLowerCase() && all[i].k) return all[i].k;
  var base = slug(name), k = base, n = 2;
  while (list.some(function(e){ return e.k === k; })) k = base.slice(0, 29) + '-' + (n++);
  return k;
}
function startEdit(){
  draft = JSON.parse(JSON.stringify({A: PLAN.A, B: PLAN.B}));
  setStatus('st-workout', ''); renderWorkout();
}
function stopEdit(){ draft = null; renderWorkout(); }
function readEditor(){
  var list = draft[wsel];
  list.forEach(function(e, i){
    var g = function(f){ return $('pe-' + i + '-' + f); };
    if (!g('n')) return;
    e.n = g('n').value;
    e.sets = Math.round(num(g('sets').value) || 0);
    e.lo = Math.round(num(g('lo').value) || 0);
    e.hi = Math.round(num(g('hi').value) || 0);
    e.u = g('u').value;
    var inc = num(g('inc').value);
    if (inc == null) delete e.inc; else e.inc = inc;
  });
}
function planProblem(){
  var bad = null;
  ['A', 'B'].forEach(function(w){
    draft[w].forEach(function(e, i){
      if (bad) return;
      var at = 'Workout ' + w + ', row ' + (i + 1) + ': ';
      if (!e.n.trim()) bad = at + 'give it a name.';
      else if (!(e.sets >= 1 && e.sets <= 10)) bad = at + 'sets must be 1 to 10.';
      else if (!(e.lo >= 1 && e.hi >= e.lo && e.hi <= 600)) bad = at + 'the range must run from low to high, up to 600.';
      else if (e.inc != null && !(e.inc > 0 && e.inc <= 50)) bad = at + 'the weight step must be above 0 and at most 50 kg.';
    });
  });
  return bad;
}
function savePlan(){
  readEditor();
  var bad = planProblem();
  if (bad){ setStatus('st-plan', bad, true); return; }
  ['A', 'B'].forEach(function(w){ draft[w].forEach(function(e){ e.n = e.n.trim(); if (!e.k) e.k = keyFor(e.n, draft[w]); }); });
  var next = {A: draft.A, B: draft.B};
  PLAN = next; draft = null;
  setStatus('st-workout', 'Saving plan…');
  renderWorkout();
  queue('plan', 'put', next).then(function(){ setStatus('st-workout', savedText('plan', 'Plan saved')); });
}
function renderEditor(){
  var host = $('planed'); host.textContent = '';
  var list = draft[wsel];
  var hint = document.createElement('p'); hint.className = 'hint';
  hint.textContent = 'Workout ' + wsel + '. Renaming keeps an exercise\'s history; removing one hides it from the sheet but keeps what you logged. The last box is the weight step added once every set reaches the top of the range (blank means ' + DEF_INC + ' kg).';
  host.appendChild(hint);
  list.forEach(function(e, i){
    var row = document.createElement('div'); row.className = 'pe';
    function field(f, label, v, attrs){
      var el = document.createElement('input');
      el.id = 'pe-' + i + '-' + f; el.value = v; el.setAttribute('aria-label', label);
      Object.keys(attrs).forEach(function(a){ el.setAttribute(a, attrs[a]); });
      el.className = 'pe-' + f;
      return el;
    }
    row.appendChild(field('n', 'Exercise ' + (i + 1) + ' name', e.n, {type: 'text', maxlength: '60', placeholder: 'Exercise name'}));
    var nums = document.createElement('div'); nums.className = 'pe-nums';
    nums.appendChild(field('sets', 'Sets', e.sets, {type: 'number', inputmode: 'numeric', min: '1', max: '10'}));
    var sx = document.createElement('span'); sx.className = 'x'; sx.textContent = '×'; nums.appendChild(sx);
    nums.appendChild(field('lo', 'Range low', e.lo, {type: 'number', inputmode: 'numeric', min: '1'}));
    var dash = document.createElement('span'); dash.className = 'x'; dash.textContent = '–'; nums.appendChild(dash);
    nums.appendChild(field('hi', 'Range high', e.hi, {type: 'number', inputmode: 'numeric', min: '1'}));
    var u = document.createElement('select'); u.id = 'pe-' + i + '-u'; u.setAttribute('aria-label', 'Unit');
    [['kg', 'kg'], ['reps', 'reps'], ['sec', 'sec']].forEach(function(o){
      var op = document.createElement('option'); op.value = o[0]; op.textContent = o[1]; if (e.u === o[0]) op.selected = true; u.appendChild(op);
    });
    nums.appendChild(u);
    var inc = field('inc', 'Weight step in kg', e.inc != null ? e.inc : '', {type: 'number', inputmode: 'decimal', min: '0', step: 'any', placeholder: '+' + DEF_INC + ' kg', title: 'How much to add when every set reaches the top of the range'});
    nums.appendChild(inc);
    row.appendChild(nums);
    var btns = document.createElement('div'); btns.className = 'pe-btns';
    [['↑', 'Move up', -1], ['↓', 'Move down', 1], ['✕', 'Remove', 0]].forEach(function(b){
      var el = document.createElement('button'); el.type = 'button'; el.className = 'tab'; el.textContent = b[0];
      el.setAttribute('aria-label', b[1] + ' ' + (e.n || 'exercise'));
      if ((b[2] === -1 && i === 0) || (b[2] === 1 && i === list.length - 1)) el.disabled = true;
      el.addEventListener('click', function(){
        readEditor();
        if (b[2] === 0) list.splice(i, 1);
        else { var t = list[i]; list[i] = list[i + b[2]]; list[i + b[2]] = t; }
        renderEditor();
      });
      btns.appendChild(el);
    });
    row.appendChild(btns);
    host.appendChild(row);
  });
  var acts = document.createElement('div'); acts.className = 'actions';
  function btn(text, cls, fn){ var b = document.createElement('button'); b.type = 'button'; b.className = cls; b.textContent = text; b.addEventListener('click', fn); acts.appendChild(b); return b; }
  btn('+ Add exercise', 'btn ghost', function(){
    readEditor();
    if (list.length >= 15){ setStatus('st-plan', 'Up to 15 exercises per workout.', true); return; }
    list.push({k: '', n: '', sets: 3, lo: 10, hi: 12, u: 'kg'}); renderEditor();
    var el = $('pe-' + (list.length - 1) + '-n'); if (el) el.focus();
  });
  btn('Save plan', 'btn', savePlan);
  btn('Cancel', 'btn ghost', stopEdit);
  btn('Reset to starting plan', 'btn ghost', function(){ draft = JSON.parse(JSON.stringify(DEFAULT_PLAN)); renderEditor(); setStatus('st-plan', 'Starting plan loaded. Save to keep it.'); });
  var st = document.createElement('span'); st.className = 'status'; st.id = 'st-plan'; st.setAttribute('role', 'status'); st.setAttribute('aria-live', 'polite');
  acts.appendChild(st);
  host.appendChild(acts);
}

/* ---------- strength: per-exercise scores, records, suggestions ---------- */
var DEF_INC = 2.5, KCAL_PER_KG = 7700;
// Estimated one-rep max (Epley). Comparable across rep counts, so a heavier set
// of 8 and a lighter set of 12 can be ranked.
function e1rm(w, r){ return w > 0 && r > 0 ? w * (1 + r / 30) : null; }
function planEx(k){
  var all = PLAN.A.concat(PLAN.B, DEFAULT_PLAN.A, DEFAULT_PLAN.B);
  for (var i = 0; i < all.length; i++) if (all[i].k === k) return all[i];
  return null;
}
function exUnit(k){ var e = planEx(k); return e ? e.u : 'kg'; }
// The best set of a session: by e1RM for weighted work, by reps or seconds otherwise.
function bestSet(sets, u){
  var best = null;
  (sets || []).forEach(function(st){
    var w = num(st[0]), r = num(st[1]), score = u === 'kg' ? e1rm(w, r) : r;
    if (score != null && (!best || score > best.score)) best = {score: score, w: w, r: r};
  });
  return best;
}
// [{d, date, v, best}] for every logged session of exercise k, on or before `upto`.
function exSeries(k, upto){
  var u = exUnit(k);
  return dates().filter(function(x){ return (!upto || x <= upto) && docs[x].sets && docs[x].sets[k]; }).map(function(x){
    var b = bestSet(docs[x].sets[k], u);
    return b ? {d: dayNum(x), date: x, v: b.score, best: b} : null;
  }).filter(Boolean);
}
function setText(b, u){ return u === 'kg' ? fmt(b.w, 2) + ' kg × ' + fmt(b.r, 0) : fmt(b.r, 0) + (u === 'sec' ? ' sec' : ' reps'); }
// Best score per exercise over (from, to], as {key: score}.
function bestIn(from, to){
  var out = {};
  dates().forEach(function(x){
    var n = dayNum(x);
    if (n <= from || n > to || !docs[x].sets) return;
    Object.keys(docs[x].sets).forEach(function(k){
      var b = bestSet(docs[x].sets[k], exUnit(k));
      if (b && (out[k] == null || b.score > out[k])) out[k] = b.score;
    });
  });
  return out;
}
// Mean % change of each exercise's best over the last 14 days against the 14 before.
function strengthChange(end){
  var now = bestIn(end - 14, end), before = bestIn(end - 28, end - 14), ch = [];
  Object.keys(now).forEach(function(k){ if (before[k]) ch.push((now[k] - before[k]) / before[k] * 100); });
  if (!ch.length) return null;
  return {pct: ch.reduce(function(a, b){ return a + b; }, 0) / ch.length, n: ch.length};
}
// Stalled: at least 4 sessions, and the last 3 all came within 5% of the earlier
// best without beating it. A lighter (deload) session below 95% resets the count.
function stalled(k, upto){
  var pts = exSeries(k).filter(function(p){ return !upto || p.date < upto; });
  if (pts.length < 4) return false;
  var prev = Math.max.apply(null, pts.slice(0, -3).map(function(p){ return p.v; }));
  return pts.slice(-3).every(function(p){ return p.v <= prev + 1e-9 && p.v >= prev * 0.95; });
}
function roundTo(x, step){ return Math.round(x / step) * step; }
// Suggested [kg, reps] per set for today, from the last session: once every set
// reached the top of the range, add one weight step and start again at the bottom;
// otherwise keep each set's weight and go for one more rep.
function suggestSets(ex, last){
  if (!last || !last.sets.length) return null;
  var n = nSets(ex, null), top = last.sets.length >= ex.sets && last.sets.every(function(st){ return num(st[1]) >= ex.hi; });
  var heaviest = Math.max.apply(null, last.sets.map(function(st){ return num(st[0]) || 0; })) || null;
  var out = [];
  // Stuck for three sessions: one lighter session (about 10% off, top of the range),
  // after which the usual progression builds back up.
  if (ex.u === 'kg' && heaviest && stalled(ex.k, sel)){
    var dl = Math.max(0, roundTo(heaviest * 0.9, num(ex.inc) || DEF_INC));
    for (var j = 0; j < n; j++) out.push([dl, ex.hi]);
    return {sets: out, deload: true};
  }
  for (var i = 0; i < n; i++){
    var ls = last.sets[Math.min(i, last.sets.length - 1)], w = num(ls[0]), r = num(ls[1]) || ex.lo;
    if (ex.u === 'kg'){
      if (top && heaviest) out.push([Math.round((heaviest + (num(ex.inc) || DEF_INC)) * 100) / 100, ex.lo]);
      else out.push([w, Math.min(ex.hi, Math.max(ex.lo, r + 1))]);
    } else {
      out.push([null, top ? ex.hi : Math.min(ex.hi, r + 1)]);
    }
  }
  return {sets: out, up: top};
}

/* ---------- exercise progress card ---------- */
var pxSel = null;
function exerciseKeys(){
  var seen = {}, out = [];
  PLAN.A.concat(PLAN.B).forEach(function(e){ if (!seen[e.k]){ seen[e.k] = 1; out.push({k: e.k, n: e.n}); } });
  dates().forEach(function(x){
    Object.keys(docs[x].sets || {}).forEach(function(k){ if (!seen[k]){ seen[k] = 1; var e = planEx(k); out.push({k: k, n: e ? e.n : k}); } });
  });
  return out;
}
function renderProgress(){
  var sel_ = $('px-sel'), keys = exerciseKeys();
  if (!keys.length){ $('px-card').hidden = true; return; }
  $('px-card').hidden = false;
  if (!pxSel || !keys.some(function(e){ return e.k === pxSel; })){
    // Default to the exercise logged most recently.
    var ds = dates().filter(function(x){ return docs[x].sets; });
    var lastK = ds.length ? Object.keys(docs[ds[ds.length - 1]].sets)[0] : null;
    pxSel = lastK && keys.some(function(e){ return e.k === lastK; }) ? lastK : keys[0].k;
  }
  sel_.textContent = '';
  keys.forEach(function(e){ var o = document.createElement('option'); o.value = e.k; o.textContent = e.n; if (e.k === pxSel) o.selected = true; sel_.appendChild(o); });
  var u = exUnit(pxSel), pts = exSeries(pxSel), st = $('px-stats');
  st.textContent = '';
  var scoreName = u === 'kg' ? 'est. 1-rep max' : (u === 'sec' ? 'seconds' : 'reps');
  if (!pts.length){
    stat(st, '—', 'Best set'); stat(st, '—', 'Heaviest'); stat(st, '—', '4 weeks');
  } else {
    var best = pts.reduce(function(a, b){ return b.v > a.v ? b : a; });
    stat(st, setText(best.best, u), 'Best set', fmtDay(best.date) + (u === 'kg' ? ' · ' + fmt(best.v, 1) + ' kg 1RM' : ''));
    if (u === 'kg'){
      var heavy = null;
      dates().forEach(function(x){
        ((docs[x].sets || {})[pxSel] || []).forEach(function(s2){ var w = num(s2[0]); if (w != null && (!heavy || w > heavy.w || (w === heavy.w && num(s2[1]) > heavy.r))) heavy = {w: w, r: num(s2[1]), date: x}; });
      });
      stat(st, heavy ? setText(heavy, u) : '—', 'Heaviest', heavy ? fmtDay(heavy.date) : null);
    } else {
      stat(st, String(pts.length), 'Sessions');
    }
    var lastP = pts[pts.length - 1], ago = pts.filter(function(p){ return p.d <= lastP.d - 28; });
    var ref = ago.length ? ago[ago.length - 1] : null;
    stat(st, ref ? sgn((lastP.v - ref.v) / ref.v * 100, 0) + '%' : '—', '4 weeks', ref ? 'since ' + fmtDay(ref.date) : 'needs a month of sessions');
  }
  drawLine('ch-px', 'ro-px', pts, {id: 'px', empty: 'Log this exercise in a workout to see its trend.',
    label: 'Best set per session, as ' + scoreName,
    text: function(i){ return fmtDay(pts[i].date) + ' · ' + setText(pts[i].best, u) + (u === 'kg' ? ' · ' + fmt(pts[i].v, 1) + ' kg 1RM' : ''); }});
}
function showProgress(k){
  pxSel = k; renderProgress();
  var c = $('px-card'); if (c.scrollIntoView) c.scrollIntoView({behavior: 'smooth', block: 'start'});
}

/* ---------- weekly check-in and calorie estimate ---------- */
// Least-squares weight slope (kg/day) over weigh-ins in (end - days, end].
function weightSlope(end, days, minPts, minSpan){
  var win = series('weight').filter(function(p){ return p.d > end - days && p.d <= end; });
  if (win.length < minPts || win[win.length - 1].d - win[0].d < minSpan) return null;
  var n = win.length, sx = 0, sy = 0, sxy = 0, sxx = 0, x0 = win[0].d;
  win.forEach(function(p){ var x = p.d - x0; sx += x; sy += p.v; sxy += x * p.v; sxx += x * x; });
  return (n * sxy - sx * sy) / (n * sxx - sx * sx);
}
function windowStats(from, to){
  var o = {w: [], kcal: [], steps: [], sleep: [], bf: [], workouts: 0, protein: 0, waist: null};
  dates().forEach(function(x){
    var n = dayNum(x), d = docs[x];
    if (n <= from || n > to) return;
    ['kcal', 'steps', 'sleep'].forEach(function(k){ var v = num(d[k]); if (v != null) o[k].push(v); });
    var w = num(d.weight); if (w != null) o.w.push(w);
    var f = num(d.bodyfat); if (f != null) o.bf.push(f);
    if (num(d.waist) != null) o.waist = num(d.waist);
    if (d.workout) o.workouts++;
    if (num(d.protein) != null && num(d.protein) >= settings.protein) o.protein++;
  });
  function mean(a){ return a.length ? a.reduce(function(x, y){ return x + y; }, 0) / a.length : null; }
  return {weight: mean(o.w), bodyfat: mean(o.bf), kcal: mean(o.kcal), steps: mean(o.steps), sleep: mean(o.sleep), workouts: o.workouts, protein: o.protein, waist: o.waist};
}
// Maintenance estimate: average logged intake minus the energy in the weight
// change over the last 28 days. Needs 14 days of calories and 8 weigh-ins.
function calorieEstimate(end){
  var kc = [];
  dates().forEach(function(x){ var n = dayNum(x), v = num(docs[x].kcal); if (n > end - 28 && n <= end && v != null) kc.push(v); });
  var slope = weightSlope(end, 28, 8, 14);
  if (kc.length < 14 || slope == null) return {need: true, days: kc.length};
  var avg = kc.reduce(function(a, b){ return a + b; }, 0) / kc.length;
  var tdee = avg - slope * KCAL_PER_KG;
  // Aim at the middle of the -0.25 to -0.5 kg/week band, never below 1200.
  var target = Math.max(1200, Math.round((tdee - 0.375 * KCAL_PER_KG / 7) / 50) * 50);
  return {tdee: Math.round(tdee / 10) * 10, target: target, days: kc.length, wk: slope * 7, avg: avg};
}
function renderWeek(){
  var end = dayNum(sel), a = windowStats(end - 7, end), b = windowStats(end - 14, end - 7);
  var host = $('wk-table'); host.textContent = '';
  var rows = [
    ['Weight, avg', a.weight, b.weight, 'kg', 1],
    ['Waist, latest', a.waist, b.waist, 'cm', 1],
    ['Body fat, avg', a.bodyfat, b.bodyfat, '%', 1],
    ['Workouts', a.workouts, b.workouts, '', 0],
    ['Protein target days', a.protein, b.protein, '', 0],
    ['Calories, avg', a.kcal, b.kcal, 'kcal', 0],
    ['Steps, avg', a.steps, b.steps, '', 0],
    ['Sleep, avg', a.sleep, b.sleep, 'h', 1]
  ];
  var hd = document.createElement('div'); hd.className = 'wk-row wk-h';
  ['', 'This week', 'Week before', 'Change'].forEach(function(t){ var c = document.createElement('span'); c.textContent = t; hd.appendChild(c); });
  host.appendChild(hd);
  rows.forEach(function(r){
    var row = document.createElement('div'); row.className = 'wk-row';
    var cells = [r[0], r[1] != null ? fmt(r[1], r[4]) + (r[3] ? ' ' + r[3] : '') : '—', r[2] != null ? fmt(r[2], r[4]) : '—',
                 r[1] != null && r[2] != null ? sgn(r[1] - r[2], r[4]) : ''];
    cells.forEach(function(t){ var c = document.createElement('span'); c.textContent = t; row.appendChild(c); });
    host.appendChild(row);
  });
  // Verdict from the 4-week trends: weight pace, waist, lifts.
  var slope = weightSlope(end, 28, 3, 6), wk = slope == null ? null : slope * 7;
  var ws = series('waist').filter(function(p){ return p.d > end - 28 && p.d <= end; });
  var waist = ws.length >= 2 && ws[ws.length - 1].d - ws[0].d >= 7 ? ws[ws.length - 1].v - ws[0].v : null;
  var str = strengthChange(end);
  var W = wk == null ? null : wk < -0.15 ? 'down' : wk > 0.2 ? 'up' : 'flat';
  var C = waist == null ? null : waist <= -0.5 ? 'down' : waist >= 0.5 ? 'up' : 'flat';
  var S = str == null ? null : str.pct >= 2 ? 'up' : str.pct <= -3 ? 'down' : 'flat';
  var facts = [];
  if (wk != null) facts.push('weight ' + sgn(wk, 2, 'kg/week'));
  if (waist != null) facts.push('waist ' + sgn(waist, 1, 'cm') + ' in 4 weeks');
  if (str) facts.push('lifts ' + sgn(str.pct, 1) + '%' +' (' + str.n + (str.n === 1 ? ' exercise' : ' exercises') + ', last 2 weeks vs the 2 before)');
  var v, cls = '';
  if (W == null && S == null) v = 'Not enough data yet. A week of weigh-ins and a month of workouts give the first read.';
  else if (S === 'down' && wk != null && wk < -0.6){ v = 'Weight is dropping fast and lifts are slipping. Eat a little more and keep protein high.'; cls = 'warn'; }
  else if (S === 'down'){ v = 'Lifts are slipping. Check sleep, protein, and that you are not eating too little.'; cls = 'warn'; }
  else if (W === 'up' && C === 'up'){ v = 'Weight and waist are both rising. Trim calories by about 150 a day.'; cls = 'warn'; }
  else if (W !== 'up' && S !== 'down' && C === 'down'){ v = 'Recomp is working: waist is down and strength is holding or rising.'; cls = 'ok'; }
  else if (W === 'down' && (S === 'up' || S === 'flat')){ v = 'Losing weight while keeping your strength. That is the goal.'; cls = 'ok'; }
  else if (W === 'flat' && S === 'up'){ v = 'Weight is flat while lifts go up, which is normal early in a recomp. Watch the waist.'; cls = 'ok'; }
  else v = 'Steady. Keep logging; the trend gets clearer every week.';
  var stuck = exerciseKeys().filter(function(e){ return PLAN.A.concat(PLAN.B).some(function(p){ return p.k === e.k; }) && stalled(e.k); });
  $('wk-stall').textContent = stuck.length ? 'No new best in the last 3 sessions: ' + stuck.map(function(e){ return e.n; }).join(', ') + '. The workout suggests a lighter session for each.' : '';
  var vp = $('wk-verdict'); vp.className = 'pace' + (cls ? ' ' + cls : '');
  vp.textContent = v + (facts.length ? ' (' + facts.join(', ') + '.)' : '');
  // Calorie target suggestion.
  var ce = calorieEstimate(end), kp = $('wk-kcal'), kb = $('wk-kcal-use');
  kb.hidden = true;
  if (ce.need){
    kp.textContent = 'Calorie estimate: log calories on 14 of 28 days and weigh in at least 8 times (calories logged on ' + ce.days + ' days so far).';
  } else {
    var cur = num(settings.kcal), diff = ce.target - cur;
    kp.textContent = 'You ate ' + fmt(ce.avg, 0) + ' kcal a day on average (' + ce.days + ' logged days) and weight moved ' + sgn(ce.wk, 2, 'kg/week') + ', so maintenance is about ' +
      fmt(ce.tdee, 0) + ' kcal. ' + (Math.abs(diff) < 100 ? 'Your target of ' + fmt(cur, 0) + ' fits the 0.25 to 0.5 kg/week pace.' :
      'For 0.25 to 0.5 kg a week, aim for about ' + fmt(ce.target, 0) + ' kcal (now ' + fmt(cur, 0) + ').');
    if (Math.abs(diff) >= 100){ kb.hidden = false; kb.textContent = 'Use ' + fmt(ce.target, 0) + ' kcal'; kb.dataset.v = ce.target; }
  }
}
function useKcal(){
  var t = $('t-kcal'); t.value = $('wk-kcal-use').dataset.v;
  var det = t.closest('details'); if (det) det.open = true;
  setStatus('st-targets', 'Calories set to ' + t.value + '. Press Save targets to keep it.');
  t.scrollIntoView({behavior: 'smooth', block: 'center'}); t.focus({preventScroll: true});
}

/* ---------- coaching: profile, proposals, coach card ---------- */
var profile = {}, coachAt = 0;
var GOAL_KINDS = [['recomp', 'Recomp: lose fat, build muscle'], ['fat-loss', 'Fat loss'], ['muscle', 'Build muscle'], ['strength', 'Strength'], ['health', 'Health']];
var MEASURES = [['waist', 'Waist (cm)'], ['weight', 'Weight (kg)'], ['bodyfat', 'Body fat (%)'], ['exercise', 'Exercise working weight (kg)']];
var WEEKDAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
var PROFILE_TEXT = [['goal_notes', 'p-goal-notes'], ['experience', 'p-exp'], ['equipment', 'p-equip'], ['injuries', 'p-inj'], ['conditions', 'p-cond'], ['diet', 'p-diet'], ['notes', 'p-notes']];
var goalsDraft = [];

function el(tag, cls, text){ var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
function opt(sel_, v, label, on){ var o = document.createElement('option'); o.value = v; o.textContent = label; if (on) o.selected = true; sel_.appendChild(o); }

function fillProfile(){
  var p = profile || {};
  $('p-birth').value = p.birth_year || '';
  $('p-goal').value = p.goal || '';
  $('p-dpw').value = p.days_per_week || '';
  $('p-min').value = p.session_minutes || '';
  PROFILE_TEXT.forEach(function(f){ $(f[1]).value = p[f[0]] || ''; });
  WEEKDAYS.forEach(function(d){ $('p-day-' + d).checked = (p.days || []).indexOf(d) >= 0; });
  goalsDraft = JSON.parse(JSON.stringify(p.goals || []));
  renderGoalsEditor();
}
function readGoals(){
  goalsDraft.forEach(function(g, i){
    var q = function(f){ return $('g-' + i + '-' + f); };
    if (!q('m')) return;
    g.measure = q('m').value;
    if (g.measure === 'exercise') g.exercise = q('x').value; else delete g.exercise;
    g.target = num(q('t').value);
    var by = q('by').value; if (by) g.by = by; else delete g.by;
    var lb = q('l').value.trim(); if (lb) g.label = lb; else delete g.label;
    (g.milestones || []).forEach(function(m, j){ m.value = num($('g-' + i + '-mv-' + j).value); m.by = $('g-' + i + '-mb-' + j).value; });
  });
}
function renderGoalsEditor(){
  var host = $('p-goals'); host.textContent = '';
  goalsDraft.forEach(function(g, i){
    var box = el('div', 'goal-ed');
    var row = el('div', 'goal-row');
    var m = document.createElement('select'); m.id = 'g-' + i + '-m'; m.setAttribute('aria-label', 'Goal ' + (i + 1) + ' measure');
    MEASURES.forEach(function(x){ opt(m, x[0], x[1], g.measure === x[0]); });
    m.addEventListener('change', function(){ readGoals(); renderGoalsEditor(); });
    row.appendChild(m);
    if (g.measure === 'exercise'){
      var x = document.createElement('select'); x.id = 'g-' + i + '-x'; x.setAttribute('aria-label', 'Goal ' + (i + 1) + ' exercise');
      exerciseKeys().forEach(function(e){ opt(x, e.k, e.n, g.exercise === e.k); });
      row.appendChild(x);
    }
    var t = mkInput('g-' + i + '-t', 'target', 'Goal ' + (i + 1) + ' target'); t.value = g.target != null ? g.target : ''; row.appendChild(t);
    var by = document.createElement('input'); by.type = 'date'; by.id = 'g-' + i + '-by'; by.value = g.by || ''; by.setAttribute('aria-label', 'Goal ' + (i + 1) + ' by date'); row.appendChild(by);
    box.appendChild(row);
    var lb = document.createElement('input'); lb.type = 'text'; lb.maxLength = 60; lb.id = 'g-' + i + '-l'; lb.placeholder = 'Name (optional)'; lb.value = g.label || ''; lb.setAttribute('aria-label', 'Goal ' + (i + 1) + ' name');
    box.appendChild(lb);
    (g.milestones || []).forEach(function(ms, j){
      var mr = el('div', 'goal-row ms');
      mr.appendChild(el('span', 'hint', 'Checkpoint'));
      var mv = mkInput('g-' + i + '-mv-' + j, 'value', 'Checkpoint ' + (j + 1) + ' value'); mv.value = ms.value != null ? ms.value : ''; mr.appendChild(mv);
      var mb = document.createElement('input'); mb.type = 'date'; mb.id = 'g-' + i + '-mb-' + j; mb.value = ms.by || ''; mb.setAttribute('aria-label', 'Checkpoint ' + (j + 1) + ' date'); mr.appendChild(mb);
      var rm = el('button', 'tab', '✕'); rm.type = 'button'; rm.setAttribute('aria-label', 'Remove checkpoint ' + (j + 1));
      rm.addEventListener('click', function(){ readGoals(); g.milestones.splice(j, 1); renderGoalsEditor(); });
      mr.appendChild(rm); box.appendChild(mr);
    });
    var acts = el('div', 'actions');
    var addm = el('button', 'btn ghost', '+ Checkpoint'); addm.type = 'button';
    addm.addEventListener('click', function(){ readGoals(); (g.milestones = g.milestones || []).push({value: null, by: ''}); renderGoalsEditor(); });
    var rmg = el('button', 'btn ghost', 'Remove goal'); rmg.type = 'button';
    rmg.addEventListener('click', function(){ readGoals(); goalsDraft.splice(i, 1); renderGoalsEditor(); });
    if ((g.milestones || []).length < 6) acts.appendChild(addm);
    acts.appendChild(rmg); box.appendChild(acts);
    host.appendChild(box);
  });
  $('p-add-goal').hidden = goalsDraft.length >= 5;
}
function profileProblem(p){
  if (p.birth_year != null && !(p.birth_year >= 1900 && p.birth_year <= 2030)) return 'Birth year looks wrong.';
  if (p.session_minutes != null && !(p.session_minutes >= 10 && p.session_minutes <= 240)) return 'Session length is 10 to 240 minutes.';
  for (var i = 0; i < (p.goals || []).length; i++){
    var g = p.goals[i], at = 'Goal ' + (i + 1) + ': ';
    if (!(g.target > 0)) return at + 'set a target above 0.';
    if (g.measure === 'exercise' && !g.exercise) return at + 'pick the exercise.';
    for (var j = 0; j < (g.milestones || []).length; j++) if (g.milestones[j].value == null || !g.milestones[j].by) return at + 'each checkpoint needs a value and a date.';
  }
  return null;
}
function saveProfile(){
  readGoals();
  var p = {}, n;
  if ((n = num($('p-birth').value)) != null) p.birth_year = Math.round(n);
  if ($('p-goal').value) p.goal = $('p-goal').value;
  if ((n = num($('p-dpw').value)) != null) p.days_per_week = Math.round(n);
  if ((n = num($('p-min').value)) != null) p.session_minutes = Math.round(n);
  var days = WEEKDAYS.filter(function(d){ return $('p-day-' + d).checked; }); if (days.length) p.days = days;
  PROFILE_TEXT.forEach(function(f){ var v = $(f[1]).value.trim(); if (v) p[f[0]] = v; });
  var goals = goalsDraft.map(function(g){ var o = Object.assign({}, g); if (o.milestones && !o.milestones.length) delete o.milestones; return o; });
  if (goals.length) p.goals = goals;
  var bad = profileProblem(p);
  if (bad){ setStatus('st-profile', bad, true); return; }
  profile = p;
  saveDoc('profile', p, 'st-profile', 'Profile saved').then(function(){ loadCoach(true); });
}

// One line per change between two documents, for the proposal's diff.
function fieldName(k){ return {kcal: 'Calories', protein: 'Protein', steps: 'Steps', sleep: 'Sleep', workouts: 'Workouts per week', rest: 'Rest (sec)', height: 'Height', start_weight: 'Start weight', sex: 'Sex',
  birth_year: 'Birth year', goal: 'Goal', goal_notes: 'Goal notes', experience: 'Experience', days_per_week: 'Days per week', days: 'Usual days', session_minutes: 'Session (min)',
  equipment: 'Equipment', injuries: 'Injuries', conditions: 'Conditions and medications', diet: 'Diet', notes: 'Notes', goals: 'Goals'}[k] || k; }
function show(v){ return v == null || v === '' ? '—' : Array.isArray(v) || typeof v === 'object' ? JSON.stringify(v) : String(v); }
function exLine(e){ return e.n + ' ' + e.sets + '×' + e.lo + '–' + e.hi + ' ' + e.u + (e.inc ? ', +' + e.inc + ' kg' : ''); }
function diffLines(target, cur, next){
  var out = [];
  if (target === 'plan'){
    cur = cur || DEFAULT_PLAN;
    ['A', 'B'].forEach(function(w){
      var a = cur[w] || [], b = next[w] || [];
      b.forEach(function(e){
        var o = a.filter(function(x){ return x.k === e.k; })[0];
        if (!o) out.push(['add', 'Workout ' + w + ': add ' + exLine(e)]);
        else if (exLine(o) !== exLine(e)) out.push(['chg', 'Workout ' + w + ': ' + exLine(o) + ' → ' + exLine(e)]);
      });
      a.forEach(function(o){ if (!b.some(function(e){ return e.k === o.k; })) out.push(['del', 'Workout ' + w + ': remove ' + o.n]); });
      var ka = a.map(function(x){ return x.k; }).filter(function(k){ return b.some(function(e){ return e.k === k; }); });
      var kb = b.map(function(x){ return x.k; }).filter(function(k){ return a.some(function(e){ return e.k === k; }); });
      if (ka.join() !== kb.join()) out.push(['chg', 'Workout ' + w + ': new order ' + b.map(function(e){ return e.n; }).join(', ')]);
    });
  } else {
    cur = cur || {};
    var keys = Object.keys(Object.assign({}, cur, next));
    keys.forEach(function(k){ if (!same(cur[k], next[k])) out.push(['chg', fieldName(k) + ': ' + show(cur[k]) + ' → ' + show(next[k])]); });
  }
  return out;
}

function api(method, path, body){
  var o = {method: method, cache: 'no-store', redirect: 'manual', headers: {'X-Fitness-User': user || ''}};
  if (body){ o.headers['Content-Type'] = 'application/json'; o.body = JSON.stringify(body); }
  return fetch(path, o).then(function(r){
    if (r.type === 'opaqueredirect' || r.status === 401) throw {auth: true};
    return r.json().catch(function(){ return {}; }).then(function(j){ return {status: r.status, ok: r.ok, body: j}; });
  });
}
// Proposals, summary and log; at most every 5 minutes unless forced.
function loadCoach(force){
  if (!force && Date.now() - coachAt < 300000) return Promise.resolve();
  coachAt = Date.now();
  return Promise.all([api('GET', 'api/coach/proposals'), api('GET', 'api/coach/summary?end=' + todayStr() + '&weeks=6'), api('GET', 'api/coach/log?limit=20')])
    .then(function(r){
      if (r[0].ok) renderProposals(r[0].body.proposals || []);
      if (r[1].ok) renderCoach(r[1].body);
      if (r[2].ok) renderLog(r[2].body.entries || []);
    }, function(){ coachAt = 0; });
}
function renderProposals(list){
  var host = $('props'), open = list.filter(function(p){ return p.status === 'open'; });
  host.textContent = ''; host.hidden = !open.length;
  open.forEach(function(p){
    var box = el('div', 'prop');
    box.appendChild(el('h2', null, 'Your coach suggests a change to ' + (p.target === 'plan' ? 'your plan' : p.target === 'settings' ? 'your targets' : 'your profile')));
    box.appendChild(el('p', 'why', p.why));
    var ul = el('ul', 'diff');
    var lines = diffLines(p.target, p.current ? p.current.data : null, p.data);
    if (!lines.length) lines = [['chg', 'No visible change.']];
    lines.forEach(function(l){ ul.appendChild(el('li', l[0], l[1])); });
    box.appendChild(ul);
    var note = document.createElement('input'); note.type = 'text'; note.maxLength = 500; note.placeholder = 'Note for your coach (optional)'; note.setAttribute('aria-label', 'Note for your coach');
    box.appendChild(note);
    var acts = el('div', 'actions'), st = el('span', 'status');
    st.setAttribute('role', 'status'); st.setAttribute('aria-live', 'polite');
    function decide(action){
      st.textContent = action === 'accept' ? 'Applying…' : 'Sending…';
      api('POST', 'api/coach/proposals/' + p.id + '/' + action, {note: note.value}).then(function(r){
        if (r.ok){ st.textContent = action === 'accept' ? 'Applied.' : 'Rejected; your coach will see your note.'; return load().then(function(){ fillTargets(); fillProfile(); renderWorkout(); return loadCoach(true); }); }
        st.className = 'status err';
        st.textContent = r.body.status === 'outdated' ? 'Not applied: this changed after your coach wrote it. Your coach will write a fresh one.' : (r.body.error || 'Could not save.');
        return loadCoach(true);
      }, function(e){ st.className = 'status err'; st.textContent = e && e.auth ? 'Signed out. Reload to sign in.' : 'Offline: try again when connected.'; });
    }
    var a = el('button', 'btn', 'Accept'); a.type = 'button'; a.addEventListener('click', function(){ decide('accept'); });
    var r = el('button', 'btn ghost', 'Reject'); r.type = 'button'; r.addEventListener('click', function(){ decide('reject'); });
    acts.appendChild(a); acts.appendChild(r); acts.appendChild(st); box.appendChild(acts);
    host.appendChild(box);
  });
}
function renderCoach(s){
  var al = $('co-alerts'); al.textContent = '';
  (s.alerts || []).forEach(function(a){ al.appendChild(el('li', a.kind === 'check-in' || a.kind === 'proposal' ? '' : 'warn', a.text)); });
  if (!(s.alerts || []).length) al.appendChild(el('li', 'ok', 'Nothing needs attention.'));
  var gh = $('co-goals'); gh.textContent = '';
  (s.goals || []).forEach(function(g){
    var li = el('li');
    var head = g.label + ': ' + (g.current != null ? fmt(g.current, 1) : '—') + ' → ' + fmt(g.target, 1) + ' ' + g.unit + (g.by ? ' by ' + fmtDay(g.by) : '');
    li.appendChild(el('div', 'gh', head));
    var eta = g.eta === 'reached' ? 'Reached.' : g.eta ? 'At the current pace: about ' + fmtDay(g.eta) + '.' : 'Not enough trend yet to estimate.';
    if (g.eta && g.eta !== 'reached' && g.by && g.eta > g.by) eta += ' That is after your date.';
    li.appendChild(el('div', 'hint', eta));
    (g.milestones || []).forEach(function(m){ li.appendChild(el('div', 'hint ms-' + m.status.replace(/ /g, '-'), 'Checkpoint ' + fmt(m.value, 1) + ' ' + g.unit + ' by ' + fmtDay(m.by) + ': ' + m.status)); });
    gh.appendChild(li);
  });
  $('co-goals-h').hidden = !(s.goals || []).length;
  $('co-text').textContent = s.text || '';
}
function renderLog(entries){
  var host = $('co-log'); host.textContent = '';
  if (!entries.length) host.appendChild(el('li', 'hint', 'Nothing yet. Check-ins, decisions and your notes appear here.'));
  entries.forEach(function(e){
    var li = el('li');
    var d = new Date(e.at * 1000), who = e.author === 'you' ? 'You' : e.author === 'coach' ? 'Coach' : 'App';
    li.appendChild(el('span', 'lg-meta', d.toLocaleDateString('en-GB', {day: 'numeric', month: 'short'}) + ' · ' + who + (e.kind === 'check-in' ? ' · check-in' : '')));
    li.appendChild(el('span', null, e.text));
    host.appendChild(li);
  });
}
function addNote(){
  var t = $('co-note').value.trim();
  if (!t){ setStatus('st-note', 'Write a note first.', true); return; }
  setStatus('st-note', 'Saving…');
  api('POST', 'api/coach/log', {text: t}).then(function(r){
    if (!r.ok){ setStatus('st-note', r.body.error || 'Could not save.', true); return; }
    $('co-note').value = ''; setStatus('st-note', 'Noted for your coach.'); loadCoach(true);
  }, function(){ setStatus('st-note', 'Offline: try again when connected.', true); });
}

/* ---------- cardio, blood tests, progress photos ---------- */
var extrasAt = 0, labMarkers = null, photoList = [];
function mkBtn(text, cls, fn){ var b = el('button', cls, text); b.type = 'button'; b.addEventListener('click', fn); return b; }
// Two clicks to delete: the first arms the button.
function delBtn(what, fn){
  var b = mkBtn('Delete', 'btn danger', function(){
    if (!b.classList.contains('armed')){ b.classList.add('armed'); b.textContent = 'Sure?'; setTimeout(function(){ b.classList.remove('armed'); b.textContent = 'Delete'; }, 4000); return; }
    fn();
  });
  b.setAttribute('aria-label', 'Delete ' + what);
  return b;
}
function postDelete(path, stId, then){
  api('POST', path + '/delete', {}).then(function(r){
    if (!r.ok){ setStatus(stId, r.body.error || 'Could not delete.', true); return; }
    setStatus(stId, 'Deleted.'); then();
  }, function(){ setStatus(stId, 'Offline: try again when connected.', true); });
}
function loadExtras(force){
  if (!force && Date.now() - extrasAt < 300000) return Promise.resolve();
  extrasAt = Date.now();
  return Promise.all([api('GET', 'api/cardio?days=14'), api('GET', 'api/labs'), api('GET', 'api/photos')]).then(function(r){
    if (r[0].ok) renderCardio(r[0].body.cardio || []);
    if (r[1].ok) renderLabs(r[1].body);
    if (r[2].ok){ photoList = r[2].body.photos || []; renderPhotos(); }
  }, function(){ extrasAt = 0; });
}
var KIND_LABEL = {'walk': 'Walk', 'incline-walk': 'Incline walk', 'cycle': 'Cycle', 'cross-trainer': 'Cross-trainer', 'row': 'Row', 'swim': 'Swim', 'sport': 'Sport', 'other': 'Other'};
function renderCardio(list){
  var host = $('c-list'); host.textContent = '';
  if (!list.length) host.appendChild(el('li', 'hint', 'No sessions in the last 14 days.'));
  list.forEach(function(s){
    var li = el('li');
    var t = fmtDay(s.date) + ' · ' + (KIND_LABEL[s.kind] || s.kind) + ' · ' + s.minutes + ' min';
    if (s.distance_km != null) t += ' · ' + fmt(s.distance_km, 2) + ' km';
    if (s.avg_hr != null) t += ' · ' + s.avg_hr + ' bpm';
    if (s.rpe != null) t += ' · effort ' + s.rpe + '/10';
    var g = el('span', 'grow', t);
    if (s.note) g.appendChild(el('div', 'hint', s.note));
    li.appendChild(g);
    li.appendChild(delBtn('session on ' + fmtDay(s.date), function(){ postDelete('api/cardio/' + s.id, 'st-cardio', function(){ loadExtras(true); }); }));
    host.appendChild(li);
  });
}
function addCardio(ev){
  ev.preventDefault();
  var body = {date: $('c-date').value, kind: $('c-kind').value, minutes: num($('c-min').value)};
  if (!body.date || body.minutes == null){ setStatus('st-cardio', 'Add a date and the minutes.', true); return; }
  var km = num($('c-km').value), hr = num($('c-hr').value), rpe = num($('c-rpe').value), note = $('c-note').value.trim();
  if (km != null) body.distance_km = km;
  if (hr != null) body.avg_hr = hr;
  if (rpe != null) body.rpe = rpe;
  if (note) body.note = note;
  setStatus('st-cardio', 'Saving…');
  api('POST', 'api/cardio', body).then(function(r){
    if (!r.ok){ setStatus('st-cardio', r.body.error || 'Could not save.', true); return; }
    ['c-min', 'c-km', 'c-hr', 'c-rpe', 'c-note'].forEach(function(i){ $(i).value = ''; });
    setStatus('st-cardio', 'Added.'); loadExtras(true);
  }, function(){ setStatus('st-cardio', 'Offline: try again when connected.', true); });
}

function labMarker(k){ var m = null; (labMarkers || []).forEach(function(x){ if (x.key === k) m = x; }); return m; }
function rangeText(l){
  if (l.low != null && l.high != null) return fmt(l.low, 2) + '–' + fmt(l.high, 2);
  if (l.high != null) return 'up to ' + fmt(l.high, 2);
  if (l.low != null) return 'at least ' + fmt(l.low, 2);
  return null;
}
function renderLabs(b){
  if (!labMarkers){
    labMarkers = b.markers || [];
    var sel_ = $('l-marker');
    labMarkers.forEach(function(m){ opt(sel_, m.key, m.label + (m.unit ? ' (' + m.unit + ')' : ''), false); });
    labMarkerChanged();
  }
  var host = $('lab-latest'); host.textContent = '';
  var today = todayStr();
  if (!(b.latest || []).length) host.appendChild(el('li', 'hint', 'No results yet.'));
  (b.latest || []).forEach(function(l){
    var li = el('li'), g = el('span', 'grow', l.label + ': ' + fmt(l.value, 2) + ' ' + l.unit + ' (' + fmtDay(l.date) + ')');
    var rt = rangeText(l);
    if (rt) g.appendChild(el('div', 'hint', 'Typical range ' + rt + ' ' + l.unit));
    li.appendChild(g);
    if (l.outside) li.appendChild(el('span', 'flag', 'Outside typical range (' + l.direction + ')'));
    if (l.next_due) li.appendChild(el('span', 'due' + (l.next_due < today ? ' late' : ''), (l.next_due < today ? 'Recheck overdue since ' : 'Recheck ') + fmtDay(l.next_due)));
    host.appendChild(li);
  });
  var all = $('lab-all'); all.textContent = '';
  (b.labs || []).forEach(function(l){
    var li = el('li');
    li.appendChild(el('span', 'grow', fmtDay(l.date) + ' · ' + (l.name || (labMarker(l.marker) || {}).label || l.marker) + ': ' + fmt(l.value, 2) + ' ' + l.unit + (l.note ? ' · ' + l.note : '')));
    li.appendChild(delBtn('result', function(){ postDelete('api/labs/' + l.id, 'st-lab', function(){ loadExtras(true); }); }));
    all.appendChild(li);
  });
}
function labMarkerChanged(){
  var m = labMarker($('l-marker').value), other = m && m.key === 'other';
  $('l-name-f').hidden = !other; $('l-unit-f').hidden = !other;
  $('l-unit-t').textContent = m && !other ? '(' + m.unit + ')' : '';
}
function addLab(ev){
  ev.preventDefault();
  var body = {date: $('l-date').value, marker: $('l-marker').value, value: num($('l-value').value)};
  if (!body.date || body.value == null){ setStatus('st-lab', 'Add a date and the result.', true); return; }
  if (body.marker === 'other'){ body.name = $('l-name').value.trim(); body.unit = $('l-unit').value.trim(); }
  var note = $('l-note').value.trim();
  if (note) body.note = note;
  setStatus('st-lab', 'Saving…');
  api('POST', 'api/labs', body).then(function(r){
    if (!r.ok){ setStatus('st-lab', r.body.error || 'Could not save.', true); return; }
    ['l-value', 'l-note', 'l-name', 'l-unit'].forEach(function(i){ $(i).value = ''; });
    setStatus('st-lab', 'Added.'); loadExtras(true);
  }, function(){ setStatus('st-lab', 'Offline: try again when connected.', true); });
}

function photoImg(p){
  var f = el('figure'), im = document.createElement('img');
  im.src = 'api/photos/' + p.id; im.alt = p.pose + ' photo from ' + fmtDay(p.date); im.loading = 'lazy';
  f.appendChild(im); f.appendChild(el('figcaption', null, fmtDay(p.date) + ' · ' + p.pose));
  return f;
}
function renderPhotos(){
  var list = $('ph-list'); list.textContent = '';
  if (!photoList.length) list.appendChild(el('li', 'hint', 'No photos yet.'));
  photoList.forEach(function(p){
    var li = el('li');
    li.appendChild(el('span', 'grow', fmtDay(p.date) + ' · ' + p.pose));
    li.appendChild(delBtn('photo from ' + fmtDay(p.date), function(){ postDelete('api/photos/' + p.id, 'st-photo', function(){ loadExtras(true); }); }));
    list.appendChild(li);
  });
  var pose = $('ph-cpose').value, mine = photoList.filter(function(p){ return p.pose === pose; }).reverse();
  var a = $('ph-a'), b = $('ph-b'), pa = a.value, pb = b.value;
  [a, b].forEach(function(s){ s.textContent = ''; mine.forEach(function(p){ opt(s, String(p.id), fmtDay(p.date) + ' (' + p.date.slice(0, 4) + ')', false); }); });
  if (mine.length){
    a.value = pa && a.querySelector('option[value="' + pa + '"]') ? pa : String(mine[0].id);
    b.value = pb && b.querySelector('option[value="' + pb + '"]') ? pb : String(mine[mine.length - 1].id);
  }
  renderPair();
}
function renderPair(){
  var host = $('ph-pair'); host.textContent = '';
  var byId = {}; photoList.forEach(function(p){ byId[p.id] = p; });
  [$('ph-a').value, $('ph-b').value].forEach(function(id){ if (byId[id]) host.appendChild(photoImg(byId[id])); });
  if (!host.firstChild) host.appendChild(el('p', 'hint', 'Add photos of this pose to compare two dates.'));
}
// Downsizes to at most 1600 px on the long side and re-encodes as JPEG.
function shrink(file){
  return new Promise(function(resolve, reject){
    var fr = new FileReader();
    fr.onerror = function(){ reject(new Error('Could not read that file.')); };
    fr.onload = function(){
      var im = new Image();
      im.onerror = function(){ reject(new Error('That file is not an image this browser can open.')); };
      im.onload = function(){
        var k = Math.min(1, 1600 / Math.max(im.naturalWidth, im.naturalHeight)), cv = document.createElement('canvas');
        cv.width = Math.max(1, Math.round(im.naturalWidth * k)); cv.height = Math.max(1, Math.round(im.naturalHeight * k));
        cv.getContext('2d').drawImage(im, 0, 0, cv.width, cv.height);
        cv.toBlob(function(b){ b ? resolve(b) : reject(new Error('Could not resize that photo.')); }, 'image/jpeg', 0.85);
      };
      im.src = fr.result;
    };
    fr.readAsDataURL(file);
  });
}
function uploadPhoto(file){
  var date = $('ph-date').value || todayStr(), pose = $('ph-pose').value;
  setStatus('st-photo', 'Uploading…');
  shrink(file).then(function(blob){
    return fetch('api/photos?date=' + encodeURIComponent(date) + '&pose=' + encodeURIComponent(pose), {method: 'POST', cache: 'no-store', redirect: 'manual',
      headers: {'Content-Type': 'image/jpeg', 'X-Fitness-User': user || ''}, body: blob});
  }).then(function(r){
    if (r.type === 'opaqueredirect' || r.status === 401) throw new Error('Signed out. Reload to sign in.');
    return r.json().catch(function(){ return {}; }).then(function(j){ if (!r.ok) throw new Error(j.error || 'Could not upload.'); });
  }).then(function(){
    $('ph-file').value = ''; setStatus('st-photo', 'Photo saved.'); $('ph-cpose').value = pose; return loadExtras(true);
  }, function(e){ setStatus('st-photo', e && e.message ? e.message : 'Offline: try again when connected.', true); });
}

/* ---------- header, banner, derived ---------- */
function renderHeader(){
  var ds = dates(), sub = $('sub'), b = $('banner');
  if (!ds.length){
    sub.textContent = 'Start with today\'s weigh-in.';
    b.hidden = false;
    b.textContent = 'Nothing logged yet. Enter your weight and waist below, then add a line each day. Set your height under Daily targets to see BMI.';
  } else {
    var wk = Math.floor((dayNum(todayStr()) - dayNum(ds[0])) / 7) + 1;
    sub.textContent = 'Week ' + Math.max(1, wk) + ' · since ' + fmtDay(ds[0]);
    b.hidden = true;
  }
}
function renderDerived(){
  renderHeader(); renderBars(); renderStats(); drawCharts(); renderHabits(); renderWeek(); renderProgress();
}

/* ---------- storage: server copy, offline cache, outbox ----------
   server/vers: the last copy and version the server confirmed for each id.
   outbox: unsent changes, id -> {op, data, orig, base, seq}. `orig` is the server
   copy the change was made against, used for a field-level merge on conflict.
   What the page shows is the server copy with the outbox laid over it. */
var server = {}, vers = {};
// Everything stored on the device is kept per signed-in user (Remote-User, from
// api/me): on a shared device the next person neither sees the last person's
// copy nor sends their unsent changes. `user` is the last account seen here.
var user = loadRaw('fitness.user');
var outbox = user ? loadJSON(key('outbox'), {}) : {};
var chain = Promise.resolve(), netState = 'ok', serverSeen = false, typed = false;
document.addEventListener('input', function(){ typed = true; }, {once: true});

function loadJSON(k, d){ try { var v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch(e){ return d; } }
function saveJSON(k, v){ try { localStorage.setItem(k, JSON.stringify(v)); } catch(e){} }
function same(a, b){ return JSON.stringify(a == null ? null : a) === JSON.stringify(b == null ? null : b); }
function loadRaw(k){ try { return localStorage.getItem(k); } catch(e){ return null; } }
function key(name){ return 'fitness.' + name + '.' + user; }
function persist(){ if (!user) return; saveJSON(key('outbox'), outbox); saveJSON(key('cache'), {server: server, vers: vers}); }
// Who the server says is signed in; on a change, switch to that account's own copy.
function whoami(){
  return fetch('api/me', {cache: 'no-store', redirect: 'manual'}).then(function(r){
    if (r.type === 'opaqueredirect' || r.status === 401) throw {auth: true};
    if (!r.ok) throw {net: true};
    return r.json();
  }).then(function(j){ if (j.user && j.user !== user) switchUser(j.user); });
}
function switchUser(u){
  var first = !user;
  user = u;
  try {
    localStorage.setItem('fitness.user', u);
    // Data stored before storage was per user goes to the first account seen on this device.
    ['outbox', 'cache'].forEach(function(n){
      var old = localStorage.getItem('fitness.' + n);
      if (old !== null && first && localStorage.getItem(key(n)) === null) localStorage.setItem(key(n), old);
      localStorage.removeItem('fitness.' + n);
    });
  } catch(e){}
  outbox = loadJSON(key('outbox'), {});
  var c = loadJSON(key('cache'), null);
  server = c && c.server ? c.server : {}; vers = c && c.vers ? c.vers : {};
  // Refill the forms from this account's data.
  firstSnap = true; serverSeen = false; typed = false; coachAt = 0; extrasAt = 0;
  document.addEventListener('input', function(){ typed = true; }, {once: true});
  rebuild();
}
function idLabel(id){ return id === 'settings' ? 'Targets' : id === 'plan' ? 'Your plan' : id === 'profile' ? 'Your profile' : fmtDay(id); }

function rebuild(){
  var view = Object.assign({}, server);
  Object.keys(outbox).forEach(function(id){ if (outbox[id].op === 'delete') delete view[id]; else view[id] = outbox[id].data; });
  settings = Object.assign({}, DEF, view.settings || {});
  var p = view.plan;
  PLAN = p && Array.isArray(p.A) && Array.isArray(p.B) && (p.A.length || p.B.length) ? p : DEFAULT_PLAN;
  profile = view.profile || {};
  delete view.settings; delete view.plan; delete view.profile;
  docs = view;
  if (firstSnap){ firstSnap = false; wsel = suggestWorkout(sel); fillForm(); fillTargets(); fillProfile(); renderWorkout(); }
  renderDerived(); updateDelete();
}

function queue(id, op, data){
  var e = outbox[id];
  if (!e) e = outbox[id] = {base: vers[id] || 0, orig: server[id] || null, seq: 0};
  e.op = op; e.data = data; e.seq++;
  persist();
  return flush();
}

function flush(){ chain = chain.then(drain); return chain; }
function drain(){
  // Confirm the account first, so changes are only ever sent as the user who made them.
  return whoami().then(function(){ return Object.keys(outbox).reduce(function(p, id){ return p.then(function(){ return sendOne(id, 0); }); }, Promise.resolve()); })
    .then(function(){ setNet('ok'); }, function(err){ setNet(err && err.auth ? 'auth' : 'offline'); });
}

function sendOne(id, tries){
  var e = outbox[id];
  if (!e) return Promise.resolve();
  var op = e.op, sent = e.data, seq = e.seq, base = e.base;
  var opts = {method: op === 'delete' ? 'DELETE' : 'PUT', redirect: 'manual', cache: 'no-store', headers: {'If-Match': String(base), 'X-Fitness-User': user || ''}};
  if (op !== 'delete'){ opts.headers['Content-Type'] = 'application/json'; opts.body = JSON.stringify(sent); }
  return fetch('api/log/' + id, opts).then(function(r){
    if (r.type === 'opaqueredirect' || r.status === 401) throw {auth: true};
    // Another account is signed in now: keep the change for its owner and switch.
    if (r.status === 403) return whoami().then(function(){ throw {net: true}; });
    if (r.status === 409) return r.json().then(function(j){ return resolveConflict(id, j.current, tries); });
    if (r.status >= 500) throw {net: true};
    return r.json().catch(function(){ return {}; }).then(function(j){
      if (!r.ok){ return rejected(id, j.error || ('HTTP ' + r.status)); }
      if (op === 'delete'){ delete server[id]; delete vers[id]; } else { server[id] = sent; vers[id] = j.version; }
      var cur = outbox[id];
      if (cur && cur.seq === seq) delete outbox[id];
      else if (cur){ cur.base = vers[id] || 0; cur.orig = server[id] || null; }
      persist();
    });
  });
}

// The server has a newer copy. Keep the fields this device changed, take the
// rest from the server, and retry against the new version.
function resolveConflict(id, cur, tries){
  var e = outbox[id];
  var theirs = cur ? cur.data : null;
  if (theirs){ server[id] = theirs; vers[id] = cur.version; } else { delete server[id]; delete vers[id]; }
  if (e.op === 'delete'){
    delete outbox[id]; persist(); rebuild();
    if (theirs) notice(idLabel(id) + ' was changed on another device, so it was not deleted.');
    return;
  }
  e.data = merge(e.orig, e.data, theirs); e.orig = theirs; e.base = cur ? cur.version : 0;
  persist(); rebuild();
  if (id === sel || id === 'settings'){ fillForm(); fillTargets(); renderWorkout(); }
  if (tries >= 3) throw {net: true};
  return sendOne(id, tries + 1);
}
function merge(orig, mine, theirs){
  if (!theirs) return mine;
  orig = orig || {}; mine = mine || {};
  var out = Object.assign({}, theirs);
  Object.keys(Object.assign({}, orig, mine)).forEach(function(k){
    if (k === 'sets' || same(orig[k], mine[k])) return;
    if (mine[k] == null) delete out[k]; else out[k] = mine[k];
  });
  var os = orig.sets || {}, ms = mine.sets || {}, sets = Object.assign({}, theirs.sets || {});
  Object.keys(Object.assign({}, os, ms)).forEach(function(x){
    if (same(os[x], ms[x])) return;
    if (ms[x] == null) delete sets[x]; else sets[x] = ms[x];
  });
  if (Object.keys(sets).length) out.sets = sets; else delete out.sets;
  return out;
}
// The server refused the data itself (400); drop the change and show its copy.
function rejected(id, msg){
  delete outbox[id]; persist(); rebuild();
  if (id === sel){ fillForm(); renderWorkout(); }
  notice('Could not save ' + idLabel(id) + ': ' + msg);
}

function notice(msg){ var b = $('banner'); b.hidden = false; b.textContent = msg; }
function setNet(state){
  netState = state;
  var el = $('net'), n = Object.keys(outbox).length;
  var waiting = n ? n + (n === 1 ? ' change' : ' changes') + ' saved on this device' : '';
  el.className = 'net'; el.textContent = '';
  if (state === 'ok' && !n){ el.hidden = true; return; }
  el.hidden = false;
  if (state === 'auth'){
    el.classList.add('warn');
    el.appendChild(document.createTextNode('Signed out' + (waiting ? ', ' + waiting : '') + '. '));
    var a = document.createElement('a'); a.href = './'; a.textContent = 'Sign in again'; el.appendChild(a);
    return;
  }
  if (state === 'offline'){ el.classList.add('warn'); el.textContent = 'Offline' + (waiting ? ', ' + waiting + ', will sync' : ', showing your last saved copy'); return; }
  el.textContent = waiting + ', syncing…';
}

function load(){
  return whoami().then(function(){ return fetch('api/log', {cache: 'no-store', redirect: 'manual'}); }).then(function(r){
    if (r.type === 'opaqueredirect' || r.status === 401) throw {auth: true};
    if (!r.ok) throw {net: true};
    return r.json();
  }).then(function(j){
    server = {}; vers = {};
    j.docs.forEach(function(x){ server[x.id] = x.data; vers[x.id] = x.version; });
    persist(); rebuild();
    // The forms were filled from the offline copy (or nothing); refresh them from
    // the first server answer unless the user has already started typing.
    if (!serverSeen){ serverSeen = true; if (!typed){ fillForm(); fillTargets(); fillProfile(); renderWorkout(); } }
    loadCoach(false); loadExtras(false);
    if (Object.keys(outbox).length) return flush();
    setNet('ok');
  }, function(err){ setNet(err && err.auth ? 'auth' : 'offline'); });
}
function sync(){ return Object.keys(outbox).length ? flush().then(load) : load(); }

function connect(){
  var c = user ? loadJSON(key('cache'), null) : null;
  if (c && c.server){ server = c.server; vers = c.vers || {}; }
  rebuild();
  sync();
  setInterval(function(){ if (!document.hidden) sync(); }, 30000);
  window.addEventListener('online', sync);
  document.addEventListener('visibilitychange', function(){ if (!document.hidden) sync(); });
}

/* ---------- import ---------- */
function importFile(file){
  setStatus('st-data', 'Importing…');
  file.text().then(function(text){
    try { JSON.parse(text); } catch(e){ throw new Error('That file is not valid JSON.'); }
    return fetch('api/import', {method: 'POST', redirect: 'manual', headers: {'Content-Type': 'application/json', 'X-Fitness-User': user || ''}, body: text});
  }).then(function(r){
    if (r.type === 'opaqueredirect' || r.status === 401) throw new Error('Signed out. Reload to sign in, then import again.');
    return r.json().then(function(j){
      if (!r.ok) throw new Error(j.error || ('HTTP ' + r.status));
      var parts = [j.imported + ' imported'];
      if (j.skipped) parts.push(j.skipped + ' already here, kept');
      if (j.invalid) parts.push(j.invalid + ' not readable');
      setStatus('st-data', parts.join(', ') + '.');
      return load();
    });
  }).catch(function(e){ setStatus('st-data', e && e.message ? e.message : 'Import failed. Check your connection.', true); });
}

/* ---------- rest timer ---------- */
var restEnd = 0, restTick = 0, restHide = 0, audio = null;
function onRepsEntered(ev){ if (ev.target.value !== '') restStart(); }
function restStart(){
  try { audio = audio || new (window.AudioContext || window.webkitAudioContext)(); audio.resume(); } catch(e){ audio = null; }
  clearTimeout(restHide);
  restEnd = Date.now() + (num(settings.rest) || DEF.rest) * 1000;
  var el = $('rest'); el.hidden = false; el.classList.remove('done');
  document.body.classList.add('resting');
  $('rest-l').textContent = 'Rest';
  $('rest-notify').hidden = !('Notification' in window) || Notification.permission !== 'default';
  keepAwake(true);
  tickRest();
  if (!restTick) restTick = setInterval(tickRest, 250);
}
function tickRest(){
  var left = Math.ceil((restEnd - Date.now()) / 1000);
  if (left > 0){ $('rest-t').textContent = Math.floor(left / 60) + ':' + pad(left % 60); return; }
  clearInterval(restTick); restTick = 0;
  $('rest').classList.add('done'); $('rest-l').textContent = 'Next set'; $('rest-t').textContent = 'Go';
  buzz(); notifyRest();
  restHide = setTimeout(restStop, 6000);
}
function restStop(){
  clearInterval(restTick); restTick = 0; clearTimeout(restHide);
  $('rest').hidden = true; document.body.classList.remove('resting');
  keepAwake(false);
}
// Keep the screen on while resting, so the phone does not lock between sets
// (the page cannot run, beep or vibrate once it is locked).
var wake = null, wantAwake = false;
function keepAwake(on){
  wantAwake = on;
  if (!on){ if (wake){ wake.release().catch(function(){}); wake = null; } return; }
  if (wake || !navigator.wakeLock || document.hidden) return;
  navigator.wakeLock.request('screen').then(function(l){
    wake = l; l.addEventListener('release', function(){ if (wake === l) wake = null; });
    if (!wantAwake) keepAwake(false);
  }).catch(function(){});
}
// If the page is in the background when the rest ends, say so with a notification
// (only after the user allowed it from the rest bar).
function notifyRest(){
  if (!document.hidden || !('Notification' in window) || Notification.permission !== 'granted' || !navigator.serviceWorker) return;
  navigator.serviceWorker.ready.then(function(reg){
    return reg.showNotification('Rest over', {body: 'Next set', tag: 'rest', renotify: true, icon: 'icon-192.png', vibrate: [200, 100, 200]});
  }).catch(function(){});
}
function askNotify(){
  if (!('Notification' in window)) return;
  Notification.requestPermission().then(function(){ $('rest-notify').hidden = true; }).catch(function(){});
}
function buzz(){
  if (navigator.vibrate) navigator.vibrate([200, 100, 200]);
  if (!audio) return;
  try {
    [0, 0.25].forEach(function(t){
      var o = audio.createOscillator(), g = audio.createGain(), at = audio.currentTime + t;
      o.frequency.value = 880; g.gain.setValueAtTime(0.2, at); g.gain.exponentialRampToValueAtTime(0.001, at + 0.18);
      o.connect(g); g.connect(audio.destination); o.start(at); o.stop(at + 0.2);
    });
  } catch(e){}
}

/* ---------- wiring ---------- */
var dateEl = $('f-date');
dateEl.value = sel; dateEl.max = sel;
dateEl.addEventListener('change', function(){
  if (!dateEl.value) return;
  sel = dateEl.value; wsel = suggestWorkout(sel);
  fillForm(); setStatus('st-workout', ''); renderWorkout(); renderDerived();
});
$('day-form').addEventListener('submit', function(ev){ ev.preventDefault(); saveDay(); });
$('del-day').addEventListener('click', deleteDay);
$('save-workout').addEventListener('click', saveWorkout);
$('edit-plan').addEventListener('click', startEdit);
$('save-targets').addEventListener('click', saveTargets);
$('imp').addEventListener('change', function(){ var f = this.files && this.files[0]; if (f) importFile(f); this.value = ''; });
$('rest-add').addEventListener('click', function(){
  if (!restTick){ restStart(); restEnd = Date.now() + 15000; tickRest(); return; }
  restEnd += 15000; tickRest();
});
$('rest-skip').addEventListener('click', restStop);
$('rest-notify').addEventListener('click', askNotify);
// Gym view: only the workout card. #gym in the URL (and the app shortcut) opens it.
function setGym(on){
  document.body.classList.toggle('gym', on);
  $('gym-btn').textContent = on ? 'Show everything' : 'Gym view';
  $('gym-btn').setAttribute('aria-pressed', on ? 'true' : 'false');
  if (on && location.hash !== '#gym') history.replaceState(null, '', '#gym');
  if (!on && location.hash === '#gym') history.replaceState(null, '', location.pathname + location.search);
  window.scrollTo(0, 0);
  if (!on) redraw();
}
$('gym-btn').addEventListener('click', function(){ setGym(!document.body.classList.contains('gym')); });
window.addEventListener('hashchange', function(){ setGym(location.hash === '#gym'); });
if (location.hash === '#gym') setGym(true);
document.addEventListener('visibilitychange', function(){ if (!document.hidden && wantAwake) keepAwake(true); if (!document.hidden) loadCoach(false); });
$('px-sel').addEventListener('change', function(){ pxSel = this.value; renderProgress(); });
$('wk-kcal-use').addEventListener('click', useKcal);
$('p-save').addEventListener('click', saveProfile);
$('p-add-goal').addEventListener('click', function(){ readGoals(); goalsDraft.push({measure: 'waist', target: null}); renderGoalsEditor(); });
$('co-note-add').addEventListener('click', addNote);
$('cardio-form').addEventListener('submit', addCardio);
$('lab-form').addEventListener('submit', addLab);
$('l-marker').addEventListener('change', labMarkerChanged);
$('c-date').value = todayStr(); $('l-date').value = todayStr(); $('ph-date').value = todayStr();
$('ph-file').addEventListener('change', function(){ var f = $('ph-file').files[0]; if (f) uploadPhoto(f); });
$('ph-cpose').addEventListener('change', renderPhotos);
$('ph-a').addEventListener('change', renderPair);
$('ph-b').addEventListener('change', renderPair);
(function(){
  var g = $('p-goal'); opt(g, '', 'Not set', false);
  GOAL_KINDS.forEach(function(x){ opt(g, x[0], x[1], false); });
  var days = $('p-days');
  WEEKDAYS.forEach(function(d){
    var lb = el('label', 'day-chk'), cb = document.createElement('input'); cb.type = 'checkbox'; cb.id = 'p-day-' + d;
    lb.appendChild(cb); lb.appendChild(document.createTextNode(' ' + d.charAt(0).toUpperCase() + d.slice(1))); days.appendChild(lb);
  });
})();
if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(function(){});

var rafId = 0;
function redraw(){ if (rafId) return; rafId = requestAnimationFrame(function(){ rafId = 0; drawCharts(); renderProgress(); }); }
if (window.ResizeObserver){
  var ro = new ResizeObserver(redraw);
  ro.observe($('ch-weight')); ro.observe($('ch-waist')); ro.observe($('ch-px')); ro.observe($('ch-bf'));
} else { window.addEventListener('resize', redraw); }

fillTargets(); renderDerived(); renderWorkout();
connect();
})();
