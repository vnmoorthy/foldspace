// FOLDSPACE landing page: nav, reveals, parallax, and two three.js scenes
// (Earth under the fold line, and the Solar System). three.js is imported
// dynamically so the page still works if the CDN or WebGL is unavailable.

const REDUCED = matchMedia("(prefers-reduced-motion: reduce)").matches;
const root = document.documentElement;

/* ---------------------------------------------------------------- nav */
const nav = document.getElementById("nav");
const onNav = () => nav.classList.toggle("solid", scrollY > 40);
addEventListener("scroll", onNav, { passive: true });
onNav();

/* ---------------------------------------------------------------- reveals */
const revealIO = new IntersectionObserver((entries) => {
  for (const e of entries) if (e.isIntersecting) { e.target.classList.add("in"); revealIO.unobserve(e.target); }
}, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
document.querySelectorAll(".reveal").forEach((el) => revealIO.observe(el));

/* ---------------------------------------------------------------- parallax */
const parallax = [...document.querySelectorAll(".parallax")];
let ticking = false;
function doParallax() {
  ticking = false;
  const vh = innerHeight;
  for (const el of parallax) {
    const r = el.parentElement.getBoundingClientRect();
    if (r.bottom < -vh || r.top > vh * 2) continue;
    const off = (r.top + r.height / 2 - vh / 2) * -Number(el.dataset.speed || 0.15);
    el.style.transform = `translate3d(0, ${off.toFixed(1)}px, 0)`;
  }
}
if (!REDUCED) {
  addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(doParallax); } }, { passive: true });
  doParallax();
}

/* ---------------------------------------------------------------- hero video safety */
const video = document.getElementById("heroVideo");
if (video && !REDUCED) {
  const p = video.play();
  if (p && p.catch) p.catch(() => { /* autoplay blocked: poster stays */ });
}

/* ---------------------------------------------------------------- WebGL */
function hasWebGL() {
  try {
    const c = document.createElement("canvas");
    return !!(window.WebGLRenderingContext && (c.getContext("webgl2") || c.getContext("webgl")));
  } catch { return false; }
}
function noWebGL() { root.classList.add("no-webgl"); }

if (!hasWebGL()) noWebGL();
else {
  import("three").then((THREE) => {
    lazyScene(document.getElementById("earthStage"), () => earthScene(THREE));
    lazyScene(document.getElementById("solarStage"), () => solarScene(THREE));
  }).catch((err) => { console.warn("three.js unavailable, using renders", err); noWebGL(); });
}

// Start a scene when its stage nears the viewport; run its loop only while visible.
function lazyScene(stage, factory) {
  let scene = null, visible = false;
  const io = new IntersectionObserver((entries) => {
    visible = entries[0].isIntersecting;
    if (visible && !scene) {
      try { scene = factory(); } catch (e) { console.warn(e); noWebGL(); io.disconnect(); return; }
    }
    if (scene) scene.setActive(visible);
  }, { rootMargin: "200px 0px" });
  io.observe(stage);
}

function makeRenderer(THREE, canvas) {
  const r = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false, powerPreference: "high-performance" });
  r.setPixelRatio(Math.min(devicePixelRatio || 1, 2));
  r.setClearColor(0x000000, 1);
  r.outputColorSpace = THREE.SRGBColorSpace;
  return r;
}

function loadTex(THREE, url, srgb = true) {
  const t = new THREE.TextureLoader().load(url);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}

