// Inspector HQ-3T: dron de inspección industrial de 920 g, del tipo de los drones comerciales de empresa con cámara
// triple (gran angular, teleobjetivo con zoom híbrido hasta 56x y cámara térmica radiométrica de 640 x 512). Misma
// física y mismo controlador de vuelo que el Mini Dron HQ (clase ModeloCuadricoptero de aviones/DJI_MINI.js), con
// los datos de un dron de su tamaño: 920 g, hélices de 9,4", unos 45 min de vuelo, 15 m/s en modo normal y 21 m/s en
// Sport, ascenso de 6 m/s, aguanta 12 m/s de viento. Lo usan los trabajos de operador que piden térmica y zoom.
// El modelo 3D es el del Mini Dron HQ (ModeloDJI) a escala 1,75 (380 mm de diagonal entre motores) y en gris oscuro,
// como los drones de empresa. "camara": niveles de zoom (1x es el gran angular; hasta "zoom_optico" es el
// teleobjetivo y por encima, zoom digital) y si lleva cámara térmica (tecla C o cruceta derecha).
// (function: no deja nada global salvo lo que registra)
(function () {
  const DATOS = {
    "id": "HQ3T", "nombre": "Inspector HQ-3T", "tipo": "cuadricoptero",
    "descripcion": "Dron de inspección industrial de 920 g con cámara triple: gran angular, teleobjetivo con zoom hasta 56x y cámara térmica. El de los trabajos que piden ver puntos calientes, fugas o leer una placa desde lejos.",
    "ayuda": "Mandos como el Mini Dron HQ (palanca izquierda sube, baja y gira; derecha adelante, atrás y laterales). Cámara: Z acerca y X aleja el zoom (cruceta arriba y abajo del mando), C cambia a la cámara térmica (cruceta a la derecha); en la térmica, la cruz del centro mide la temperatura.",
    "caracteristicas": [["Masa en vuelo", "920 g"], ["Tamaño", "347 × 283 × 108 mm desplegado, 380 mm de diagonal, hélices de 9,4 pulgadas"],
                        ["Empuje máximo", "≈ 2,2 veces el peso (20 N)"], ["Modos de vuelo", "C (Cine) 6 m/s · N (Normal) 15 m/s · S (Sport) 21 m/s"],
                        ["Ascenso / descenso", "C 3 / 3 · N 6 / 6 · S 8 / 6 m/s"], ["Inclinación máxima", "C 15° · N 30° · S 35°"],
                        ["Cámaras", "gran angular (84°), teleobjetivo con zoom hasta 56x y térmica radiométrica 640 × 512 (−20 a 150 °C)"],
                        ["Gimbal", "3 ejes, de −89° a +10°"], ["Volver a casa", "sube a 30 m, vuelve al punto de despegue y aterriza"],
                        ["Batería", "77 Wh: unos 45 min de vuelo"], ["Viento máximo", "12 m/s"],
                        ["Mandos", "modo 2: izquierda gas y guiñada, derecha inclinación; conmutador C/N/S, rueda del gimbal, zoom y térmica"],
                        ["Velocidad de pérdida", "0 m/s (no entra en pérdida)"]],
    "masa_kg": 0.92, "b_m": 0.44, "S_m2": 0.09, "c_m": 0.18, "inercia": { "Ixx": 0.0068, "Iyy": 0.0079, "Izz": 0.0135, "Ixz": 0 }, "cg_mm": [0, 0, 0],
    "propulsion": { "empuje_max_N": 20, "rpm_max": 9000, "D_m": 0.239, "masa_bateria_Wh": 59, "P_max_W": 330 },
    "fc": { "modos": { "C": { "vmax_ms": 6, "vzmax_sube": 3, "vzmax_baja": 3, "inclinacion_grados": 15, "rmax_grados_s": 60, "kv": 0.9 },
                       "N": { "vmax_ms": 15, "vzmax_sube": 6, "vzmax_baja": 6, "inclinacion_grados": 30, "rmax_grados_s": 120, "kv": 1.2 },
                       "S": { "vmax_ms": 21, "vzmax_sube": 8, "vzmax_baja": 6, "inclinacion_grados": 35, "rmax_grados_s": 200, "kv": 1.5 } },
            "rth_altura_m": 30, "kz": 3.5, "ka": 6, "kr": 25, "tau_max": 1.2, "tau_guinada": 0.15, "cda_h": 0.03, "cda_v": 0.07 },
    "mandos": { "expo": 0.3, "prof_max_grados": 30, "aleron_max_grados": 30, "timon_max_grados": 0, "servo_vel_grados_s": 400, "servo_tau_s": 0.02, "izq_der": "inclinación lateral (A/D: giro)" },
    "lanzamiento": { "vel_ms": 0, "cabeceo_grados": 0 }, "compensador_grados": 0,
    "colores": { "fuselaje": 4868682, "ala": 3815994, "estab": 2631720, "moviles": 13840175 },
    "modelo3d": { "escala": 1.75, "carcasa": 5000526, "cuerpo": 4211781, "brazo": 4540238 },
    "camara": { "zoom": [1, 2, 4, 7, 14, 28, 56], "zoom_optico": 7, "termica": true },
    "malla": { "helice_r": 0.12, "helice": [0.166, 0.157, -0.031],
               "luces": [{ "p": [-0.095, 0.09, -0.012], "color": 58998, "patron": "lento" }, { "p": [-0.095, -0.09, -0.012], "color": 16717636, "patron": "lento" },
                         { "p": [-0.07, 0, -0.03], "color": 16777215, "patron": "estrobo" }] }
  };

  // ---- malla de cajas (la del Mini Dron HQ a escala 1,75): solo la usan las vistas que no llevan el modelo detallado ----
  const S = 1.75, V = { fuselaje: { v: [], i: [] }, estab: { v: [], i: [] } };
  function caja(parte, cx, cy, cz, sx, sy, sz, ang = 0) {
    const M = V[parte], b = M.v.length / 3, c = Math.cos(ang), s = Math.sin(ang);
    for (const [ix, iy, iz] of [[-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1], [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]]) {
      const x = ix * sx * S / 2, y = iy * sy * S / 2;
      M.v.push(cx * S + x * c - y * s, cy * S + x * s + y * c, cz * S + iz * sz * S / 2);
    }
    for (const f of [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]) M.i.push(b + f[0], b + f[1], b + f[2], b + f[0], b + f[2], b + f[3]);
  }
  caja("fuselaje", 0, 0, 0, 0.14, 0.08, 0.05);
  caja("estab", 0.078, 0, 0.012, 0.025, 0.032, 0.03);
  const brazos = [[0.095, 0.09], [0.095, -0.09], [-0.095, 0.09], [-0.095, -0.09]];
  for (const [x, y] of brazos) {
    caja("fuselaje", x * 0.62, y * 0.62, -0.004, 0.11, 0.012, 0.008, Math.atan2(y, x));
    caja("estab", x, y, -0.008, 0.02, 0.02, 0.016);
    caja("estab", x * 0.5, y * 0.4, 0.03, 0.01, 0.01, 0.02);
  }
  Object.assign(DATOS.malla, { fuselaje: V.fuselaje, estab: V.estab, helices: brazos.map(([x, y]) => [x * S, y * S, -0.018 * S]) });
  Modelos.registrar(DATOS, "ModeloCuadricoptero");          // por nombre: aviones/DJI_MINI.js puede cargar despues que este fichero
})();
