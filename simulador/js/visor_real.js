"use strict";
// =====================================================================
//  MUNDO REAL DE DETALLE (simulador del navegador, v1). Amplia el Visor con:
//   - la ortofoto PNOA de toda la region (mundos/<id>_orto.jpg) como suelo lejano, en el GPS y en el mapa de salida;
//   - la ZONA DE DETALLE (zonas/<id>/, la misma que lee el simulador de Godot, v2): terreno del MDT a 5 m con la
//     ortofoto a 0,5 m, edificios del Catastro con sus plantas reales y los arboles detectados en la ortofoto.
//   - carreteras y edificios genericos de OSM fuera de la zona (dentro estan los de verdad).
//  Los datos se generan con analisis/mundo_cartagena/zona.py y orto_region.py.
// =====================================================================
Object.assign(Visor.prototype, {

  /** Tras construir la escena de un mundo real: guarda su terreno lejano (para hundirlo bajo la zona) y carga la
   *  ortofoto de la region, que sustituye a la textura sintetica cuando llega. */
  _despuesDeConstruirMundo(esc, m) {
    const terr = esc.children.find(o => o.isMesh && o.geometry.attributes.uv && o.material.vertexColors && o.material.map);
    esc.userData.terreno = terr;
    if (terr) esc.userData.yOriginal = Float32Array.from(terr.geometry.attributes.position.array);
    const img = new Image();
    img.onload = () => {
      let fuente = img;
      const max = this.renderer.capabilities.maxTextureSize;
      if (img.width > max) { const [c, g] = lienzo(max, Math.round(img.height * max / img.width)); g.drawImage(img, 0, 0, c.width, c.height); fuente = c; }
      const t = new THREE.Texture(fuente); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = this.renderer.capabilities.getMaxAnisotropy(); t.needsUpdate = true;
      if (terr) { terr.material.map = t; terr.material.vertexColors = false; terr.material.needsUpdate = true; }
      const c = this.lienzoMundo; if (c) c.getContext("2d").drawImage(img, 0, 0, c.width, c.height);   // GPS y mapa de salida
      if (typeof GPS !== "undefined") GPS.mapa = null;
      if (typeof pintarMapaLanz === "function" && typeof pantallaActual !== "undefined" && pantallaActual === "pLanzamiento") pintarMapaLanz();
    };
    // con doble clic (file://) una imagen suelta no se puede subir a WebGL (el suelo saldria negro): se usa la misma foto
    // empaquetada en data: dentro de mundos/<id>_orto.js. Si no esta, se queda la textura sintetica
    if (ABIERTO_COMO_FICHERO) cargarScript("mundos/" + m.id + "_orto.js").then(() => { if (Mundos._ortos[m.id]) img.src = Mundos._ortos[m.id]; })
                                .catch(e => console.warn("Sin la ortofoto de la region (falta mundos/" + m.id + "_orto.js):", e));
    else img.src = "mundos/" + m.id + "_orto.jpg";
  },

  /** Carreteras de OSM en cinta, sin los tramos dentro de la zona de detalle (alli la ortofoto ya las muestra). */
  _carreterasMundo(esc, m) {
    if (esc.userData.cintas) { esc.remove(esc.userData.cintas); esc.userData.cintas.geometry.dispose(); }
    const dentro = (e, n) => this._enZonas(n, e, 30);
    const lista = [];
    for (const c of m.carreteras) {
      let tramo = [c[0]];
      for (let i = 1; i < c.length; i += 2) {
        if (dentro(c[i], c[i + 1])) { if (tramo.length >= 5) lista.push(tramo); tramo = [c[0]]; }
        else tramo.push(c[i], c[i + 1]);
      }
      if (tramo.length >= 5) lista.push(tramo);
    }
    esc.userData.cintas = this._cintas(esc, lista, this.entorno.altura);
  },

  /** Edificios genericos (cajas) repartidos por las zonas urbanas de OSM, fuera de la zona de detalle. */
  _edificiosSinteticos(esc, m) {
    for (const o of esc.userData.edifSint || []) { esc.remove(o); o.geometry.dispose(); }
    const ent = this.entorno, alt = ent.altura, r = semilla(17), antes = new Set(esc.children);
    const dentro = (P, x, y) => { let d = false; for (let i = 0, j = P.length - 1; i < P.length; j = i++) { const [xi, yi] = P[i], [xj, yj] = P[j]; if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) d = !d; } return d; };
    const edificios = [];
    for (const u of m.urbano) {
      const P = []; for (let i = 1; i < u.length; i += 2) P.push([u[i], u[i + 1]]);
      let e0 = 1e9, e1 = -1e9, n0 = 1e9, n1 = -1e9; for (const [e, n] of P) { e0 = Math.min(e0, e); e1 = Math.max(e1, e); n0 = Math.min(n0, n); n1 = Math.max(n1, n); }
      const paso = u[0] === 1 ? 48 : 70;
      for (let e = e0; e < e1; e += paso) for (let n = n0; n < n1; n += paso) {
        const ee = e + (r() - 0.5) * paso * 0.7, nn = n + (r() - 0.5) * paso * 0.7;
        if (this._enZonas(nn, ee, 20)) continue;
        if (edificios.length < 14000 && dentro(P, ee, nn) && !ent.enMar(nn, ee) && ent.alturaMar(nn, ee) > 0) edificios.push([ee, nn, u[0] === 1 ? 8 + r() * 8 : 12 + r() * 14, u[0], r()]);
      }
    }
    const caja = new THREE.BoxGeometry(1, 1, 1); caja.translate(0, 0.5, 0);
    this._instanciarEn(esc, caja, new THREE.MeshLambertMaterial({ color: 0xffffff }), edificios, (it, M, Cc) => {
      const [e, n, s, tipo, z] = it, h = tipo === 1 ? 4 + z * 7 : 6 + z * 6;
      M.compose(new THREE.Vector3(e, alt(n, e), -n), new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), z * 3.14), new THREE.Vector3(s, h, s * (0.7 + z * 0.5)));
      Cc.setHex(tipo === 1 ? [0xf2ede4, 0xe8dcc8, 0xd9c4a8, 0xf5f0e8][Math.floor(z * 4)] : [0xd0d4d8, 0xc3c7cc, 0xb9bec4][Math.floor(z * 3)]);
    }, 1200);
    esc.userData.edifSint = esc.children.filter(o => !antes.has(o));
    for (const o of esc.userData.edifSint) { o.castShadow = true; o.receiveShadow = true; }
  },

  /** Pone la zona de detalle (o la quita con null) en la escena del mundo activo. z = { meta, dem, base } (base: la
   *  carpeta, p. ej. "zonas/origen/"). El Entorno ya la tiene (ponerZona) para que el suelo fisico sea el mismo. */
  ponerZona(z) { this.ponerZonas(z ? [z] : []); },

  /** Varias zonas de detalle a la vez (las de cerca del punto de lanzamiento; [] para quitarlas). Como poner_zonas de
   *  mundo_3d.gd en Godot. El Entorno ya las tiene (ponerZonas). */
  ponerZonas(lista) {
    const esc = this.escena, m = this.mundo;
    if (!m) return;
    lista = (lista || []).filter(Boolean);
    for (const g of esc.userData.zonaGrupos || []) {
      g.traverse(o => { if (o.geometry) o.geometry.dispose(); if (o.material && o.material.map) o.material.map.dispose(); });
      esc.remove(g);
    }
    esc.userData.zonaGrupos = [];
    this.entorno.quitarArboles("zona:");             // los arboles solidos de las zonas que se quitan
    this.mapaZonas = [];                              // teselas de ortofoto de las zonas para el GPS: { tex, N0, E0, lado }
    const terr = esc.userData.terreno, pos = terr && terr.geometry.attributes.position, Y0 = esc.userData.yOriginal;
    if (pos) pos.array.set(Y0);
    this.zonasBBox = lista.map(z => [z.meta.N0, z.meta.N0 + z.meta.lado_m, z.meta.E0, z.meta.E0 + z.meta.lado_m]);
    this.zonaBBox = this.zonasBBox[0] || null; this.zonaId = lista.length ? lista.map(z => z.meta.id).join(",") : null;
    if (lista.length && pos) {                        // el terreno lejano se hunde 25 m bajo las zonas: no asoma entre sus mallas
      const a = pos.array;
      for (let i = 0; i < a.length; i += 3) if (this._enZonas(-a[i + 2], a[i], 0)) a[i + 1] -= 25;
    }
    if (pos) { pos.needsUpdate = true; terr.geometry.computeBoundingSphere(); }
    this._carreterasMundo(esc, m); this._edificiosSinteticos(esc, m);
    for (const z of lista) {
      const g = new THREE.Group(); esc.add(g); esc.userData.zonaGrupos.push(g);
      this._terrenoZona(g, z); this._edificiosZona(g, z); this._arbolesZona(g, z);
    }
    this._singulares(esc, m);                          // despues de las zonas: se asientan en su suelo
  },

  /** Lo que hay que ver en un trabajo del modo Operaciones (escenarios.js, "operacion"; las reglas en js/operaciones.js),
   *  o null para quitarlo: la plataforma de despegue, las placas numeradas de la inspeccion, los jalones de la parcela o
   *  de la zona de busqueda, el senderista, las manchas de plaga y las torres y cables de la linea. casa: [N, E]. */
  ponerOperacion(d, casa) {
    if (this.operacion) { this.operacion.parent && this.operacion.parent.remove(this.operacion); this.operacion = null; }
    if (!d || !this.mundo) return;
    const G = new THREE.Group(), alt = this.entorno.altura, h0 = this.mundo.terreno.h0, std = (c, extra) => new THREE.MeshStandardMaterial(Object.assign({ color: c, roughness: 0.8 }, extra || {}));
    const en = (o, N, E, y) => { o.position.set(E, y, -N); G.add(o); return o; };
    const placa = (texto, fondo, tam) => { const [c, g] = lienzo(128, 128); g.fillStyle = fondo; g.fillRect(0, 0, 128, 128); g.fillStyle = "#fff"; g.fillRect(8, 8, 112, 112); g.fillStyle = fondo; g.fillRect(16, 16, 96, 96);
      g.fillStyle = "#fff"; g.font = `bold ${tam || 80}px sans-serif`; g.textAlign = "center"; g.textBaseline = "middle"; g.fillText(texto, 64, 68); return new THREE.MeshBasicMaterial({ map: texSRGB(c), side: THREE.DoubleSide }); };
    const jalon = (N, E, c1) => {                                       // jalon de 2 m a franjas con banderin
      const y = alt(N, E), [c, g] = lienzo(8, 64); for (let i = 0; i < 8; i++) { g.fillStyle = i % 2 ? "#ffffff" : c1; g.fillRect(0, i * 8, 8, 8); }
      en(new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 2, 8), new THREE.MeshLambertMaterial({ map: texSRGB(c) })), N, E, y + 1);
      en(new THREE.Mesh(new THREE.PlaneGeometry(0.5, 0.35), std(c1, { side: THREE.DoubleSide })), N, E, y + 1.8).position.x += 0.25;
    };
    const esquinas = (P, c1) => [[P.n0, P.e0], [P.n0, P.e1], [P.n1, P.e0], [P.n1, P.e1]].forEach(([N, E]) => jalon(N, E, c1));
    // plataforma de despegue (a la que hay que volver)
    const pad = en(new THREE.Mesh(new THREE.CylinderGeometry(0.75, 0.75, 0.03, 32), placa("H", "#ff6d00", 70)), casa[0], casa[1], alt(casa[0], casa[1]) + 0.04);
    pad.material = [std(0xff6d00), placa("H", "#ff6d00", 70), std(0xff6d00)];
    (d.puntos || []).forEach((q, i) => {                                // inspeccion: placas naranjas numeradas
      const y = q.cota !== undefined ? q.cota - h0 : alt(q.n, q.e) + (q.h || 0), o = new THREE.Mesh(new THREE.PlaneGeometry(1.5, 1.5), placa(String(i + 1), "#ff6d00"));
      if (q.normal !== undefined) { en(o, q.n + 0.06 * Math.cos(q.normal * D2R), q.e + 0.06 * Math.sin(q.normal * D2R), y); o.rotation.y = Math.PI - q.normal * D2R; }
      else { en(o, q.n, q.e, y + 0.06); o.rotation.x = -Math.PI / 2; }
    });
    if (d.parcela) esquinas(d.parcela, d.solape ? "#e53935" : "#2e7d32");
    if (d.solape) {                                                     // dianas de apoyo de la fotogrametria
      const P = d.parcela;
      for (const [N, E] of [[P.n0 + 15, P.e0 + 15], [P.n0 + 15, P.e1 - 15], [P.n1 - 15, P.e0 + 15], [P.n1 - 15, P.e1 - 15], [(P.n0 + P.n1) / 2, (P.e0 + P.e1) / 2]]) {
        const [c, g] = lienzo(64, 64); g.fillStyle = "#fff"; g.fillRect(0, 0, 64, 64); g.fillStyle = "#111"; g.fillRect(0, 0, 32, 32); g.fillRect(32, 32, 32, 32);
        en(new THREE.Mesh(new THREE.PlaneGeometry(1.2, 1.2), new THREE.MeshBasicMaterial({ map: texSRGB(c) })), N, E, alt(N, E) + 0.05).rotation.x = -Math.PI / 2;
      }
    }
    if (d.zona) {                                                       // busqueda: jalones amarillos y el senderista
      esquinas(d.zona, "#fdd835");
      if (d.persona) {
        const [N, E] = d.persona, y = alt(N, E), P = new THREE.Group();
        const pie = (dx) => { const p = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.07, 0.85, 8), std(0x2b3440)); p.position.set(dx, 0.43, 0); P.add(p); };
        pie(-0.1); pie(0.1);
        const tronco = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.17, 0.62, 12), std(0xd32f2f)); tronco.position.y = 1.16; P.add(tronco);
        const cabeza = new THREE.Mesh(new THREE.SphereGeometry(0.12, 12, 8), std(0xc68b6e)); cabeza.position.y = 1.6; P.add(cabeza);
        const mochila = new THREE.Mesh(new THREE.BoxGeometry(0.32, 0.45, 0.2), std(0xff8f00)); mochila.position.set(0, 1.2, 0.2); P.add(mochila);
        for (const s of [-1, 1]) { const b = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.05, 0.6, 8), std(0xd32f2f)); b.position.set(s * 0.27, 1.12, 0); b.rotation.z = s * 0.2; P.add(b); }
        P.rotation.y = 0.7; en(P, N, E, y);
      }
    }
    (d.manchas || []).forEach(([N, E, r], i) => {                       // agricultura: rodales amarillos en el cultivo
      const s = new THREE.Shape(); for (let k = 0; k <= 24; k++) { const a = k / 24 * 2 * Math.PI, rr = r * (0.82 + 0.18 * Math.sin(3 * a + i) * Math.cos(2 * a - i)); k ? s.lineTo(rr * Math.cos(a), rr * Math.sin(a)) : s.moveTo(rr * Math.cos(a), rr * Math.sin(a)); }
      en(new THREE.Mesh(new THREE.ShapeGeometry(s), new THREE.MeshLambertMaterial({ color: 0xc9b13a, transparent: true, opacity: 0.85 })), N, E, alt(N, E) + 0.12).rotation.x = -Math.PI / 2;
    });
    if (d.torres) {                                                     // linea: torres de celosia, crucetas, aisladores y cables
      const op = new Operacion(d, () => {}, () => {}, { casa, suelo: alt, h0 }), acero = std(0x9ea4a8, { metalness: 0.5, roughness: 0.5 });
      const barra = (A, B, r, mat) => {                                 // cilindro de A a B (N, E, arriba)
        const a = new THREE.Vector3(A[1], A[2], -A[0]), b = new THREE.Vector3(B[1], B[2], -B[0]), L = a.distanceTo(b);
        const o = new THREE.Mesh(new THREE.CylinderGeometry(r, r, L, 6), mat); o.position.copy(a).add(b).multiplyScalar(0.5);
        o.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), b.clone().sub(a).normalize()); G.add(o);
      };
      d.torres.forEach(([tn, te], i) => {
        const b0 = op.bases[i], L = op.laterales[i], F = [L[1], -L[0]];      // F: a lo largo de la linea
        const pata = (s, t, h) => { const w = 1.3 - 0.75 * h / d.alto; return [tn + (s * L[0] + t * F[0]) * w, te + (s * L[1] + t * F[1]) * w, b0 + h]; };
        for (const [s, t] of [[-1, -1], [-1, 1], [1, -1], [1, 1]]) barra(pata(s, t, 0), pata(s, t, d.alto - 1), 0.07, acero);
        for (let h = 0; h < d.alto - 2; h += 4) for (const [s1, t1, s2, t2] of [[-1, -1, 1, -1], [-1, 1, 1, 1], [-1, -1, -1, 1], [1, -1, 1, 1]]) {
          barra(pata(s1, t1, h), pata(s2, t2, h + 4), 0.03, acero); barra(pata(s2, t2, h), pata(s1, t1, h + 4), 0.03, acero);
        }
        barra([tn + L[0] * d.brazo, te + L[1] * d.brazo, b0 + d.fases + 1.2], [tn - L[0] * d.brazo, te - L[1] * d.brazo, b0 + d.fases + 1.2], 0.09, acero);   // cruceta
        barra(pata(0, 0, d.alto - 1), [tn, te, b0 + d.alto], 0.08, acero);
        for (const k of [0, 1]) { const A = op.enganches[i][k]; barra([A[0], A[1], A[2] + 1.2], A, 0.07, std(0x8d6e63)); }   // cadenas de aisladores
      });
      for (const [A, B] of op.cables) barra(A, B, 0.025, std(0x2f3133, { metalness: 0.6, roughness: 0.4 }));
    }
    G.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    this.operacion = G; this.escena.add(G);
  },

  /** Elementos singulares del mundo (simulador/singulares.js, comun con Godot): la entrada del CIFP Politecnico... */
  _singulares(esc, m) {
    if (esc.userData.singulares) { esc.userData.singulares.traverse(o => { if (o.geometry) o.geometry.dispose(); }); esc.remove(esc.userData.singulares); }
    const g = new THREE.Group(); esc.add(g); esc.userData.singulares = g;
    const alt = this.entorno.altura, T = Visor.texturaSingular;
    const mat = (tex, rep, extra) => { const t = tex.clone(); t.needsUpdate = true; if (rep) t.repeat.set(rep[0], rep[1]); return new THREE.MeshStandardMaterial(Object.assign({ map: t, roughness: 0.9, metalness: 0 }, extra || {})); };
    const cara = (obj, rumbo) => { obj.rotation.y = Math.PI - rumbo * Math.PI / 180; };      // la cara +z de la pieza mira a "rumbo"
    for (const S of (window.SINGULARES || []).filter(q => q.mundo === m.id)) for (const p of S.piezas) {
      if (p.tipo === "muro") {
        const de = p.e1 - p.e0, dn = p.n1 - p.n0, L = Math.hypot(de, dn), y0 = Math.min(alt(p.n0, p.e0), alt(p.n1, p.e1)) - 0.3;
        const o = new THREE.Mesh(new THREE.BoxGeometry(L, p.alto + 0.3, p.grosor), mat(T(p.textura), [L / 1.6, (p.alto + 0.3) / 1.6]));
        o.position.set((p.e0 + p.e1) / 2, y0 + (p.alto + 0.3) / 2, -(p.n0 + p.n1) / 2); o.rotation.y = Math.atan2(dn, de); g.add(o);
      } else if (p.tipo === "cilindro") {
        const y0 = alt(p.n, p.e) - 0.3, o = new THREE.Mesh(new THREE.CylinderGeometry(p.radio, p.radio, p.alto + 0.3, 40), mat(T(p.textura), [2 * Math.PI * p.radio / 2.4, (p.alto + 0.3) / 2.4]));
        o.position.set(p.e, y0 + (p.alto + 0.3) / 2, -p.n); g.add(o);
      } else if (p.tipo === "disco") {
        const o = new THREE.Mesh(new THREE.CircleGeometry(p.radio, 48), mat(T(p.textura), null, { metalness: 0.4, roughness: 0.5 }));
        o.position.set(p.e, alt(p.n, p.e) + p.h, -p.n); cara(o, p.rumbo); g.add(o);
        const aro = new THREE.Mesh(new THREE.TorusGeometry(p.radio, 0.06, 8, 48), new THREE.MeshStandardMaterial({ color: 0x2b2f33, metalness: 0.5, roughness: 0.4 }));
        aro.position.copy(o.position); aro.rotation.copy(o.rotation); g.add(aro);
      } else if (p.tipo === "cartel") {
        const o = new THREE.Mesh(new THREE.PlaneGeometry(p.ancho, p.alto), new THREE.MeshStandardMaterial({ map: Visor.texturaCartel(p), roughness: 0.6 }));
        o.position.set(p.e, alt(p.n, p.e) + p.h, -p.n); cara(o, p.rumbo); g.add(o);
        const fondo = new THREE.Mesh(new THREE.BoxGeometry(p.ancho + 0.08, p.alto + 0.08, 0.08), new THREE.MeshStandardMaterial({ color: 0xe8e8e4 }));
        fondo.position.copy(o.position); fondo.rotation.copy(o.rotation); fondo.translateZ(-0.05); g.add(fondo);
      } else if (p.tipo === "marquesina") {
        const y = alt((p.n0 + p.n1) / 2, (p.e0 + p.e1) / 2), acero = new THREE.MeshStandardMaterial({ color: 0x3a3f45, metalness: 0.6, roughness: 0.45 });
        const ancho = p.e1 - p.e0 + p.vuelo, fondo = p.n1 - p.n0;
        const techo = new THREE.Mesh(new THREE.BoxGeometry(ancho, 0.22, fondo), new THREE.MeshStandardMaterial({ color: 0xd9dcdf, metalness: 0.3, roughness: 0.5 }));
        techo.position.set((p.e0 - p.vuelo + p.e1) / 2, y + p.h, -(p.n0 + p.n1) / 2); g.add(techo);
        for (let k = 0; k <= 4; k++) {                                     // cerchas metalicas bajo el techo
          const v = new THREE.Mesh(new THREE.BoxGeometry(ancho, 0.5, 0.08), acero);
          v.position.set(techo.position.x, y + p.h - 0.35, -(p.n0 + 0.2 + k * (fondo - 0.4) / 4)); g.add(v);
        }
        for (const n of [p.n0 + 0.25, p.n1 - 0.25]) {                    // pilares de la parte que vuela
          const c = new THREE.Mesh(new THREE.CylinderGeometry(0.11, 0.11, p.h, 10), acero);
          c.position.set(p.e0 - p.vuelo + 0.3, y + p.h / 2, -n); g.add(c);
        }
      } else if (p.tipo === "submarino") {
        const y = alt(p.n, p.e), metal = new THREE.MeshStandardMaterial({ color: 0xa7aeb5, metalness: 0.35, roughness: 0.38 });
        const perfil = []; for (let k = 0; k <= 24; k++) { const t = k / 24, r = p.radio * Math.pow(Math.sin(Math.PI * Math.min(1, t * 1.15)), 0.62) * (t < 0.87 ? 1 : 1 - (t - 0.87) / 0.13 * 0.9); perfil.push(new THREE.Vector2(Math.max(0.01, r), (t - 0.5) * p.largo)); }
        const casco = new THREE.Mesh(new THREE.LatheGeometry(perfil, 32), metal);
        const grupo = new THREE.Group(); grupo.position.set(p.e, y + p.peana + 0.9 + p.radio, -p.n); grupo.rotation.y = -p.rumbo * Math.PI / 180; g.add(grupo);
        casco.rotation.x = Math.PI / 2; grupo.add(casco);                  // eje del casco a lo largo de -z local (proa hacia "rumbo")
        const torre = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.26, 0.42, 16), metal); torre.position.set(0, p.radio + 0.12, -0.6); grupo.add(torre);
        const timon = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.5, 0.35), metal); timon.position.set(0, 0, p.largo / 2 - 0.25); grupo.add(timon);
        const helice = new THREE.Mesh(new THREE.TorusGeometry(0.22, 0.03, 6, 16), metal); helice.position.set(0, 0, p.largo / 2 - 0.05); grupo.add(helice);
        const peana = new THREE.Mesh(new THREE.BoxGeometry(1.4, p.peana, 2.4), new THREE.MeshStandardMaterial({ color: 0x8f9499, roughness: 0.85 }));
        peana.position.set(p.e, y + p.peana / 2, -p.n); peana.rotation.y = grupo.rotation.y; g.add(peana);
        const poste = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.08, 0.95, 10), metal); poste.position.set(p.e, y + p.peana + 0.47, -p.n); g.add(poste);
      } else if (p.tipo === "mastil") {
        const y = alt(p.n, p.e), poste = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.05, p.alto, 10), new THREE.MeshStandardMaterial({ color: 0xd8dadc, metalness: 0.6, roughness: 0.3 }));
        poste.position.set(p.e, y + p.alto / 2, -p.n); g.add(poste);
        const b = new THREE.Mesh(new THREE.PlaneGeometry(1.5, 1.0, 8, 1), new THREE.MeshStandardMaterial({ map: Visor.texturaBandera(p.bandera), side: THREE.DoubleSide, roughness: 0.8 }));
        const pos = b.geometry.attributes.position; for (let i = 0; i < pos.count; i++) pos.setZ(i, 0.08 * Math.sin((pos.getX(i) + 0.75) * 3.2)); b.geometry.computeVertexNormals();   // un poco ondeada
        b.position.set(p.e, y + p.alto - 0.6, -(p.n - 0.78)); b.rotation.y = Math.PI / 2; g.add(b);      // ondea hacia el sur: de cara al aparcamiento (oeste)
      }
    }
    g.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  },

  /** Terreno de la zona: una malla por tesela de ortofoto (500 m, 101 x 101 vertices a 5 m) con su foto; en el borde
   *  exterior, un faldon que baja 30 m para tapar el escalon con el terreno lejano. */
  _terrenoZona(g, z) {
    const Z = z.meta, D = z.dem, n = Z.dem.n, paso = Z.dem.paso_m, h0 = this.mundo.terreno.h0, nt = Z.orto.teselas;
    const celdas = Math.round(Z.orto.tesela_m / paso), cargador = new THREE.TextureLoader(), aniso = this.renderer.capabilities.getMaxAnisotropy();
    const yDe = (i, j) => { const v = D[i * n + j]; return (v === -32768 ? -1.5 : Math.max(1, v / 10)) - h0; };
    for (let ti = 0; ti < nt; ti++) for (let tj = 0; tj < nt; tj++) {
      const pos = [], uv = [], idx = [], i0 = ti * celdas, j0 = tj * celdas, w = celdas + 1;
      for (let a = 0; a <= celdas; a++) for (let b = 0; b <= celdas; b++) {
        const i = i0 + a, j = j0 + b;
        pos.push(Z.E0 + j * paso, yDe(i, j), -(Z.N0 + i * paso)); uv.push(b / celdas, a / celdas);
      }
      for (let a = 0; a < celdas; a++) for (let b = 0; b < celdas; b++) { const p = a * w + b; idx.push(p, p + 1, p + w, p + 1, p + w + 1, p + w); }
      // faldones en los bordes exteriores de la zona
      const faldon = (lista) => {
        const base = pos.length / 3;
        for (const [a, b] of lista) { const k = (a * w + b) * 3; pos.push(pos[k], pos[k + 1] - 30, pos[k + 2]); uv.push(b / celdas, a / celdas); }
        for (let q = 0; q < lista.length - 1; q++) { const [a1, b1] = lista[q], [a2, b2] = lista[q + 1], p1 = a1 * w + b1, p2 = a2 * w + b2; idx.push(p1, base + q, p2, p2, base + q, base + q + 1); }
      };
      const fila = a => Array.from({ length: w }, (_, b) => [a, b]), col = b => Array.from({ length: w }, (_, a) => [a, b]);
      if (ti === 0) faldon(fila(0)); if (ti === nt - 1) faldon(fila(celdas).reverse());
      if (tj === 0) faldon(col(0).reverse()); if (tj === nt - 1) faldon(col(celdas));
      const geo = new THREE.BufferGeometry();
      geo.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3)); geo.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2)); geo.setIndex(idx);
      geo.computeVertexNormals();
      const tex = cargador.load(z.datos ? z.datos.orto[ti + "_" + tj] : z.base + Z.orto.archivo.replace("{i}", ti).replace("{j}", tj));
      tex.colorSpace = THREE.SRGBColorSpace; tex.anisotropy = aniso;
      (g.userData.orto = g.userData.orto || {})[ti + "_" + tj] = tex;
      (this.mapaZonas = this.mapaZonas || []).push({ tex, N0: Z.N0 + ti * Z.orto.tesela_m, E0: Z.E0 + tj * Z.orto.tesela_m, lado: Z.orto.tesela_m });
      const malla = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ map: tex, side: THREE.DoubleSide }));
      malla.receiveShadow = true; g.add(malla);
    }
  },

  /** Edificios del Catastro: cada huella extruida a sus plantas (3 m por planta) desde la cota del terreno. Tejados con
   *  la propia ortofoto de la zona (la tesela de su centro: se ven las cubiertas reales, lucernarios, placas...), fachadas
   *  con una ventana por planta y modulo de 3,5 m (VentanasFachada) del color claro de siempre o, si la zona lo trae
   *  ("f", p. ej. el ladrillo del CIFP Politecnico), con ese color y textura de ladrillo. Igual que _edificios_zona de Godot. */
  _edificiosZona(g, z) {
    this._edificiosDe(z).then(lista => {
      const Z = z.meta, h0 = this.mundo.terreno.h0, nt = Z.orto.teselas, tm = Z.orto.tesela_m, C = new THREE.Color(), Cw = new THREE.Color(), crema = new THREE.Color(0xeee6d8), r = semilla(5);
      const fach = { claro: { pos: [], col: [], uv: [] }, ladrillo: { pos: [], col: [], uv: [] } }, tejados = {};
      for (const ed of lista) {
        const P = []; for (let i = 0; i < ed.p.length; i += 2) P.push(new THREE.Vector2(ed.p[i], ed.p[i + 1]));
        if (P.length < 3) continue;
        const y0 = ed.b - h0 - 0.4, y1 = ed.b - h0 + ed.pl * 3.0 + 0.5, alto = (y1 - y0) / 3.0;
        C.set(ed.c).convertSRGBToLinear(); C.multiplyScalar(1.08);
        const F = ed.f ? fach.ladrillo : fach.claro;
        if (ed.f) Cw.setRGB(1, 1, 1).multiplyScalar(0.92 + 0.12 * r());                                  // el color va en la textura
        else Cw.copy(crema).convertSRGBToLinear().lerp(C, 0.12).multiplyScalar(0.93 + 0.1 * r());
        let u = 0;
        for (let k = 0; k < P.length; k++) {                      // fachadas: u en modulos de 3,5 m, v en plantas
          const a = P[k], b = P[(k + 1) % P.length], L = a.distanceTo(b), u0 = u / 3.5, u1 = (u + L) / 3.5; u += L;
          F.pos.push(a.x, y0, -a.y, b.x, y0, -b.y, b.x, y1, -b.y, a.x, y0, -a.y, b.x, y1, -b.y, a.x, y1, -a.y);
          F.uv.push(u0, 0, u1, 0, u1, alto, u0, 0, u1, alto, u0, alto);
          for (let q = 0; q < 6; q++) F.col.push(Cw.r, Cw.g, Cw.b);
        }
        let tri; try { tri = THREE.ShapeUtils.triangulateShape(P, []); } catch (e) { tri = []; }
        let ce = 0, cn = 0; for (const v of P) { ce += v.x; cn += v.y; } ce /= P.length; cn /= P.length;
        const ti = Math.min(nt - 1, Math.max(0, Math.floor((cn - Z.N0) / tm))), tj = Math.min(nt - 1, Math.max(0, Math.floor((ce - Z.E0) / tm)));
        const T = tejados[ti + "_" + tj] = tejados[ti + "_" + tj] || { pos: [], uv: [], N0: Z.N0 + ti * tm, E0: Z.E0 + tj * tm };
        for (const t of tri) for (const v of t) { T.pos.push(P[v].x, y1, -P[v].y); T.uv.push((P[v].x - T.E0) / tm, (P[v].y - T.N0) / tm); }   // tejado: la foto
      }
      for (const [nombre, F] of Object.entries(fach)) {
        if (!F.pos.length) continue;
        const geo = new THREE.BufferGeometry();
        geo.setAttribute("position", new THREE.Float32BufferAttribute(F.pos, 3)); geo.setAttribute("color", new THREE.Float32BufferAttribute(F.col, 3));
        geo.setAttribute("uv", new THREE.Float32BufferAttribute(F.uv, 2)); geo.computeVertexNormals();
        const malla = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true, map: Visor.texturaFachada(nombre, this.renderer), side: THREE.DoubleSide }));
        malla.castShadow = true; malla.receiveShadow = true; g.add(malla);
      }
      const orto = g.userData.orto || {};
      for (const [k, T] of Object.entries(tejados)) {
        const geo = new THREE.BufferGeometry();
        geo.setAttribute("position", new THREE.Float32BufferAttribute(T.pos, 3)); geo.setAttribute("uv", new THREE.Float32BufferAttribute(T.uv, 2));
        geo.computeVertexNormals();
        const malla = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ map: orto[k] || null, color: orto[k] ? 0xffffff : 0xb8b0a4, side: THREE.DoubleSide }));
        malla.castShadow = true; malla.receiveShadow = true; g.add(malla);
      }
    }).catch(e => console.warn("Sin edificios de la zona:", e));
  },

  /** Arboles detectados en la ortofoto: los de copa (radio >= 1,3 m) con tronco y copa, los pequenos como matorral bajo.
   *  Copa pequena (radio < 2,5 m) = almendro: copa aplanada verde grisacea sobre un tronco corto; grande = algarrobo o
   *  pino: copa densa y oscura, tronco grueso. Instanciados por celdas de 500 m; mas triangulos cerca del punto de salida. */
  /** Edificios de una zona (una sola carga para los edificios y para quitar los arboles que caen dentro). */
  _edificiosDe(z) {
    return z._edificios = z._edificios || (z.datos ? Promise.resolve(z.datos.edificios) : fetch(z.base + z.meta.edificios.archivo).then(r => r.json()).catch(() => []));
  },

  /** Funcion (e, n, rc) -> true si un arbol de radio de copa rc cae dentro de un edificio o su copa se mete en el muro
   *  (centro a menos de media copa del borde): la deteccion de copas en la ortofoto confunde a veces cubiertas y patios
   *  con arboles. Rejilla de 40 m con los edificios que tocan cada celda. Lo mismo que _en_edificio de mundo_3d.gd. */
  _filtroEdificios(lista) {
    const C = 40, rej = new Map(), clave = (i, j) => i * 100003 + j;
    for (const ed of lista || []) {
      const p = ed.p; if (p.length < 6) continue;
      let e0 = Infinity, e1 = -Infinity, n0 = Infinity, n1 = -Infinity;
      for (let i = 0; i < p.length; i += 2) { e0 = Math.min(e0, p[i]); e1 = Math.max(e1, p[i]); n0 = Math.min(n0, p[i + 1]); n1 = Math.max(n1, p[i + 1]); }
      for (let i = Math.floor((e0 - 4) / C); i <= Math.floor((e1 + 4) / C); i++) for (let j = Math.floor((n0 - 4) / C); j <= Math.floor((n1 + 4) / C); j++) {
        const k = clave(i, j); if (!rej.has(k)) rej.set(k, []); rej.get(k).push(p);
      }
    }
    return (e, n, rc) => {
      for (const p of rej.get(clave(Math.floor(e / C), Math.floor(n / C))) || []) {
        let dentro = false, d2 = Infinity;
        for (let i = 0, j = p.length - 2; i < p.length; j = i, i += 2) {
          const xi = p[i], yi = p[i + 1], xj = p[j], yj = p[j + 1];
          if ((yi > n) !== (yj > n) && e < (xj - xi) * (n - yi) / (yj - yi) + xi) dentro = !dentro;
          const dx = xj - xi, dy = yj - yi, t = Math.max(0, Math.min(1, ((e - xi) * dx + (n - yi) * dy) / (dx * dx + dy * dy || 1)));
          d2 = Math.min(d2, (e - xi - t * dx) ** 2 + (n - yi - t * dy) ** 2);
        }
        if (dentro || d2 < (0.5 * rc) ** 2) return true;
      }
      return false;
    };
  },

  _arbolesZona(g, z) {
    Promise.all([z.datos ? Promise.resolve(z.datos.arboles) : fetch(z.base + z.meta.arboles.archivo).then(r => r.arrayBuffer()).then(b => new Float32Array(b)), this._edificiosDe(z)]).then(([A, edificios]) => {
      const alt = this.entorno.altura, r = semilla(29), base = this.baseNE || [0, 0], enEdificio = this._filtroEdificios(edificios);
      // sin arboles donde no los hay aunque la ortofoto lo parezca (escenarios.js, "sin_arboles": el aparcamiento del CIFP)
      const claros = Object.values(ESCENARIOS).filter(E => E.mundo === this.mundo.id).flatMap(E => E.destacados || []).filter(d => d.sin_arboles).map(d => d.sin_arboles);
      const enClaro = (e, n) => claros.some(P => { let k = false; for (let i = 0, j = P.length - 1; i < P.length; j = i++) if ((P[i][0] > n) !== (P[j][0] > n) && e < (P[j][1] - P[i][1]) * (n - P[i][0]) / (P[j][0] - P[i][0]) + P[i][1]) k = !k; return k; });
      const arboles = [], matas = [];
      for (let i = 0; i < A.length; i += 3) {
        if (Math.hypot(A[i] - base[1], A[i + 1] - base[0]) < 25 + A[i + 2]) continue;   // claro de 25 m alrededor del piloto (como en Godot)
        if (enEdificio(A[i], A[i + 1], A[i + 2]) || enClaro(A[i], A[i + 1])) continue;   // ni dentro de los edificios (ni metidos en sus muros) ni en los despegues destacados
        (A[i + 2] < 1.3 ? matas : arboles).push([A[i], A[i + 1], Math.min(3.5, A[i + 2])]);     // mas de 3,5 m de radio es un grupo de copas pegadas, no un arbol
      }
      const Q = new THREE.Quaternion(), S = new THREE.Vector3(), P = new THREE.Vector3(), eje = new THREE.Vector3(0, 1, 0);
      const mat = new THREE.MeshLambertMaterial({ color: 0xffffff }), mTronco = new THREE.MeshLambertMaterial({ color: 0x5b4632 });
      const antes = new Set(g.children);
      // copas con 80 triangulos a menos de 600 m del punto de salida; mas lejos, 20. Tronco en todos (es lo que se ve desde abajo)
      const tronco = rc => rc < 2.5 ? 1.0 + 0.3 * rc : 1.5 + 0.4 * rc;            // altura del tronco (visible entera): almendro 1,4-1,7 m, algarrobo 2,5-2,9
      const cerca = arboles.filter(a => Math.hypot(a[0] - base[1], a[1] - base[0]) < 600), lejos = arboles.filter(a => Math.hypot(a[0] - base[1], a[1] - base[0]) >= 600);
      for (const [lista, det] of [[cerca, 1], [lejos, 0]]) {
        this._instanciarEn(g, new THREE.IcosahedronGeometry(1, det), mat, lista, ([e, n, rc], M, C) => {
          const ht = tronco(rc), alm = rc < 2.5, sy = alm ? 0.55 + 0.15 * r() : 0.8 + 0.2 * r();     // almendro: copa aplanada
          P.set(e, alt(n, e) + ht + rc * sy * 0.85, -n); S.set(rc * (0.9 + 0.2 * r()), rc * sy, rc * (0.9 + 0.2 * r())); Q.setFromAxisAngle(eje, r() * 6.28);
          M.compose(P, Q, S);
          if (alm) C.setHSL(0.21 + 0.04 * r(), 0.2 + 0.1 * r(), 0.27 + 0.08 * r());    // verde grisaceo, mas claro
          else C.setHSL(0.24 + 0.04 * r(), 0.3 + 0.12 * r(), 0.14 + 0.06 * r());       // algarrobo / pino: verde oscuro
        }, 500);
      }
      this._instanciarEn(g, new THREE.CylinderGeometry(0.13, 0.22, 1, 6), mTronco, arboles, ([e, n, rc], M, C) => {
        const ht = tronco(rc), gr = rc < 2.5 ? 1.7 : 2.8; P.set(e, alt(n, e) + ht / 2, -n); S.set(gr, ht * 1.1, gr); Q.identity(); M.compose(P, Q, S); C.setHex(0xffffff);
      }, 500);
      this._instanciarEn(g, new THREE.IcosahedronGeometry(1, 0), mat, matas, ([e, n, rc], M, C) => {
        P.set(e, alt(n, e) + rc * 0.3, -n); S.set(rc, rc * 0.55, rc); Q.setFromAxisAngle(eje, r() * 6.28); M.compose(P, Q, S);
        C.setHSL(0.17 + 0.06 * r(), 0.22 + 0.1 * r(), 0.2 + 0.08 * r());
      }, 500);
      for (const o of g.children) if (!antes.has(o)) { o.castShadow = true; o.receiveShadow = false; }   // las copas no necesitan recibir sombra
      if ((this.escena.userData.zonaGrupos || []).includes(g))       // solidos (Entorno.chocaArbol), si la zona sigue puesta
        this.entorno.ponerArboles("zona:" + z.meta.id, arboles.map(([e, n, rc]) => [e, n, ...arbolZona(rc, alt(n, e))]));
    }).catch(e => console.warn("Sin arboles de la zona:", e));
  },
});

