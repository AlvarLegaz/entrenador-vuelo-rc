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
    const Zb = this.zonaBBox, dentro = (e, n) => Zb && n > Zb[0] - 30 && n < Zb[1] + 30 && e > Zb[2] - 30 && e < Zb[3] + 30;
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
    const ent = this.entorno, alt = ent.altura, r = semilla(17), antes = new Set(esc.children), Zb = this.zonaBBox;
    const dentro = (P, x, y) => { let d = false; for (let i = 0, j = P.length - 1; i < P.length; j = i++) { const [xi, yi] = P[i], [xj, yj] = P[j]; if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) d = !d; } return d; };
    const edificios = [];
    for (const u of m.urbano) {
      const P = []; for (let i = 1; i < u.length; i += 2) P.push([u[i], u[i + 1]]);
      let e0 = 1e9, e1 = -1e9, n0 = 1e9, n1 = -1e9; for (const [e, n] of P) { e0 = Math.min(e0, e); e1 = Math.max(e1, e); n0 = Math.min(n0, n); n1 = Math.max(n1, n); }
      const paso = u[0] === 1 ? 48 : 70;
      for (let e = e0; e < e1; e += paso) for (let n = n0; n < n1; n += paso) {
        const ee = e + (r() - 0.5) * paso * 0.7, nn = n + (r() - 0.5) * paso * 0.7;
        if (Zb && nn > Zb[0] - 20 && nn < Zb[1] + 20 && ee > Zb[2] - 20 && ee < Zb[3] + 20) continue;
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
  ponerZona(z) {
    const esc = this.escena, m = this.mundo;
    if (!m) return;
    if (esc.userData.zonaGrupo) {
      esc.userData.zonaGrupo.traverse(o => { if (o.geometry) o.geometry.dispose(); if (o.material && o.material.map) o.material.map.dispose(); });
      esc.remove(esc.userData.zonaGrupo); esc.userData.zonaGrupo = null;
    }
    const terr = esc.userData.terreno, pos = terr && terr.geometry.attributes.position, Y0 = esc.userData.yOriginal;
    if (pos) pos.array.set(Y0);
    this.zonaBBox = z ? [z.meta.N0, z.meta.N0 + z.meta.lado_m, z.meta.E0, z.meta.E0 + z.meta.lado_m] : null;
    this.zonaId = z ? z.meta.id : null;
    if (z && pos) {                                   // el terreno lejano se hunde 25 m bajo la zona: no asoma entre sus mallas
      const Zb = this.zonaBBox, a = pos.array;
      for (let i = 0; i < a.length; i += 3) { const E = a[i], N = -a[i + 2]; if (N > Zb[0] && N < Zb[1] && E > Zb[2] && E < Zb[3]) a[i + 1] -= 25; }
    }
    if (pos) { pos.needsUpdate = true; terr.geometry.computeBoundingSphere(); }
    this._carreterasMundo(esc, m); this._edificiosSinteticos(esc, m);
    if (!z) return;
    const g = new THREE.Group(); esc.add(g); esc.userData.zonaGrupo = g;
    this._terrenoZona(g, z); this._edificiosZona(g, z); this._arbolesZona(g, z);
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
      const malla = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ map: tex, side: THREE.DoubleSide }));
      malla.receiveShadow = true; g.add(malla);
    }
  },

  /** Edificios del Catastro: cada huella extruida a sus plantas (3 m por planta) desde la cota del terreno, con el
   *  tejado del color de la ortofoto y las fachadas claras. Todo en una sola malla. */
  _edificiosZona(g, z) {
    (z.datos ? Promise.resolve(z.datos.edificios) : fetch(z.base + z.meta.edificios.archivo).then(r => r.json())).then(lista => {
      const h0 = this.mundo.terreno.h0, pos = [], col = [], C = new THREE.Color(), Cw = new THREE.Color(), crema = new THREE.Color(0xeee6d8), r = semilla(5);
      for (const ed of lista) {
        const P = []; for (let i = 0; i < ed.p.length; i += 2) P.push(new THREE.Vector2(ed.p[i], ed.p[i + 1]));
        if (P.length < 3) continue;
        const y0 = ed.b - h0 - 0.4, y1 = ed.b - h0 + ed.pl * 3.0 + 0.5;
        C.set(ed.c).convertSRGBToLinear(); C.multiplyScalar(1.08);
        Cw.copy(crema).convertSRGBToLinear().lerp(C, 0.12).multiplyScalar(0.93 + 0.1 * r());
        for (let k = 0; k < P.length; k++) {                      // fachadas
          const a = P[k], b = P[(k + 1) % P.length];
          pos.push(a.x, y0, -a.y, b.x, y0, -b.y, b.x, y1, -b.y, a.x, y0, -a.y, b.x, y1, -b.y, a.x, y1, -a.y);
          for (let q = 0; q < 6; q++) col.push(Cw.r, Cw.g, Cw.b);
        }
        let tri; try { tri = THREE.ShapeUtils.triangulateShape(P, []); } catch (e) { tri = []; }
        for (const t of tri) for (const v of t) { pos.push(P[v].x, y1, -P[v].y); col.push(C.r, C.g, C.b); }   // azotea o tejado
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3)); geo.setAttribute("color", new THREE.Float32BufferAttribute(col, 3));
      geo.computeVertexNormals();
      const malla = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide }));
      malla.castShadow = true; malla.receiveShadow = true; g.add(malla);
    }).catch(e => console.warn("Sin edificios de la zona:", e));
  },

  /** Arboles detectados en la ortofoto: los de copa grande con tronco y copa; los pequenos, como matorral bajo.
   *  Instanciados por celdas de 500 m; mas detalle en las copas cercanas al punto de salida. */
  _arbolesZona(g, z) {
    (z.datos ? Promise.resolve(z.datos.arboles) : fetch(z.base + z.meta.arboles.archivo).then(r => r.arrayBuffer()).then(b => new Float32Array(b))).then(A => {
      const alt = this.entorno.altura, r = semilla(29), base = this.baseNE || [0, 0];
      const arboles = [], matas = [];
      for (let i = 0; i < A.length; i += 3) (A[i + 2] < 1.3 ? matas : arboles).push([A[i], A[i + 1], A[i + 2]]);
      const Q = new THREE.Quaternion(), S = new THREE.Vector3(), P = new THREE.Vector3(), eje = new THREE.Vector3(0, 1, 0);
      const mat = new THREE.MeshLambertMaterial({ color: 0xffffff }), mTronco = new THREE.MeshLambertMaterial({ color: 0x5b4632 });
      const antes = new Set(g.children);
      // copas detalladas (80 triangulos) solo a menos de 400 m del punto de salida; mas lejos, 20 triangulos y sin tronco
      const cerca = arboles.filter(a => Math.hypot(a[0] - base[1], a[1] - base[0]) < 400), lejos = arboles.filter(a => Math.hypot(a[0] - base[1], a[1] - base[0]) >= 400);
      for (const [lista, det] of [[cerca, 1], [lejos, 0]]) {
        this._instanciarEn(g, new THREE.IcosahedronGeometry(1, det), mat, lista, ([e, n, rc], M, C) => {
          const ht = 0.9 + 0.45 * rc; P.set(e, alt(n, e) + ht + rc * 0.55, -n); S.set(rc, rc * (0.7 + 0.25 * r()), rc); Q.setFromAxisAngle(eje, r() * 6.28);
          M.compose(P, Q, S); C.setHSL(0.2 + 0.05 * r(), 0.28 + 0.12 * r(), 0.16 + 0.07 * r());
        }, 500);
      }
      this._instanciarEn(g, new THREE.CylinderGeometry(0.12, 0.2, 1, 5), mTronco, cerca, ([e, n, rc], M, C) => {
        const ht = 0.9 + 0.45 * rc; P.set(e, alt(n, e) + ht / 2, -n); S.set(rc / 2.2, ht, rc / 2.2); Q.identity(); M.compose(P, Q, S); C.setHex(0xffffff);
      }, 500);
      this._instanciarEn(g, new THREE.IcosahedronGeometry(1, 0), mat, matas, ([e, n, rc], M, C) => {
        P.set(e, alt(n, e) + rc * 0.3, -n); S.set(rc, rc * 0.55, rc); Q.setFromAxisAngle(eje, r() * 6.28); M.compose(P, Q, S);
        C.setHSL(0.17 + 0.06 * r(), 0.22 + 0.1 * r(), 0.2 + 0.08 * r());
      }, 500);
      for (const o of g.children) if (!antes.has(o)) { o.castShadow = true; o.receiveShadow = false; }   // las copas no necesitan recibir sombra
    }).catch(e => console.warn("Sin arboles de la zona:", e));
  },
});
