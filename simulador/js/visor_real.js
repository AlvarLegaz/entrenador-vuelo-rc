"use strict";
// =====================================================================
//  MUNDO REAL DE DETALLE (simulador del navegador, v1). Amplia el Visor con:
//   - la ortofoto PNOA de toda la region (mundos/<id>_orto.jpg) como suelo lejano, en el GPS y en el mapa de salida;
//   - la ZONA DE DETALLE (zonas/<id>/, la misma que lee el simulador de Godot, v2): terreno del MDT a 5 m con la
//     ortofoto a 0,5 m, edificios del Catastro con sus plantas reales y los arboles detectados en la ortofoto.
//   - carreteras y edificios genericos de OSM fuera de la zona (dentro estan los de verdad).
//  Los datos se generan con analisis/mundo_cartagena/zona.py y orto_region.py.
// =====================================================================
const arbolesSinteticos = Visor.prototype._arbolesMundo;      // sin la ortofoto de la region, los arboles de antes
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
      // pixeles de la ortofoto (a 24 m) para poner los arboles de la region donde hay vegetacion, como Godot
      try {
        const w = Math.round(img.width / 2), h = Math.round(img.height / 2), [cp, gp] = lienzo(w, h); gp.drawImage(img, 0, 0, w, h);
        this._ortoPix = { d: gp.getImageData(0, 0, w, h).data, w, h };
        if (this.arbolesNE) this._arbolesMundo(esc, m, this.arbolesNE[0], this.arbolesNE[1]);
      } catch (e) { console.warn("Sin los pixeles de la ortofoto de la region:", e); }
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
    ent.ponerEdificios("sinteticos", edificios.map(([e, n, s, tipo, z]) => {          // solidos: la planta girada y su altura
      const h = tipo === 1 ? 4 + z * 7 : 6 + z * 6, d = s * (0.7 + z * 0.5), c = Math.cos(z * 3.14), sn = Math.sin(z * 3.14), y = alt(n, e), P = [];
      for (const [cx, cz] of [[-s / 2, -d / 2], [s / 2, -d / 2], [s / 2, d / 2], [-s / 2, d / 2]]) P.push(e + cx * c + cz * sn, n - (-cx * sn + cz * c));
      return [P, y, y + h];
    }));
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
    this.entorno.quitarArboles("zona:"); this.entorno.quitarEdificios("zona:");      // los arboles y edificios solidos de las zonas que se quitan
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
    if (this._marPlano) this._lagunaTransparente(this._marPlano, this._marT);   // bajo las zonas, el mar es el de la ortofoto
  },

  /** Lo que hay que ver en un trabajo del modo Operaciones (escenarios.js, "operacion"; las reglas en js/operaciones.js),
   *  o null para quitarlo: la plataforma de despegue, las placas numeradas de la inspeccion, los jalones de la parcela o
   *  de la zona de busqueda, el senderista, las manchas de plaga y las torres y cables de la linea. casa: [N, E]. */
  ponerOperacion(d, casa) {
    if (this.operacion) { this.operacion.parent && this.operacion.parent.remove(this.operacion); liberar(this.operacion); this.operacion = null; }
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
    if (d.parcela && d.parcela.poligono) for (const [N, E] of d.parcela.poligono) jalon(N, E, "#2e7d32");      // el bancal: un jalon en cada esquina
    else if (d.parcela) esquinas(d.parcela, d.solape ? "#e53935" : "#2e7d32");
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
    if (d.planta) {                                                     // paneles: mesas de modulos inclinadas al sur, patas y los modulos danados
      const op = new Operacion(d, () => {}, () => {}, { casa, suelo: alt, h0 }), P = d.planta, inc = P.inclinacion * D2R;
      const [cm, gm] = lienzo(256, 64); gm.fillStyle = "#c9d3dc"; gm.fillRect(0, 0, 256, 64);            // 8 modulos de 1 x 2 m a lo ancho de la textura
      for (let k = 0; k < 8; k++) { gm.fillStyle = "#14294d"; gm.fillRect(k * 32 + 1, 1, 30, 62); gm.strokeStyle = "rgba(160,190,230,0.35)"; gm.lineWidth = 0.6;
        for (let y = 8; y < 64; y += 8) { gm.beginPath(); gm.moveTo(k * 32 + 1, y); gm.lineTo(k * 32 + 31, y); gm.stroke(); }
        for (let x = 6; x < 32; x += 6) { gm.beginPath(); gm.moveTo(k * 32 + x, 1); gm.lineTo(k * 32 + x, 63); gm.stroke(); } }
      const tm = texSRGB(cm); tm.wrapS = THREE.RepeatWrapping; tm.repeat.set((P.tramo || P.largo) / 8, 1);
      const mPanel = new THREE.MeshStandardMaterial({ map: tm, roughness: 0.25, metalness: 0.3 }), mAcero = std(0xb0b6bb, { metalness: 0.6, roughness: 0.4 });
      // giro de las mesas: su eje x a lo largo de la fila (rumbo), inclinadas sobre ese eje con el borde alto hacia la fila siguiente
      const yaw = Math.atan2(op.pl.cr, op.pl.sr), geoP = new THREE.BoxGeometry(1, 0.05, P.ancho);
      for (const M of op.mesas) {
        const panel = new THREE.Mesh(geoP, [mAcero, mAcero, mPanel, mAcero, mAcero, mAcero]), [n, e] = op.ne((M.l0 + M.l1) / 2, M.t);
        panel.scale.x = M.l1 - M.l0; panel.position.set(e, M.y + P.h0 + P.ancho * Math.sin(inc) / 2, -n); panel.rotation.order = "YXZ"; panel.rotation.set(inc, yaw, 0);
        G.add(panel);
      }
      // patas (delante cortas, detras largas) cada 6 m: una sola malla instanciada para todas
      const patas = []; for (const M of op.mesas) for (let x = M.l0 + 2; x < M.l1; x += 6) for (const s of [-1, 1]) patas.push([x, M, s]);
      const ip = new THREE.InstancedMesh(new THREE.BoxGeometry(0.08, 1, 0.08), mAcero, patas.length), Mx = new THREE.Matrix4();
      patas.forEach(([x, M, s], k) => { const h = P.h0 + (s > 0 ? P.ancho * Math.sin(inc) : 0) * 0.92, [n, e] = op.ne(x, M.t + s * M.fondo * 0.42); ip.setMatrixAt(k, Mx.makeScale(1, h, 1).setPosition(e, M.y + h / 2, -n)); });
      G.add(ip);
      op.modulos.forEach(([n, e, y], k) => {                                 // modulos danados: cristal roto (grietas) o excrementos de aves (manchas blancas)
        const [cd, gd] = lienzo(64, 128), roto = k % 2 === 0;
        gd.fillStyle = "#24365c"; gd.fillRect(0, 0, 64, 128);
        if (roto) { gd.strokeStyle = "#e8eef5"; gd.lineWidth = 2; for (let r = 0; r < 9; r++) { const a = r * 0.7; gd.beginPath(); gd.moveTo(32, 64); gd.lineTo(32 + 40 * Math.cos(a), 64 + 70 * Math.sin(a)); gd.stroke(); } }
        else for (const [x, yy, r] of [[32, 60, 9], [18, 30, 5], [44, 92, 6], [24, 100, 4], [48, 40, 4], [12, 74, 3], [52, 16, 3]]) {
          gd.fillStyle = "#f2f0e8"; gd.beginPath(); gd.arc(x, yy, r, 0, 7); gd.fill();
          gd.fillStyle = "#8a8578"; gd.beginPath(); gd.arc(x, yy, r * 0.4, 0, 7); gd.fill();
        }
        const o = new THREE.Mesh(new THREE.PlaneGeometry(1, 2), new THREE.MeshStandardMaterial({ map: texSRGB(cd), roughness: 0.5 }));
        o.position.set(e, y + 0.04, -n); o.rotation.order = "YXZ"; o.rotation.set(-Math.PI / 2 + inc, yaw, 0); G.add(o);      // sobre el panel, con su inclinacion
      });
    }
    G.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    if (d.racks || d.calientes) this._termicos(G, new Operacion(d, () => {}, () => {}, { casa, suelo: alt, h0 }), d);
    this.operacion = G; this.escena.add(G);
  },

  /** Lo que solo se ve con la camara termica (capa 1: la camara normal no la dibuja) en colores clave para el sombreador
   *  de la termica (visor.js, _renderTermico): caliente en rojo puro con el calor en el azul, frio en verde puro. Y lo
   *  que se ve tambien a simple vista: la placa de la boca de la antorcha y la llama de su piloto. op: la Operacion del
   *  trabajo (mismos datos sorteados), con sus objetos termicos (puntos calientes, vapor, chimeneas, antorcha, fuga). */
  _termicos(G, op, d) {
    const clave = T => { const c = opCalor(T); return c >= 0.55 ? new THREE.Color(1, 0, (c - 0.55) / 0.45) : new THREE.Color(0, 1, c / 0.15); };
    const mat = T => new THREE.MeshBasicMaterial({ color: clave(T), toneMapped: false, fog: false });
    const capa1 = o => { o.layers.set(1); o.castShadow = false; o.receiveShadow = false; G.add(o); return o; };
    for (const o of op.termicos) {
      const [n0, e0, y0] = o.P0, [n1, e1, y1] = o.P1, L = Math.hypot(n1 - n0, e1 - e0, y1 - y0);
      if (L < 0.01) { const s = capa1(new THREE.Mesh(new THREE.SphereGeometry(o.r, 12, 8), mat(o.T))); s.position.set(e0, y0, -n0); continue; }
      const c = capa1(new THREE.Mesh(new THREE.CylinderGeometry(o.r, o.r, L, 12), mat(o.T)));
      c.position.set((e0 + e1) / 2, (y0 + y1) / 2, -(n0 + n1) / 2);
      c.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), new THREE.Vector3(e1 - e0, y1 - y0, -(n1 - n0)).normalize());
    }
    if (d.racks) {
      // el penacho de la fuga: gas frio que se aleja con el viento, cada vez mas ancho
      const v = this.entorno.viento, rv = v && v.base > 0.2 ? v.rumbo : 0, [N, E, up] = op.valvula;
      for (let k = 1; k <= 6; k++) {
        const s = capa1(new THREE.Mesh(new THREE.SphereGeometry(0.5 + 0.35 * k, 10, 8), mat(-15 + 3 * k)));
        s.position.set(E + 1.5 * k * Math.sin(rv), up - 0.25 * k, -(N + 1.5 * k * Math.cos(rv)));
      }
      // la placa de la antorcha (se lee con el zoom) y la llama del piloto (si esta encendido)
      const [pn, pe, py, pr] = op.placa, [c, g] = lienzo(256, 128);
      g.fillStyle = "#f2f2f2"; g.fillRect(0, 0, 256, 128); g.strokeStyle = "#111"; g.lineWidth = 8; g.strokeRect(4, 4, 248, 120);
      g.fillStyle = "#111"; g.font = "bold 80px sans-serif"; g.textAlign = "center"; g.textBaseline = "middle"; g.fillText(d.placaTxt, 128, 68);
      const pl = new THREE.Mesh(new THREE.PlaneGeometry(1.6, 0.8), new THREE.MeshStandardMaterial({ map: texSRGB(c), roughness: 0.6 }));
      pl.position.set(pe, py, -pn); pl.rotation.y = Math.PI - pr * Math.PI / 180; G.add(pl);
      if (d.piloto) {
        const [bn, be, by] = op.boca;
        for (const [r, h, col] of [[0.45, 1.8, 0xff7a1a], [0.22, 1.1, 0xffe27a]]) {
          const f = new THREE.Mesh(new THREE.ConeGeometry(r, h, 12), new THREE.MeshBasicMaterial({ color: col, transparent: true, opacity: 0.85, depthWrite: false }));
          f.position.set(be, by + h / 2, -bn); G.add(f);
        }
      }
    }
  },

  /** Elementos singulares del mundo (simulador/singulares.js, comun con Godot): la entrada del CIFP Politecnico... */
  _singulares(esc, m) {
    if (esc.userData.singulares) { esc.remove(esc.userData.singulares); liberar(esc.userData.singulares); }
    const g = new THREE.Group(); esc.add(g); esc.userData.singulares = g;
    const alt = this.entorno.altura, T = Visor.texturaSingular;
    const mat = (tex, rep, extra) => { const t = tex.clone(); t.needsUpdate = true; if (rep) t.repeat.set(rep[0], rep[1]); return new THREE.MeshStandardMaterial(Object.assign({ map: t, roughness: 0.9, metalness: 0 }, extra || {})); };
    const cara = (obj, rumbo) => { obj.rotation.y = Math.PI - rumbo * Math.PI / 180; };      // la cara +z de la pieza mira a "rumbo"
    const prims = [], solidos = [];                    // instalaciones industriales (js/industria.js): instancias
    for (const S of (window.SINGULARES || []).filter(q => q.mundo === m.id)) for (const p of S.piezas) {
      if (Industria.TIPOS.includes(p.tipo)) {
        for (const q of Industria.primitivas(p)) prims.push(q);
        const [P, h] = Industria.solido(p); let e = 0, n = 0;
        for (let i = 0; i < P.length; i += 2) { e += P[i] * 2 / P.length; n += P[i + 1] * 2 / P.length; }
        const y = alt(n, e); solidos.push([P, y - 0.3, y + h]);
      } else if (p.tipo === "muro") {
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
    if (prims.length) {
      const formas = [new THREE.BoxGeometry(1, 1, 1), new THREE.CylinderGeometry(0.5, 0.5, 1, 20), new THREE.CylinderGeometry(0.5, 0.5, 1, 16).rotateZ(Math.PI / 2), new THREE.SphereGeometry(0.5, 20, 12)];
      const M = new THREE.Matrix4(), Q = new THREE.Quaternion(), V = new THREE.Vector3(), E = new THREE.Vector3(), C = new THREE.Color(), Y = new THREE.Vector3(0, 1, 0);
      const colores = Industria.COLORES.map(h => new THREE.Color(h));
      formas.forEach((geo, f) => {
        geo.translate(0, 0.5, 0); const L = prims.filter(q => q[0] === f);
        if (!L.length) return;
        const im = new THREE.InstancedMesh(geo, new THREE.MeshStandardMaterial({ roughness: 0.6, metalness: 0.15 }), L.length);
        L.forEach(([, e, n, y0, sx, sy, sz, R, c], i) => {
          Q.setFromAxisAngle(Y, (90 - R) * Math.PI / 180); M.compose(V.set(e, alt(n, e) + y0, -n), Q, E.set(sx, sy, sz));
          im.setMatrixAt(i, M); im.setColorAt(i, C.copy(colores[c]));
        });
        im.computeBoundingSphere(); g.add(im);
      });
    }
    this.entorno.ponerEdificios("singulares", solidos);
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
      const malla = new THREE.Mesh(geo, conGrano(new THREE.MeshLambertMaterial({ map: tex, side: THREE.DoubleSide })));
      malla.receiveShadow = true; g.add(malla);
    }
  },

  /** Edificios del Catastro: cada huella extruida a sus plantas (3 m por planta) desde la cota del terreno. Tejados con
   *  la propia ortofoto de la zona (la tesela de su centro: se ven las cubiertas reales, lucernarios, placas...), fachadas
   *  con una ventana por planta y modulo de 3,5 m (VentanasFachada) del color claro de siempre o, si la zona lo trae
   *  ("f", p. ej. el ladrillo del CIFP Politecnico), con ese color y textura de ladrillo. Igual que _edificios_zona de Godot. */
  _edificiosZona(g, z) {
    this._edificiosDe(z).then(lista => {
      this.entorno.ponerEdificios("zona:" + z.meta.id, lista.filter(ed => ed.p.length >= 6).map(ed => [ed.p, ed.b - this.mundo.terreno.h0 - 0.4, ed.b - this.mundo.terreno.h0 + ed.pl * 3.0 + 0.5]));
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

  /** Arboles de la region fuera de las zonas de detalle (_arboles_de_la_region de Godot): un arbol donde la ortofoto de
   *  la region es vegetacion (verde y oscura), con su color algo oscurecido, cada 24 m hasta 2,5 / 4,5 / 7 km segun la
   *  calidad. Sin la ortofoto todavia, los de antes (sinteticos). */
  _arbolesMundo(esc, m, cN, cE) {
    if (!this._ortoPix) return arbolesSinteticos.call(this, esc, m, cN, cE);
    for (const o of esc.userData.arboles || []) { esc.remove(o); o.geometry.dispose(); const i = this.lejanos.indexOf(o); if (i >= 0) this.lejanos.splice(i, 1); }
    esc.userData.arboles = []; this.arbolesNE = [cN, cE];
    const ent = this.entorno, alt = ent.altura, T = m.terreno, Pp = this._ortoPix, W = Pp.w, H = Pp.h, mpx = (T.nE - 1) * T.paso / W;
    const r = semilla(11 + Math.trunc(cN / 97) + Math.trunc(cE / 89)), antes = new Set(esc.children);
    const arboles = [], paso = 24, R = [2500, 4500, 7000][this.calidad];
    for (let n = -R; n <= R && arboles.length < 60000; n += paso) for (let e = -R; e <= R && arboles.length < 60000; e += paso) {
      const ee = cE + e + (r() - 0.5) * paso, nn = cN + n + (r() - 0.5) * paso;
      if (e * e + n * n > R * R || this._enZonas(nn, ee, 10)) continue;
      const x = Math.floor((ee - T.E0) / mpx), y = Math.floor(H - 1 - (nn - T.N0) / mpx);
      if (x < 0 || y < 0 || x >= W || y >= H) continue;
      const k = 4 * (y * W + x), cr = Pp.d[k] / 255, cg = Pp.d[k + 1] / 255, cb = Pp.d[k + 2] / 255, lum = 0.3 * cr + 0.59 * cg + 0.11 * cb;
      if (!(cg > cr * 0.97 && cg > cb * 1.08 && lum < 0.45 && lum > 0.08)) continue;
      if (r() > 0.7 || ent.enMar(nn, ee)) continue;
      const os = 1 - (0.05 + 0.2 * r());
      if (Math.hypot(ee - cE, nn - cN) >= 25) arboles.push([ee, nn, 2 + r() * 2, cr * os, cg * os, cb * os]);      // claro de 25 m en el punto de salida
    }
    const Q = new THREE.Quaternion(), S = new THREE.Vector3(), P = new THREE.Vector3(), eje = new THREE.Vector3(0, 1, 0);
    this._instanciarEn(esc, new THREE.SphereGeometry(1, 6, 3), materialCopas(), arboles, ([e, n, s, a, b, c], M, C) => {
      P.set(e, alt(n, e) + s * 0.75, -n); S.set(s, s * 0.8, s); Q.setFromAxisAngle(eje, s * 5); M.compose(P, Q, S); C.setRGB(a, b, c, THREE.SRGBColorSpace);
    }, 1000, 4000, [cE, -cN]);
    for (const o of esc.children) if (!antes.has(o)) { esc.userData.arboles.push(o); o.castShadow = true; }
    // solidos (Entorno.chocaArbol): la copa, una esfera de radio s a 0,75 s del suelo achatada al 80 %
    ent.ponerArboles("region", arboles.map(([e, n, s]) => { const y = alt(n, e); return [e, n, 0.9 * s, y, y + 1.55 * s]; }));
  },

  _arbolesZona(g, z) {
    Promise.all([z.datos ? Promise.resolve(z.datos.arboles) : fetch(z.base + z.meta.arboles.archivo).then(r => r.arrayBuffer()).then(b => new Float32Array(b)), this._edificiosDe(z)]).then(([A, edificios]) => {
      const alt = this.entorno.altura, r = semilla(29), base = this.baseNE || [0, 0], enEdificio = this._filtroEdificios(edificios);
      // sin arboles donde no los hay aunque la ortofoto lo parezca (escenarios.js, "sin_arboles": el aparcamiento del CIFP)
      const claros = Object.values(ESCENARIOS).filter(E => E.mundo === this.mundo.id).flatMap(E => (E.destacados || []).concat(E.operacion ? [E.operacion] : [])).filter(d => d.sin_arboles).map(d => d.sin_arboles);   // y donde va la planta fotovoltaica
      const enClaro = (e, n) => claros.some(P => { let k = false; for (let i = 0, j = P.length - 1; i < P.length; j = i++) if ((P[i][0] > n) !== (P[j][0] > n) && e < (P[j][1] - P[i][1]) * (n - P[i][0]) / (P[j][0] - P[i][0]) + P[i][1]) k = !k; return k; });
      const arboles = [], matas = [];
      for (let i = 0; i < A.length; i += 3) {
        if (Math.hypot(A[i] - base[1], A[i + 1] - base[0]) < 25 + A[i + 2]) continue;   // claro de 25 m alrededor del piloto (como en Godot)
        if (enEdificio(A[i], A[i + 1], A[i + 2]) || enClaro(A[i], A[i + 1])) continue;   // ni dentro de los edificios (ni metidos en sus muros) ni en los despegues destacados
        (A[i + 2] < 1.3 ? matas : arboles).push([A[i], A[i + 1], A[i + 2], r(), r(), r(), r()]);
      }
      const Q = new THREE.Quaternion(), S = new THREE.Vector3(), P = new THREE.Vector3(), eje = new THREE.Vector3(0, 1, 0);
      // como _arboles_zona de Godot: copa con el material de copas (esfera de 12 x 7 cerca del piloto y de 6 x 3 lejos),
      // tronco de 0,9 + 0,45 rc de alto y matas bajas; colores verde oliva
      const mat = materialCopas(), mTronco = new THREE.MeshLambertMaterial({ color: 0x5b4632 });
      const antes = new Set(g.children);
      const ht = rc => 0.9 + 0.45 * rc;
      const copa = ([e, n, rc, a0, a1, a2, a3], M, C) => {
        P.set(e, alt(n, e) + ht(rc) + rc * 0.55, -n); S.set(rc, rc * (0.7 + 0.25 * a1), rc); Q.setFromAxisAngle(eje, a0 * 2 * Math.PI); M.compose(P, Q, S);
        C.setHSL(0.19 + 0.05 * a2, 0.2 + 0.1 * a3, 0.24 + 0.08 * a1);
      };
      const cerca = arboles.filter(a => Math.hypot(a[0] - base[1], a[1] - base[0]) < 450), lejos = arboles.filter(a => Math.hypot(a[0] - base[1], a[1] - base[0]) >= 450);
      this._instanciarEn(g, new THREE.SphereGeometry(1, 12, 7), mat, cerca, copa, 500);
      this._instanciarEn(g, new THREE.SphereGeometry(1, 6, 3), mat, lejos, copa, 500);
      this._instanciarEn(g, new THREE.CylinderGeometry(0.12, 0.2, 1, 5, 1, true), mTronco, arboles, ([e, n, rc], M, C) => {
        P.set(e, alt(n, e) + ht(rc) / 2, -n); S.set(rc / 2.2, ht(rc), rc / 2.2); Q.identity(); M.compose(P, Q, S); C.setHex(0xffffff);
      }, 500);
      const nMatas = g.children.length;
      this._instanciarEn(g, new THREE.SphereGeometry(1, 5, 3), mat, matas, ([e, n, rc, a0, a1, a2, a3], M, C) => {
        P.set(e, alt(n, e) + rc * 0.3, -n); S.set(rc, rc * 0.55, rc); Q.setFromAxisAngle(eje, a0 * 2 * Math.PI); M.compose(P, Q, S);
        C.setHSL(0.15 + 0.06 * a2, 0.16 + 0.1 * a3, 0.3 + 0.08 * a1);
      }, 500);
      const sinSombra = new Set(g.children.slice(nMatas));                              // las matas no hacen sombra (como en Godot)
      for (const o of g.children) if (!antes.has(o)) { o.castShadow = !sinSombra.has(o); o.receiveShadow = false; }   // las copas no necesitan recibir sombra
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
