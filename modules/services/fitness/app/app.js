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
  var map = {weight:'f-weight', waist:'f-waist', kcal:'f-kcal', protein:'f-protein', steps:'f-steps', sleep:'f-sleep'};
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
  var next = Object.assign({}, docs[d] || {});
  next.date = d;
  next.workout = wsel;
  next.sets = Object.assign({}, next.sets || {}, collected);
  docs[d] = next;
  saveDoc(d, next, 'st-workout', 'Workout saved').then(updateDelete);
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
  var h = num($('t-height').value), sw = num($('t-start').value);
  if (h) s.height = h;
  if (sw) s.start_weight = sw;
  settings = Object.assign({}, DEF, s);
  saveDoc('settings', s, 'st-targets', 'Saved');
}

/* ---------- forms ---------- */
function fillForm(){
  var d = docs[sel] || {};
  ['weight','waist','kcal','protein','steps','sleep'].forEach(function(k){ $('f-' + k).value = d[k] != null ? d[k] : ''; });
  $('f-note').value = d.note || '';
  setStatus('st-day', '');
  disarmDelete(); updateDelete();
}
function fillTargets(){
  ['kcal','protein','steps','sleep','workouts','rest'].forEach(function(k){ $('t-' + k).value = settings[k]; });
  $('t-height').value = settings.height != null ? settings.height : '';
  $('t-start').value = settings.start_weight != null ? settings.start_weight : '';
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
  var host = $(hostId), ro = $(roId);
  var pts = series(key);
  host.textContent = '';
  if (!pts.length){
    var e = document.createElement('div'); e.className = 'empty'; e.textContent = emptyMsg; host.appendChild(e);
    ro.textContent = ''; return;
  }
  var W = Math.max(host.clientWidth || 340, 240), H = 200;
  var t = dayNum(todayStr());
  var d0 = Math.min(pts[0].d, t - 13), d1 = Math.max(pts[pts.length - 1].d, t);
  var avg = avgSeries(pts);
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
  host.innerHTML = '<svg viewBox="0 0 ' + W + ' ' + H + '" width="100%" role="img" aria-label="' + unit + ' over time with 7-day average">' + s + '</svg>';
  function text(i){ return fmtDay(pts[i].date) + ' · ' + fmt(pts[i].v, 1) + ' ' + unit + ' · 7-day avg ' + fmt(avg[i].v, 1); }
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
  var all = last.sets.length >= ex.sets && last.sets.every(function(s){ return s[1] >= ex.hi; });
  var tip = all ? (ex.u === 'kg' ? ' All sets at the top of the range, so add a little weight.' : ' Top of the range on every set, so make it harder.') : (ex.u === 'kg' ? ' Keep the weight and aim for more reps.' : '');
  return 'Last, ' + fmtDay(last.date) + ': ' + parts.join(' · ') + suffix + '.' + tip;
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
    var nm = document.createElement('span'); nm.className = 'nm'; nm.textContent = ex.n;
    var tg = document.createElement('span'); tg.className = 'tg';
    tg.textContent = ex.sets + ' sets · ' + (ex.u === 'sec' ? ex.lo + '–' + ex.hi + ' sec' : ex.lo + '–' + ex.hi + ' reps');
    head.appendChild(nm); head.appendChild(tg); box.appendChild(head);
    var last = lastFor(ex.k);
    if (last){ var h = document.createElement('p'); h.className = 'hint'; h.textContent = lastText(ex, last); box.appendChild(h); }
    var sets = document.createElement('div'); sets.className = 'sets';
    for (var i = 0; i < nSets(ex, saved); i++){
      var row = document.createElement('div'); row.className = 'set';
      var no = document.createElement('span'); no.className = 'no'; no.textContent = (i + 1);
      row.appendChild(no);
      var ls = last && last.sets[i] ? last.sets[i] : null, sv = saved[ex.k] && saved[ex.k][i] ? saved[ex.k][i] : null;
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
  hint.textContent = 'Workout ' + wsel + '. Renaming keeps an exercise\'s history; removing one hides it from the sheet but keeps what you logged.';
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
  renderHeader(); renderBars(); renderStats(); drawCharts(); renderHabits();
}

/* ---------- storage: server copy, offline cache, outbox ----------
   server/vers: the last copy and version the server confirmed for each id.
   outbox: unsent changes, id -> {op, data, orig, base, seq}. `orig` is the server
   copy the change was made against, used for a field-level merge on conflict.
   What the page shows is the server copy with the outbox laid over it. */
var server = {}, vers = {};
// Offline storage is per user: Authelia's cookie covers the whole domain, so a
// shared device can change users. Nothing is sent until the server has said who
// is signed in, and another user's unsent changes stay under their own key.
var user = loadJSON('fitness.user', null), confirmed = false;
function skey(k){ return 'fitness.' + k + '.' + (user || '_'); }
var outbox = loadJSON(skey('outbox'), {});
var chain = Promise.resolve(), netState = 'ok', serverSeen = false, typed = false;
document.addEventListener('input', function(){ typed = true; }, {once: true});

function loadJSON(k, d){ try { var v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch(e){ return d; } }
function saveJSON(k, v){ try { localStorage.setItem(k, JSON.stringify(v)); } catch(e){} }
function same(a, b){ return JSON.stringify(a == null ? null : a) === JSON.stringify(b == null ? null : b); }
function persist(){ saveJSON(skey('outbox'), outbox); saveJSON(skey('cache'), {server: server, vers: vers}); }
function idLabel(id){ return id === 'settings' ? 'Targets' : id === 'plan' ? 'Your plan' : fmtDay(id); }

function rebuild(){
  var view = Object.assign({}, server);
  Object.keys(outbox).forEach(function(id){ if (outbox[id].op === 'delete') delete view[id]; else view[id] = outbox[id].data; });
  settings = Object.assign({}, DEF, view.settings || {});
  var p = view.plan;
  PLAN = p && Array.isArray(p.A) && Array.isArray(p.B) && (p.A.length || p.B.length) ? p : DEFAULT_PLAN;
  delete view.settings; delete view.plan;
  docs = view;
  if (firstSnap){ firstSnap = false; wsel = suggestWorkout(sel); fillForm(); fillTargets(); renderWorkout(); }
  renderDerived(); updateDelete();
}

function queue(id, op, data){
  var e = outbox[id];
  if (!e) e = outbox[id] = {base: vers[id] || 0, orig: server[id] || null, seq: 0};
  e.op = op; e.data = data; e.seq++;
  persist();
  return flush();
}

function flush(){ if (!confirmed) return chain; chain = chain.then(drain); return chain; }
function drain(){
  return Object.keys(outbox).reduce(function(p, id){ return p.then(function(){ return sendOne(id, 0); }); }, Promise.resolve())
    .then(function(){ setNet('ok'); }, function(err){ setNet(err && err.auth ? 'auth' : 'offline'); });
}

function sendOne(id, tries){
  var e = outbox[id];
  if (!e) return Promise.resolve();
  var op = e.op, sent = e.data, seq = e.seq, base = e.base;
  var opts = {method: op === 'delete' ? 'DELETE' : 'PUT', redirect: 'manual', cache: 'no-store', headers: {'If-Match': String(base), 'X-Fitness-User': user}};
  if (op !== 'delete'){ opts.headers['Content-Type'] = 'application/json'; opts.body = JSON.stringify(sent); }
  return fetch('api/log/' + id, opts).then(function(r){
    if (r.type === 'opaqueredirect' || r.status === 401) throw {auth: true};
    // Someone else is signed in now: stop, and let load() switch users.
    if (r.status === 403){ confirmed = false; setTimeout(load, 0); throw {auth: true}; }
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
  return fetch('api/log', {cache: 'no-store', redirect: 'manual'}).then(function(r){
    if (r.type === 'opaqueredirect' || r.status === 401) throw {auth: true};
    if (!r.ok) throw {net: true};
    return r.json();
  }).then(function(j){
    if (j.user && j.user !== user){
      // A different user than this device's last one: switch to their own
      // copy and queue, and refill the forms from their data.
      user = j.user; saveJSON('fitness.user', user);
      outbox = loadJSON(skey('outbox'), {});
      serverSeen = false; typed = false;
    }
    confirmed = true;
    server = {}; vers = {};
    j.docs.forEach(function(x){ server[x.id] = x.data; vers[x.id] = x.version; });
    persist(); rebuild();
    // The forms were filled from the offline copy (or nothing); refresh them from
    // the first server answer unless the user has already started typing.
    if (!serverSeen){ serverSeen = true; if (!typed){ fillForm(); fillTargets(); renderWorkout(); } }
    if (Object.keys(outbox).length) return flush();
    setNet('ok');
  }, function(err){ setNet(err && err.auth ? 'auth' : 'offline'); });
}
// load() confirms the user first and then flushes the queue.
function sync(){ return load(); }

function connect(){
  var c = loadJSON(skey('cache'), null);
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
  tickRest();
  if (!restTick) restTick = setInterval(tickRest, 250);
}
function tickRest(){
  var left = Math.ceil((restEnd - Date.now()) / 1000);
  if (left > 0){ $('rest-t').textContent = Math.floor(left / 60) + ':' + pad(left % 60); return; }
  clearInterval(restTick); restTick = 0;
  $('rest').classList.add('done'); $('rest-l').textContent = 'Next set'; $('rest-t').textContent = 'Go';
  buzz();
  restHide = setTimeout(restStop, 6000);
}
function restStop(){
  clearInterval(restTick); restTick = 0; clearTimeout(restHide);
  $('rest').hidden = true; document.body.classList.remove('resting');
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
if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(function(){});

var rafId = 0;
function redraw(){ if (rafId) return; rafId = requestAnimationFrame(function(){ rafId = 0; drawCharts(); }); }
if (window.ResizeObserver){
  var ro = new ResizeObserver(redraw);
  ro.observe($('ch-weight')); ro.observe($('ch-waist'));
} else { window.addEventListener('resize', redraw); }

fillTargets(); renderDerived(); renderWorkout();
connect();
})();
