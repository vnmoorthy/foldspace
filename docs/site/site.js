// FOLDSPACE landing page. Starfield, nav, reveals, count-ups, the scroll-driven
// iPhone Duo mockup (three.js Earth in the top screen), and the gameplay carousel.
// three.js is imported dynamically so the page still works without WebGL/CDN.

const REDUCED = matchMedia("(prefers-reduced-motion: reduce)").matches;
const root = document.documentElement;
const $ = (s) => document.querySelector(s);

/* ---------------------------------------------------------------- starfield */
const starCanvas = $("#stars");
function drawStars() {
  const dpr = Math.min(devicePixelRatio || 1, 2), w = innerWidth, h = innerHeight;
  starCanvas.width = w * dpr; starCanvas.height = h * dpr;
  const g = starCanvas.getContext("2d");
  g.scale(dpr, dpr);
  let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const n = Math.round(w * h / 2600);
  for (let i = 0; i < n; i++) {
    const b = Math.pow(rnd(), 3), r = b > .8 ? 1.1 : .6;
    g.fillStyle = `rgba(${220 + rnd() * 35 | 0},${230 + rnd() * 25 | 0},255,${.18 + b * .7})`;
    g.beginPath(); g.arc(rnd() * w, rnd() * h, r, 0, Math.PI * 2); g.fill();
  }
}
drawStars();
let starT; addEventListener("resize", () => { clearTimeout(starT); starT = setTimeout(drawStars, 150); });

/* ---------------------------------------------------------------- nav */
const nav = $("#nav");
const onNav = () => nav.classList.toggle("solid", scrollY > 40);
addEventListener("scroll", onNav, { passive: true }); onNav();

/* ---------------------------------------------------------------- reveals + count-ups */
const fmt = (v, dec) => v.toLocaleString("en-US", { minimumFractionDigits: dec, maximumFractionDigits: dec });
function countUp(el) {
  const to = parseFloat(el.dataset.count), dec = +(el.dataset.dec || 0);
  if (REDUCED) { el.textContent = fmt(to, dec); return; }
  const t0 = performance.now(), dur = 2200;
  const step = (t) => {
    const k = Math.min(1, (t - t0) / dur), e = 1 - Math.pow(1 - k, 4);
    el.textContent = fmt(to * e, dec);
    if (k < 1) requestAnimationFrame(step);
  };
  el.textContent = fmt(0, dec);
  requestAnimationFrame(step);
}
const io = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (!e.isIntersecting) continue;
    const el = e.target;
    if (el.dataset.count) countUp(el); else el.classList.add(el.classList.contains("move") ? "seen" : "in");
    io.unobserve(el);
  }
}, { rootMargin: "0px 0px -10% 0px", threshold: 0.1 });
document.querySelectorAll(".reveal, .move, [data-count]").forEach((el) => io.observe(el));

/* ---------------------------------------------------------------- hero video */
const video = $("#heroVideo");
if (video && !REDUCED) { const p = video.play(); if (p && p.catch) p.catch(() => {}); }

/* ---------------------------------------------------------------- device: hinge follows scroll */
const deviceSec = $("#device"), duo = $("#duo");
const els = { deg: $("#hingeDeg"), post: $("#hingePosture"), hudDeg: $("#hudDeg"), hudPost: $("#hudPosture"), bar: $("#hudBar"), veil: $("#warpVeil"), open: $("#lineOpen"), close: $("#lineClose") };
const posture = (a) => a < 12 ? "Closed" : a < 45 ? "Squeezed" : a < 135 ? "Cockpit" : a < 170 ? "Open" : "Flat";
const smooth = (x) => x * x * (3 - 2 * x);
const hinge = { angle: 112 };
function hingeAt(p) {
  // 0–.3 open from cockpit to wide · .3–.45 hold · .45–.9 close smoothly to warp · then closed
  if (p < .3) return 100 + smooth(p / .3) * 55;
  if (p < .45) return 155;
  if (p < .9) return 155 - smooth((p - .45) / .45) * 153;
  return 2;
}
let shown = null;
function updateHinge() {
  const r = deviceSec.getBoundingClientRect();
  const p = Math.min(1, Math.max(0, -r.top / (r.height - innerHeight)));
  const a = hingeAt(p);
  hinge.angle = a;
  duo.style.setProperty("--hinge", a.toFixed(2));
  const ai = Math.round(a);
  if (ai !== shown) {
    shown = ai;
    const post = posture(ai);
    els.deg.textContent = els.hudDeg.textContent = ai + "°";
    els.post.textContent = post; els.hudPost.textContent = post.toUpperCase();
    // bubble stability: closing speed is ideal in the mid band
    els.bar.setAttribute("width", p > .45 && p < .9 ? 200 : 60 + (ai - 60) * .6);
    els.veil.style.opacity = ai < 50 ? String(Math.min(1, (50 - ai) / 25)) : "0";
    const closing = p > .42;
    els.open.classList.toggle("off", closing); els.close.classList.toggle("off", !closing);
  }
}
let hTick = false;
addEventListener("scroll", () => { if (!hTick) { hTick = true; requestAnimationFrame(() => { hTick = false; updateHinge(); }); } }, { passive: true });
addEventListener("resize", updateHinge);
updateHinge();