/** Textura de un modulo de fachada (3,5 m de ancho por una planta de 3 m) que se repite: "claro" (pared blanca que tine
 *  el color del vertice, ventana de 2,1 x 1,2 m con su marco) o "ladrillo" (caravista rojo con llagas y una ventana alta
 *  apaisada, como los talleres del CIFP). La misma que fachada() de mundo_3d.gd en Godot. */
Visor.texturaFachada = function (tipo, renderer) {
  Visor._fachadas = Visor._fachadas || {};
  if (Visor._fachadas[tipo]) return Visor._fachadas[tipo];
  const N = 128, [c, g] = lienzo(N, N), img = g.createImageData(N, N), r = semilla(tipo === "ladrillo" ? 61 : 43);
  const pon = (x, y, R, G, B) => { const q = 4 * (y * N + x); img.data[q] = R; img.data[q + 1] = G; img.data[q + 2] = B; img.data[q + 3] = 255; };
  const ventana = tipo === "ladrillo" ? [44, 84, 22, 42] : [26, 102, 36, 87];          // x0, x1, y0, y1 (fila 0 = arriba de la planta)
  const ladrillos = [];
  if (tipo === "ladrillo") for (let f = 0; f < 32; f++) for (let k = 0; k < 9; k++) ladrillos.push(0.85 + 0.25 * r());
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    let R, G, B;
    if (tipo === "ladrillo") {                                        // hiladas de 4 px (7 cm), ladrillos de 15 px a soga
      const f = y >> 2, xo = (x + (f & 1) * 7) % N, k = Math.floor(xo / 15), llaga = (y & 3) === 3 || xo % 15 === 14, t = ladrillos[f * 9 + Math.min(8, k)];
      [R, G, B] = llaga ? [196, 182, 164] : [164 * t, 85 * t, 63 * t];
    } else { const t = 0.96 + 0.04 * r(); [R, G, B] = [244 * t, 241 * t, 236 * t]; }
    const [x0, x1, y0, y1] = ventana;
    if (x >= x0 && x < x1 && y >= y0 && y < y1) {
      const marco = x < x0 + 2 || x >= x1 - 2 || y < y0 + 2 || y >= y1 - 2 || Math.abs(x - (x0 + x1) / 2) < 1;
      [R, G, B] = marco ? [205, 205, 200] : [58 + 30 * (y - y0) / (y1 - y0), 72 + 30 * (y - y0) / (y1 - y0), 86 + 28 * (y - y0) / (y1 - y0)];   // cristal con el reflejo del cielo abajo
    }
    if (y >= y1Alfeizar(ventana) && y < y1Alfeizar(ventana) + 2 && x >= ventana[0] - 2 && x < ventana[1] + 2) [R, G, B] = [215, 210, 200];     // alfeizar
    pon(x, y, R, G, B);
  }
  g.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = renderer ? renderer.capabilities.getMaxAnisotropy() : 1;
  // la v va de abajo (0) arriba (plantas): en el lienzo la fila 0 es arriba, y CanvasTexture lo voltea (flipY): bien
  return (Visor._fachadas[tipo] = t);
};
function y1Alfeizar(v) { return v[3]; }

