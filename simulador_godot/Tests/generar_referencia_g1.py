"""Referencia de la fisica del Poli-1 (4 canales: alerones, profundidad y TIMON con mando.guinada) en el navegador, para
simulador_godot/Tests/prueba_g1.gd. Repite en simulador.html (clase ModeloG1 de datos/vehiculos/G1.js) el vuelo de 16 s de
prueba_fisica.gd, con la palanca izquierda de lado moviendo el timon, en las tres configuraciones (diseno, cambiada y
dificultad facil). Uso: python simulador_godot/Tests/generar_referencia_g1.py   (Playwright con el Chrome del sistema)."""
import json, pathlib
from playwright.sync_api import sync_playwright

RAIZ = pathlib.Path(__file__).resolve().parents[2]
JS = r"""
(() => {
  const DT = 0.002, A = Modelos.datos("G1"), out = {};
  const cf = { masa_kg: A.masa_kg * 1.1, cg_mm: A.cg_mm[0] + 5, temperatura: 30, empuje_gf: 800, resistencia: 1.2 };
  for (const [nombre, conf, facil] of [["normal", null, false], ["config", cf, false], ["facil", cf, true]]) {
    const ent = new Entorno(), m = Modelos.crear("G1");
    if (conf) m.configurar(conf);
    m.facil = facil; ent.facil = facil;
    const a = m.estadoInicial();
    a.asim = 0.37; a.p = [0, 0, -80]; a.q = Cuat.desdeEuler(0.05, 0.03, 0.2); a.v = [11, 0.3, 0.1]; a.w = [0, 0, 0]; a.estado = "volando";
    const mm = { pitch: 0, yaw: 0, guinada: 0, trim: m.compensador_grados || 0 }, tr = [];
    for (let i = 0; i <= 16 / DT; i++) {
      const t = i * DT;
      mm.pitch = t >= 10 && t < 14 ? 1 : 0.4 * Math.sin(0.9 * t); mm.yaw = 0.6 * Math.sin(1.7 * t); mm.guinada = 0.5 * Math.sin(1.3 * t + 0.4);
      a.gases = t < 6 ? 1 : t < 12 ? 0.5 : 0;
      if (i % 500 === 0) tr.push({ t, p: a.p.slice(), v: a.v.slice(), w: a.w.slice(), q: a.q.slice(), de: a.de, da: a.da, dr: a.dr, Wh: a.Wh, T: a.T });
      m.servos(a, mm, DT);
      a.agl = -a.p[2]; a.pg = 0.05 * Math.sin(3 * t);
      m.paso(a, ent.vientoA([2, -1, 0.2], a.agl), DT);
    }
    out[nombre] = tr;
  }
  return out;
})()
"""
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome", args=["--use-angle=swiftshader", "--allow-file-access-from-files"])
    pg = b.new_page(); pg.goto((RAIZ / "simulador_web" / "simulador.html").as_uri()); pg.wait_for_function("() => { try { return !!Modelos.datos('G1'); } catch (e) { return false; } }")
    ref = pg.evaluate(JS); b.close()
(RAIZ / "simulador_godot" / "Tests" / "referencia_g1_js.json").write_text(json.dumps(ref), encoding="utf-8")
print("referencia_g1_js.json:", {k: len(v) for k, v in ref.items()})