/* ---------------------------------------------------------------- WebGL Earth in the top screen */
function hasWebGL() {
  try { const c = document.createElement("canvas"); return !!(window.WebGLRenderingContext && (c.getContext("webgl2") || c.getContext("webgl"))); }
  catch { return false; }
}
const noWebGL = () => root.classList.add("no-webgl");
if (!hasWebGL()) noWebGL();
else {
  const start = () => import("three").then(earthScene).catch((e) => { console.warn("three.js unavailable, using render", e); noWebGL(); });
  const lazy = new IntersectionObserver((en) => { if (en[0].isIntersecting) { lazy.disconnect(); start(); } }, { rootMargin: "400px 0px" });
  lazy.observe(deviceSec);
}

function earthScene(THREE) {
  const canvas = $("#earthCanvas"), screen = $("#gameScreen");
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
  renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2));
  renderer.setClearColor(0x000000, 1);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(30, 1.8, 0.1, 400);
  const tex = (u) => { const t = new THREE.TextureLoader().load(u); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4; return t; };

  const earth = new THREE.Mesh(new THREE.SphereGeometry(1, 96, 96), new THREE.MeshStandardMaterial({
    map: tex("site/planet-earth.jpg"), emissiveMap: tex("site/planet-earth-emissive.png"),
    emissive: new THREE.Color(0xffc27a), emissiveIntensity: 0.5, roughness: 0.85, metalness: 0,
  }));
  earth.rotation.z = THREE.MathUtils.degToRad(23.4);
  scene.add(earth);
  const atm = new THREE.Mesh(new THREE.SphereGeometry(1.07, 64, 64), new THREE.ShaderMaterial({
    vertexShader: `varying vec3 vN; varying vec3 vV; void main(){ vec4 mv = modelViewMatrix*vec4(position,1.); vN = normalize(normalMatrix*normal); vV = normalize(-mv.xyz); gl_Position = projectionMatrix*mv; }`,
    fragmentShader: `varying vec3 vN; varying vec3 vV; void main(){ float f = pow(1.-abs(dot(vN,vV)), 3.); gl_FragColor = vec4(vec3(.35,.62,1.)*f*1.4, f); }`,
    blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, side: THREE.BackSide,
  }));
  scene.add(atm);
  // stars
  const n = 1800, pos = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) { const u = Math.random() * 2 - 1, t = Math.random() * 6.283, s = Math.sqrt(1 - u * u), r = 80 + Math.random() * 60; pos.set([r * s * Math.cos(t), r * u, r * s * Math.sin(t)], i * 3); }
  const sg = new THREE.BufferGeometry(); sg.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  scene.add(new THREE.Points(sg, new THREE.PointsMaterial({ size: 1.3, sizeAttenuation: false, color: 0xdfe8ff, transparent: true, opacity: .8 })));
  const sun = new THREE.DirectionalLight(0xffffff, 3.2); sun.position.set(-4, 1.5, 4);
  scene.add(sun, new THREE.AmbientLight(0x223344, 0.2));

  const resize = () => {
    const w = screen.clientWidth, h = screen.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h, false); camera.aspect = w / h; camera.updateProjectionMatrix();
  };
  new ResizeObserver(resize).observe(screen); resize();

  let active = false, last = performance.now();
  function frame(now) {
    if (!active) return;
    const dt = Math.min(.05, (now - last) / 1000); last = now;
    if (!REDUCED) earth.rotation.y += dt * .12;
    // hologram camera: pitch follows the hinge angle, as in SpaceScene
    const el = THREE.MathUtils.degToRad((hinge.angle - 110) * .45);
    camera.position.set(0, Math.sin(el) * 4.3, Math.cos(el) * 4.3);
    camera.lookAt(0, 0, 0);
    renderer.render(scene, camera);
    requestAnimationFrame(frame);
  }
  new IntersectionObserver((en) => {
    const v = en[0].isIntersecting;
    if (v && !active) { active = true; last = performance.now(); requestAnimationFrame(frame); }
    else if (!v) active = false;
  }).observe(deviceSec);
}

/* ---------------------------------------------------------------- gameplay carousel */
(function carousel() {
  const sec = $("#gameplay"), label = $("#carLabel");
  let slides = [...document.querySelectorAll(".slide")];
  let i = 0, timer = null, settled = 0;
  const show = (k) => {
    if (!slides.length) return;
    i = (k + slides.length) % slides.length;
    slides.forEach((s, j) => s.classList.toggle("on", j === i));
    label.textContent = slides[i].querySelector("figcaption").textContent;
  };
  const done = () => {
    if (++settled < 7) return;
    slides = slides.filter((s) => s.isConnected);
    if (!slides.length) {
      sec.classList.add("empty");
      const w = $("#watchBtn"); if (w) w.setAttribute("href", "#device");
      return;
    }
    show(0);
    if (!REDUCED && slides.length > 1) timer = setInterval(() => show(i + 1), 4000);
  };
  slides.forEach((s) => {
    const img = s.querySelector("img");
    const bad = () => { s.remove(); done(); };
    if (img.complete) { img.naturalWidth ? done() : bad(); }
    else { img.addEventListener("load", done, { once: true }); img.addEventListener("error", bad, { once: true }); }
  });
  const user = (d) => { clearInterval(timer); timer = null; show(i + d); };
  $("#prev").addEventListener("click", () => user(-1));
  $("#next").addEventListener("click", () => user(1));
})();