function starfield(THREE, count, rMin, rMax) {
  const pos = new Float32Array(count * 3), col = new Float32Array(count * 3);
  for (let i = 0; i < count; i++) {
    const u = Math.random() * 2 - 1, th = Math.random() * Math.PI * 2, s = Math.sqrt(1 - u * u);
    const r = rMin + Math.random() * (rMax - rMin);
    pos.set([r * s * Math.cos(th), r * u, r * s * Math.sin(th)], i * 3);
    const b = 0.35 + 0.65 * Math.pow(Math.random(), 2.5);
    col.set([b * (0.85 + Math.random() * 0.15), b * 0.93, b], i * 3);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  g.setAttribute("color", new THREE.BufferAttribute(col, 3));
  return new THREE.Points(g, new THREE.PointsMaterial({ size: 1.6, sizeAttenuation: false, vertexColors: true, transparent: true, opacity: 0.9, depthWrite: false }));
}

// Canvas-generated soft horizontal glow strip for the cyan fold line.
function glowTexture(THREE) {
  const c = document.createElement("canvas"); c.width = 512; c.height = 64;
  const g = c.getContext("2d");
  const v = g.createLinearGradient(0, 0, 0, 64);
  v.addColorStop(0, "rgba(61,242,255,0)"); v.addColorStop(0.5, "rgba(61,242,255,1)"); v.addColorStop(1, "rgba(61,242,255,0)");
  g.fillStyle = v; g.fillRect(0, 0, 512, 64);
  g.globalCompositeOperation = "destination-in";
  const h = g.createLinearGradient(0, 0, 512, 0);
  h.addColorStop(0, "rgba(0,0,0,0)"); h.addColorStop(0.15, "rgba(0,0,0,1)"); h.addColorStop(0.85, "rgba(0,0,0,1)"); h.addColorStop(1, "rgba(0,0,0,0)");
  g.fillStyle = h; g.fillRect(0, 0, 512, 64);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function atmosphere(THREE, radius, color, power = 3.2, strength = 1.0) {
  return new THREE.Mesh(
    new THREE.SphereGeometry(radius, 64, 64),
    new THREE.ShaderMaterial({
      uniforms: { c: { value: new THREE.Color(color) }, p: { value: power }, s: { value: strength } },
      vertexShader: `varying vec3 vN; varying vec3 vV;
        void main(){ vec4 mv = modelViewMatrix * vec4(position,1.0);
          vN = normalize(normalMatrix * normal); vV = normalize(-mv.xyz);
          gl_Position = projectionMatrix * mv; }`,
      fragmentShader: `uniform vec3 c; uniform float p; uniform float s; varying vec3 vN; varying vec3 vV;
        void main(){ float f = pow(1.0 - abs(dot(vN, vV)), p);
          gl_FragColor = vec4(c * f * s, f); }`,
      blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, side: THREE.BackSide,
    })
  );
}

function sizeLoop(renderer, camera, canvas, onResize) {
  const resize = () => {
    const w = canvas.clientWidth, h = canvas.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    onResize && onResize(w, h);
    camera.updateProjectionMatrix();
  };
  new ResizeObserver(resize).observe(canvas);
  resize();
  return resize;
}

/* ---------------------------------------------------------------- Earth + fold line */
function earthScene(THREE) {
  const canvas = document.getElementById("earthCanvas");
  const section = document.getElementById("hinge");
  const degEl = document.getElementById("hingeDeg"), postureEl = document.getElementById("hingePosture");
  const renderer = makeRenderer(THREE, canvas);
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(32, 1, 0.1, 400);

  const earth = new THREE.Mesh(
    new THREE.SphereGeometry(1, 96, 96),
    new THREE.MeshStandardMaterial({
      map: loadTex(THREE, "site/planet-earth.jpg"),
      emissiveMap: loadTex(THREE, "site/planet-earth-emissive.png"),
      emissive: new THREE.Color(0xffc27a), emissiveIntensity: 0.55,
      roughness: 0.85, metalness: 0,
    })
  );
  earth.rotation.z = THREE.MathUtils.degToRad(23.4);
  const tiltGroup = new THREE.Group();
  tiltGroup.add(earth);
  tiltGroup.add(atmosphere(THREE, 1.06, 0x5aa8ff, 3.0, 1.3));
  scene.add(tiltGroup);
  scene.add(starfield(THREE, 2600, 60, 160));

  const sun = new THREE.DirectionalLight(0xffffff, 3.4);
  sun.position.set(4, 1.2, 4.5);
  scene.add(sun, new THREE.AmbientLight(0x223344, 0.25));

  // Fold line: faces the camera, passes through Earth's centre, drawn over it.
  const fold = new THREE.Group();
  const core = new THREE.Mesh(new THREE.PlaneGeometry(30, 0.008), new THREE.MeshBasicMaterial({ color: 0xeaffff, transparent: true, opacity: 0.95, depthTest: false, blending: THREE.AdditiveBlending }));
  const glow = new THREE.Mesh(new THREE.PlaneGeometry(30, 0.14), new THREE.MeshBasicMaterial({ map: glowTexture(THREE), transparent: true, opacity: 0.85, depthTest: false, depthWrite: false, blending: THREE.AdditiveBlending }));
  core.renderOrder = glow.renderOrder = 10;
  fold.add(glow, core);
  scene.add(fold);

  let mobile = false;
  sizeLoop(renderer, camera, canvas, (w, h) => {
    mobile = w < 800;
    // shift the frame so Earth sits left (desktop) or high (mobile)
    if (mobile) camera.setViewOffset(w, h, 0, h * 0.2, w, h);
    else camera.setViewOffset(w, h, w * 0.2, 0, w, h);
  });

  const posture = (a) => a < 12 ? "Closed" : a < 45 ? "Squeezed" : a < 135 ? "Cockpit" : a < 170 ? "Open" : "Flat";
  let angle = 112, shown = -1;
  function hingeFromScroll() {
    const r = section.getBoundingClientRect();
    const p = Math.min(1, Math.max(0, (innerHeight - r.top) / (innerHeight + r.height)));
    angle = 178 - p * 118; // flat → cockpit → squeezed as you scroll through
  }

  let active = false, last = performance.now();
  function frame(now) {
    if (!active) return;
    const dt = Math.min(0.05, (now - last) / 1000); last = now;
    hingeFromScroll();
    if (!REDUCED) earth.rotation.y += dt * 0.08;
    const el = THREE.MathUtils.degToRad((angle - 110) * 0.55); // camera elevation follows the hinge
    const d = mobile ? 7.4 : 6.4;
    camera.position.set(0, Math.sin(el) * d, Math.cos(el) * d);
    camera.lookAt(0, 0, 0);
    fold.quaternion.copy(camera.quaternion);
    const a = Math.round(angle);
    if (a !== shown) { shown = a; degEl.textContent = a + "°"; postureEl.textContent = posture(a); }
    renderer.render(scene, camera);
    requestAnimationFrame(frame);
  }
  return {
    setActive(v) {
      if (v === active) return;
      active = v;
      if (v) { last = performance.now(); requestAnimationFrame(frame); }
    },
  };
}

/* ---------------------------------------------------------------- Solar System */
const PLANETS = [
  { id: "mercury", name: "Mercury", au: 0.39, r: 0.30, orbit: 3.0,  fact: "0.39 AU · the innermost world" },
  { id: "venus",   name: "Venus",   au: 0.72, r: 0.51, orbit: 4.3,  fact: "0.72 AU · clouded in sulphuric acid" },
  { id: "earth",   name: "Earth",   au: 1.00, r: 0.54, orbit: 5.7,  fact: "1.00 AU · home" },
  { id: "mars",    name: "Mars",    au: 1.52, r: 0.39, orbit: 7.1,  fact: "1.52 AU · a warp-drive part is hidden here" },
  { id: "jupiter", name: "Jupiter", au: 5.20, r: 1.50, orbit: 10.0, fact: "5.20 AU · a warp-drive part is hidden here" },
  { id: "saturn",  name: "Saturn",  au: 9.58, r: 1.26, orbit: 13.2, fact: "9.58 AU · rings of ice", ring: true },
  { id: "uranus",  name: "Uranus",  au: 19.2, r: 0.84, orbit: 16.0, fact: "19.2 AU · rolls on its side", tilt: 97.8 },
  { id: "neptune", name: "Neptune", au: 30.1, r: 0.81, orbit: 18.6, fact: "30.1 AU · a warp-drive part is hidden here" },
];

function ringTexture(THREE) {
  const c = document.createElement("canvas"); c.width = 512; c.height = 8;
  const g = c.getContext("2d");
  for (let x = 0; x < 512; x++) {
    const t = x / 511;
    const band = 0.55 + 0.45 * Math.sin(t * 60) * Math.sin(t * 13 + 1);
    const gap = t > 0.62 && t < 0.67 ? 0.08 : 1; // Cassini-like division
    const a = Math.max(0, Math.min(1, band * gap * (t < 0.04 ? t / 0.04 : 1) * (t > 0.95 ? (1 - t) / 0.05 : 1)));
    g.fillStyle = `rgba(${210 + 30 * band | 0},${190 + 25 * band | 0},${160 + 20 * band | 0},${(a * 0.8).toFixed(3)})`;
    g.fillRect(x, 0, 1, 8);
  }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function radialTexture(THREE) {
  const c = document.createElement("canvas"); c.width = c.height = 256;
  const g = c.getContext("2d");
  const r = g.createRadialGradient(128, 128, 0, 128, 128, 128);
  r.addColorStop(0, "rgba(255,255,255,1)"); r.addColorStop(0.2, "rgba(255,255,255,.45)");
  r.addColorStop(0.5, "rgba(255,255,255,.08)"); r.addColorStop(1, "rgba(255,255,255,0)");
  g.fillStyle = r; g.fillRect(0, 0, 256, 256);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function solarScene(THREE) {
  const canvas = document.getElementById("solarCanvas");
  const tip = document.getElementById("planetTip");
  const renderer = makeRenderer(THREE, canvas);
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(38, 1, 0.1, 600);
  scene.add(starfield(THREE, 3000, 120, 300));

  // Sun: photosphere texture (emissive) + corona sprite
  const sunR = 1.7;
  const sun = new THREE.Mesh(new THREE.SphereGeometry(sunR, 64, 64),
    new THREE.MeshBasicMaterial({ map: loadTex(THREE, "site/sun-photosphere.jpg"), color: new THREE.Color(1.0, 0.93, 0.8) }));
  scene.add(sun);
  const corona = new THREE.Sprite(new THREE.SpriteMaterial({ map: loadTex(THREE, "site/sun-corona.png"), color: 0xffe2b0, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, opacity: 0.9 }));
  corona.scale.setScalar(sunR * 2 / 0.33);
  scene.add(corona);
  scene.add(atmosphere(THREE, sunR * 1.12, 0xffb050, 2.2, 1.2));
  const glow = new THREE.Sprite(new THREE.SpriteMaterial({ map: radialTexture(THREE), color: 0xffb060, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, opacity: 0.55 }));
  glow.scale.setScalar(sunR * 9);
  scene.add(glow);
  scene.add(new THREE.PointLight(0xfff4e0, 3.2, 0, 0), new THREE.AmbientLight(0x404a60, 0.12));

  const bodies = [], hit = [];
  const orbitMat = new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.12 });
  for (const p of PLANETS) {
    const pts = [];
    for (let i = 0; i <= 256; i++) { const t = (i / 256) * Math.PI * 2; pts.push(new THREE.Vector3(Math.cos(t) * p.orbit, 0, Math.sin(t) * p.orbit)); }
    scene.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), orbitMat));

    const pivot = new THREE.Group();
    const holder = new THREE.Group();
    holder.position.x = p.orbit;
    pivot.add(holder);
    const mesh = new THREE.Mesh(new THREE.SphereGeometry(p.r, 48, 48),
      new THREE.MeshStandardMaterial({ map: loadTex(THREE, `site/planet-${p.id}.jpg`), roughness: 0.95, metalness: 0 }));
    if (p.tilt) holder.rotation.z = THREE.MathUtils.degToRad(p.tilt);
    holder.add(mesh);
    if (p.ring) {
      const rg = new THREE.RingGeometry(p.r * 1.25, p.r * 2.3, 128, 1);
      // map U radially
      const pos = rg.attributes.position, uv = rg.attributes.uv, v = new THREE.Vector3();
      for (let i = 0; i < pos.count; i++) { v.fromBufferAttribute(pos, i); uv.setXY(i, (v.length() - p.r * 1.25) / (p.r * 1.05), 0.5); }
      const ring = new THREE.Mesh(rg, new THREE.MeshStandardMaterial({ map: ringTexture(THREE), transparent: true, side: THREE.DoubleSide, depthWrite: false, roughness: 1 }));
      ring.rotation.x = -Math.PI / 2 + THREE.MathUtils.degToRad(26.7);
      holder.add(ring);
    }
    if (p.id === "earth") holder.add(atmosphere(THREE, p.r * 1.07, 0x5aa8ff, 3, 1.2));
    // invisible, larger hit target so small planets are easy to hover
    const target = new THREE.Mesh(new THREE.SphereGeometry(Math.max(p.r * 1.6, 0.55), 12, 12), new THREE.MeshBasicMaterial({ visible: false }));
    target.userData.p = p;
    holder.add(target);
    hit.push(target);
    pivot.rotation.y = Math.random() * Math.PI * 2;
    scene.add(pivot);
    bodies.push({ p, pivot, mesh, speed: 0.22 / Math.pow(p.au, 1.5) * 0.6 + 0.004 });
  }

  let camDist = 30;
  sizeLoop(renderer, camera, canvas, (w, h) => {
    const aspect = w / h;
    const vfov = THREE.MathUtils.degToRad(camera.fov);
    const hfov = 2 * Math.atan(Math.tan(vfov / 2) * aspect);
    const need = 17.5; // half-width of Neptune's orbit plus margin
    camDist = Math.max(need / Math.tan(hfov / 2), need / Math.tan(vfov / 2) * 0.62);
  });

  const ray = new THREE.Raycaster(), mouse = new THREE.Vector2(9, 9);
  let hovered = null, pointer = { x: 0, y: 0 };
  function pick(ev) {
    const r = canvas.getBoundingClientRect();
    pointer = { x: ev.clientX - r.left, y: ev.clientY - r.top };
    mouse.set((pointer.x / r.width) * 2 - 1, -(pointer.y / r.height) * 2 + 1);
  }
  canvas.addEventListener("pointermove", pick);
  canvas.addEventListener("pointerdown", pick);
  canvas.addEventListener("pointerleave", () => mouse.set(9, 9));

  let active = false, last = performance.now(), t = 0;
  const v = new THREE.Vector3();
  function frame(now) {
    if (!active) return;
    const dt = Math.min(0.05, (now - last) / 1000); last = now;
    if (!REDUCED) t += dt;
    for (const b of bodies) {
      if (!REDUCED) { b.pivot.rotation.y += dt * b.speed; b.mesh.rotation.y += dt * 0.25; }
    }
    sun.rotation.y = t * 0.02;
    const az = REDUCED ? 0.6 : 0.6 + t * 0.015, el = THREE.MathUtils.degToRad(24);
    camera.position.set(Math.sin(az) * Math.cos(el) * camDist, Math.sin(el) * camDist, Math.cos(az) * Math.cos(el) * camDist);
    camera.lookAt(0, -1.2, 0);

    ray.setFromCamera(mouse, camera);
    const hits = ray.intersectObjects(hit, false);
    const h = hits.length ? hits[0].object : null;
    if (h !== hovered) {
      hovered = h;
      canvas.style.cursor = h ? "pointer" : "";
      if (h) { tip.innerHTML = `${h.userData.p.name}<small>${h.userData.p.fact}</small>`; tip.hidden = false; }
      else tip.hidden = true;
    }
    if (hovered) {
      hovered.getWorldPosition(v).project(camera);
      const r = canvas.getBoundingClientRect();
      tip.style.left = ((v.x + 1) / 2 * r.width) + "px";
      tip.style.top = ((1 - v.y) / 2 * r.height) + "px";
    }
    renderer.render(scene, camera);
    requestAnimationFrame(frame);
  }
  return {
    setActive(on) {
      if (on === active) return;
      active = on;
      if (on) { last = performance.now(); requestAnimationFrame(frame); }
    },
  };
}
