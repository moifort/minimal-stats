/* Stats landing page: the live widgets, the popover's figures, reveal on
   scroll, the latest version. Started by i18n.js once the texts are in. */
(() => {
  "use strict";

  // The Mac App Store page, once Stats is there: the badges stay hidden until
  // then (docs/app-store.md). e.g. "https://apps.apple.com/app/id0000000000?mt=12"
  const APP_STORE_URL = null;

  const texts = (window.STATS_I18N && window.STATS_I18N.text) || {};
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ---------------------------------------------------------------------------
  // Simulated readings: calm, with now and then a burst, like a working Mac.
  // ---------------------------------------------------------------------------

  const points = 60;
  const cpu = [], netIn = [], netOut = [];
  let cpuNow = 18, burst = 0;
  const step = () => {
    if (burst > 0) burst -= 1;
    else if (Math.random() < 0.05) burst = 3 + Math.floor(Math.random() * 4);
    const target = burst > 0 ? 35 + Math.random() * 40 : 6 + Math.random() * 10;
    cpuNow += (target - cpuNow) * 0.35;
    cpu.push(cpuNow);
    const download = burst > 0 && Math.random() < 0.6 ? 2e6 + Math.random() * 6e6 : 4e4 + Math.random() * 2.6e5;
    netIn.push(download);
    netOut.push(download * (0.08 + Math.random() * 0.2));
    for (const series of [cpu, netIn, netOut]) if (series.length > points) series.shift();
  };
  for (let i = 0; i < points; i += 1) step();
  let memory = 0.69;
  const disk = 280 / 494;

  // ---------------------------------------------------------------------------
  // The four widgets, drawn as the app draws them: one colour, the menu bar's.
  // ---------------------------------------------------------------------------

  const ink = () => getComputedStyle(document.documentElement).getPropertyValue("--chart").trim() || "#1d1d1f";

  const draw = {
    cpu(ctx, w, h, color) {
      const s = h / 22, top = 2 * s, bottom = h - 2 * s;
      const y = (v) => bottom - (bottom - top) * Math.min(v, 100) / 100;
      const x = (i) => (w - 1) * i / (cpu.length - 1);
      ctx.beginPath();
      cpu.forEach((v, i) => (i ? ctx.lineTo(x(i), y(v)) : ctx.moveTo(x(i), y(v))));
      ctx.lineTo(w, bottom); ctx.lineTo(0, bottom); ctx.closePath();
      ctx.fillStyle = color; ctx.fill();
      // The scale's floor, as on the widget.
      ctx.globalAlpha = 0.35; ctx.fillRect(0, bottom, w, Math.max(1, 0.8 * s)); ctx.globalAlpha = 1;
    },
    net(ctx, w, h, color) {
      // Mirrored as in the app: upload hangs from the top edge, download rises
      // from the bottom edge, on one square-root scale (light traffic stays
      // visible after a burst).
      const s = h / 22, top = 2 * s, bottom = h - 2 * s, half = (bottom - top) / 2;
      const peak = Math.sqrt(Math.max(...netIn, ...netOut, 1e5));
      const x = (i) => (w - 1) * i / (netIn.length - 1);
      const area = (series, edge, sign) => {
        ctx.beginPath(); ctx.moveTo(0, edge);
        series.forEach((v, i) => ctx.lineTo(x(i), edge + sign * half * Math.sqrt(v) / peak));
        ctx.lineTo(w, edge); ctx.closePath(); ctx.fill();
      };
      ctx.fillStyle = color;
      area(netOut, top, 1);
      area(netIn, bottom, -1);
    },
    mem(ctx, w, h, color) {
      // A pill, filled from the bottom to the share in use, as on the widget.
      const s = h / 22, box = { x: s, y: 2 * s, w: w - 2 * s, h: h - 4 * s }, r = Math.min(box.w / 2, 3 * s);
      ctx.fillStyle = color;
      ctx.globalAlpha = 0.3; ctx.beginPath(); ctx.roundRect(box.x, box.y, box.w, box.h, r); ctx.fill(); ctx.globalAlpha = 1;
      ctx.save(); ctx.beginPath(); ctx.roundRect(box.x, box.y, box.w, box.h, r); ctx.clip();
      ctx.fillRect(box.x, box.y + box.h * (1 - memory), box.w, box.h * memory); ctx.restore();
    },
    disk(ctx, w, h, color) {
      const s = h / 22, cx = w / 2, cy = h / 2, r = Math.min(w, h) / 2 - 2.5 * s;
      ctx.fillStyle = color;
      ctx.globalAlpha = 0.3; ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.fill(); ctx.globalAlpha = 1;
      ctx.beginPath(); ctx.moveTo(cx, cy);
      ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * disk); ctx.closePath(); ctx.fill();
    },
  };

  const canvases = [...document.querySelectorAll("canvas[data-widget]")];
  const ratio = Math.min(window.devicePixelRatio || 1, 2);
  for (const canvas of canvases) {
    canvas.dataset.w = canvas.width; canvas.dataset.h = canvas.height;
    canvas.width = canvas.dataset.w * ratio; canvas.height = canvas.dataset.h * ratio;
  }
  const paint = () => {
    const color = ink();
    for (const canvas of canvases) {
      const ctx = canvas.getContext("2d");
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
      ctx.clearRect(0, 0, canvas.dataset.w, canvas.dataset.h);
      draw[canvas.dataset.widget](ctx, +canvas.dataset.w, +canvas.dataset.h, color);
    }
  };

  // ---------------------------------------------------------------------------
  // The popover's live figures, formatted as the app formats them.
  // ---------------------------------------------------------------------------

  const bytes = (value, base = 1000) => {
    const units = ["B", "KB", "MB", "GB", "TB"];
    let v = Math.max(value, 0), unit = 0;
    while (v >= base && unit < units.length - 1) { v /= base; unit += 1; }
    return v.toFixed(unit === 0 || v >= 100 ? 0 : 1) + units[unit];
  };
  const live = (name) => document.querySelector(`[data-live="${name}"]`);
  const figures = () => {
    live("cpu").textContent = `${Math.round(cpu[cpu.length - 1])}%`;
    live("mem").textContent = `${bytes(memory * 16 * 1024 ** 3, 1024)} / 16GB`;
    live("net").innerHTML = `↓ ${bytes(netIn[netIn.length - 1])}/s&nbsp;&nbsp;↑ ${bytes(netOut[netOut.length - 1])}/s`;
  };

  const tick = () => {
    step();
    memory = Math.min(0.82, Math.max(0.6, memory + (Math.random() - 0.5) * 0.01));
    paint(); figures();
  };
  paint(); figures();
  // The app refreshes every two seconds; the page too, while it is visible.
  if (!reducedMotion) setInterval(() => { if (!document.hidden) tick(); }, 2000);
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", paint);

  // ---------------------------------------------------------------------------
  // App Store, reveal on scroll, latest version
  // ---------------------------------------------------------------------------

  if (APP_STORE_URL) {
    for (const badge of document.querySelectorAll("[data-app-store]")) {
      badge.href = APP_STORE_URL;
      badge.hidden = false;
    }
  }

  for (const el of document.querySelectorAll(".card, .faq-list details, .section-title, .section-lead")) {
    el.classList.add("reveal");
  }
  const revealer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) { entry.target.classList.add("in"); revealer.unobserve(entry.target); }
    }
  }, { threshold: 0.15 });
  for (const el of document.querySelectorAll(".reveal")) revealer.observe(el);

  // The GitHub API is public for this; failing silently keeps the generic label.
  // The download links already point at releases/latest/download/Stats.dmg.
  fetch("https://api.github.com/repos/moifort/minimal-stats/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
    .then((r) => (r.ok ? r.json() : null))
    .then((release) => {
      if (!release || !release.tag_name) return;
      const version = release.tag_name.replace(/^v/, "");
      for (const el of document.querySelectorAll("[data-version]")) el.textContent = (texts.version || "Version {v}").replace("{v}", version);
      for (const el of document.querySelectorAll("[data-version-short]")) el.textContent = `v${version}`;
    })
    .catch(() => {});
})();