/** Texturas de los elementos singulares (comunes a todas sus piezas): "bloque" (bloque de hormigon gris de 40 x 20 cm
 *  con llagas, 1,6 m por textura), "hormigon" (gris claro con manchas de humedad, 2,4 m) y "rejilla" (lamas verticales
 *  oscuras de la ventana redonda). Las mismas que textura_singular() de mundo_3d.gd. */
Visor.texturaSingular = function (tipo) {
  Visor._sing = Visor._sing || {};
  if (Visor._sing[tipo]) return Visor._sing[tipo];
  const N = 256, [c, g] = lienzo(N, N), img = g.createImageData(N, N), r = semilla(tipo === "bloque" ? 71 : tipo === "hormigon" ? 73 : 79);
  const tonos = []; for (let k = 0; k < 64; k++) tonos.push(0.9 + 0.14 * r());
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    let v;
    if (tipo === "bloque") {                     // 4 bloques de 64 px a lo ancho, 8 hiladas de 32 px, a matajuntas
      const f = y >> 5, xo = (x + (f & 1) * 32) % N, k = (f * 4 + (xo >> 6)) % 64, junta = (y & 31) >= 30 || (xo & 63) >= 62;
      v = junta ? [150, 150, 146] : [190 * tonos[k], 190 * tonos[k], 185 * tonos[k]];
      const grano = 0.94 + 0.12 * r(); v = v.map(q => q * grano);
    } else if (tipo === "hormigon") {
      const mancha = 0.88 + 0.12 * Math.sin(x * 0.05 + Math.sin(y * 0.03) * 2) * Math.sin(y * 0.021), grano = 0.95 + 0.08 * r();
      v = [205 * mancha * grano, 200 * mancha * grano, 190 * mancha * grano];
    } else if (tipo === "sillar") {              // sillares de piedra (faro): 3 a lo ancho, 6 hiladas, a matajuntas
      const f = Math.floor(y / 43), xo = (x + (f & 1) * 43) % N, k = (f * 3 + Math.floor(xo / 86)) % 64, junta = y % 43 >= 41 || xo % 86 >= 84;
      v = junta ? [168, 164, 152] : [196 * tonos[k], 190 * tonos[k], 176 * tonos[k]];
      const grano = 0.93 + 0.12 * r(); v = v.map(q => q * grano);
    } else if (tipo === "linterna") {            // linterna del faro: cristal oscuro con montantes blancos
      v = (x & 31) < 4 || y < 12 ? [236, 236, 230] : [48 + y * 0.12, 66 + y * 0.12, 82 + y * 0.1];
    } else {                                     // rejilla: lamas verticales cada 16 px
      const lama = (x & 15) < 9; v = lama ? [62, 66, 70] : [22, 24, 26];
    }
    const q = 4 * (y * N + x); img.data[q] = v[0]; img.data[q + 1] = v[1]; img.data[q + 2] = v[2]; img.data[q + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8;
  return (Visor._sing[tipo] = t);
};

/** Cartel de un singular: a la izquierda un cuadro naranja con un engranaje blanco y, a la derecha, el panel gris
 *  oscuro con las lineas de texto (el nombre del centro). Mismo dibujo que textura_cartel() de mundo_3d.gd. */
Visor.texturaCartel = function (p) {
  const H = 256, W = Math.round(H * p.ancho / p.alto), [c, g] = lienzo(W, H);
  g.fillStyle = "#f4f4f2"; g.fillRect(0, 0, W, H);
  const m = 10, lado = H - 2 * m;
  g.fillStyle = "#ec7a26"; g.fillRect(m, m, lado, lado);                                   // cuadro naranja con el engranaje
  const cx = m + lado / 2, cy = m + lado / 2;
  g.fillStyle = "#ffffff"; g.beginPath();
  for (let k = 0; k < 24; k++) { const a = k / 24 * 2 * Math.PI, rr = k % 2 ? 0.30 : 0.38; g.lineTo(cx + Math.cos(a) * lado * rr, cy + Math.sin(a) * lado * rr); }
  g.closePath(); g.fill(); g.fillStyle = "#ec7a26"; g.beginPath(); g.arc(cx, cy, lado * 0.14, 0, 2 * Math.PI); g.fill();
  g.strokeStyle = "#ffffff"; g.lineWidth = 5; g.beginPath(); g.ellipse(cx, cy, lado * 0.46, lado * 0.17, 0.6, 0, 2 * Math.PI); g.stroke();
  const x0 = m + lado + 8; g.fillStyle = "#3d4247"; g.fillRect(x0, m, W - x0 - m, H - 2 * m);  // panel gris oscuro con el texto
  let y = m + 14; const total = p.lineas.reduce((s, l) => s + l[2], 0), esc = (H - 2 * m - 28) / total;
  const ancho = W - x0 - m - 44;                                                        // el texto cabe a lo ancho del panel
  for (const [txt, col, tam] of p.lineas) {
    const px = tam * esc; let f = Math.round(px * 0.92); g.font = "bold " + f + "px sans-serif";
    const w = g.measureText(txt).width; if (w > ancho) { f = Math.floor(f * ancho / w); g.font = "bold " + f + "px sans-serif"; }
    g.fillStyle = col; g.textBaseline = "top"; g.fillText(txt, x0 + 22, y + (px - f) / 2); y += px;
  }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
  return t;
};

/** Banderas (3 x 2): "es" (roja, amarilla y roja, 1:2:1), "ue" (azul con 12 estrellas amarillas en circulo) y "murcia"
 *  (carmesi con cuatro castillos y siete coronas, simplificados). Las mismas que textura_bandera() de mundo_3d.gd. */
Visor.texturaBandera = function (tipo) {
  Visor._band = Visor._band || {};
  if (Visor._band[tipo]) return Visor._band[tipo];
  const W = 192, H = 128, [c, g] = lienzo(W, H);
  if (tipo === "es") { g.fillStyle = "#c60b1e"; g.fillRect(0, 0, W, H); g.fillStyle = "#ffc400"; g.fillRect(0, H / 4, W, H / 2); }
  else if (tipo === "ue") {
    g.fillStyle = "#003399"; g.fillRect(0, 0, W, H); g.fillStyle = "#ffcc00";
    for (let k = 0; k < 12; k++) { const a = k / 12 * 2 * Math.PI, x = W / 2 + Math.cos(a) * 38, y = H / 2 + Math.sin(a) * 38; g.beginPath(); for (let q = 0; q < 10; q++) { const b = q / 10 * 2 * Math.PI - Math.PI / 2, rr = q % 2 ? 2.6 : 6.5; g.lineTo(x + Math.cos(b) * rr, y + Math.sin(b) * rr); } g.fill(); }
  } else {
    g.fillStyle = "#9b1b30"; g.fillRect(0, 0, W, H); g.fillStyle = "#f2c230";
    for (const [x, y] of [[10, 10], [34, 10], [10, 34], [34, 34]]) { g.fillRect(x, y + 6, 18, 12); g.fillRect(x + 2, y + 2, 4, 5); g.fillRect(x + 12, y + 2, 4, 5); }     // castillos
    for (let k = 0; k < 7; k++) { const x = 150 + (k % 2) * 16, y = 14 + k * 15; g.beginPath(); g.moveTo(x, y + 8); g.lineTo(x + 3, y); g.lineTo(x + 6, y + 5); g.lineTo(x + 9, y); g.lineTo(x + 12, y + 8); g.fill(); }   // coronas
  }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
  return (Visor._band[tipo] = t);
};
