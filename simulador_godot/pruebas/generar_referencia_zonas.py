"""Referencia del suelo con VARIAS zonas de detalle (Entorno.ponerZonas de simulador/js/entorno.js), para
pruebas/prueba_zonas.gd: altura y agua en una rejilla que cruza la costura entre dos zonas pegadas y sus bordes libres.
Uso: python simulador_godot/pruebas/generar_referencia_zonas.py [zona_a] [zona_b]   (por defecto mm_n03_e23 y mm_n03_e26)
Necesita las dos zonas en simulador/zonas/ (analisis/mundo_cartagena/zona.py) y Playwright con el Chrome del sistema."""
import json, pathlib, sys
from playwright.sync_api import sync_playwright

RAIZ = pathlib.Path(__file__).resolve().parents[2]
A = sys.argv[1] if len(sys.argv) > 1 else "mm_n03_e23"
B = sys.argv[2] if len(sys.argv) > 2 else "mm_n03_e26"
JS = r"""
async ([a, b]) => {
  const mundo = Mundos.datos("cartagena"); entorno.ponerMundo(mundo);
  const idx = await indiceZonas(), za = await cargarZona(idx.find(z => z.id === a)), zb = await cargarZona(idx.find(z => z.id === b));
  entorno.ponerZonas([za, zb]);
  const Z = za.meta, out = [];
  // rejilla de 41 x 61 puntos que cubre las dos zonas y 300 m alrededor (bordes libres, costura y fuera)
  const N0 = Math.min(za.meta.N0, zb.meta.N0) - 300, N1 = Math.max(za.meta.N0, zb.meta.N0) + Z.lado_m + 300;
  const E0 = Math.min(za.meta.E0, zb.meta.E0) - 300, E1 = Math.max(za.meta.E0, zb.meta.E0) + Z.lado_m + 300;
  for (let i = 0; i <= 40; i++) for (let j = 0; j <= 60; j++) {
    const N = N0 + (N1 - N0) * i / 40 + 0.37, E = E0 + (E1 - E0) * j / 60 + 0.61;
    out.push([N, E, entorno.altura(N, E), entorno.enMar(N, E) ? 1 : 0]);
  }
  // y una linea fina que cruza la costura (cada 2 m, 400 m)
  const costa = za.meta.E0 + Z.lado_m === zb.meta.E0 ? zb.meta.E0 : za.meta.E0;
  for (let k = -100; k <= 100; k++) { const N = Z.N0 + Z.lado_m * 0.37, E = costa + 2 * k + 0.13; out.push([N, E, entorno.altura(N, E), entorno.enMar(N, E) ? 1 : 0]); }
  return { zonas: [a, b], puntos: out };
}
"""
with sync_playwright() as p:
    br = p.chromium.launch(channel="chrome", args=["--use-angle=swiftshader", "--allow-file-access-from-files"])
    pg = br.new_page(); pg.goto((RAIZ / "simulador" / "simulador.html").as_uri())
    pg.wait_for_function("() => { try { return !!Mundos.datos('cartagena'); } catch (e) { return false; } }", timeout=60000)
    ref = pg.evaluate(JS, [A, B]); br.close()
(RAIZ / "simulador_godot" / "pruebas" / "referencia_zonas_js.json").write_text(json.dumps(ref), encoding="utf-8")
print("referencia_zonas_js.json: %d puntos de %s + %s" % (len(ref["puntos"]), A, B))
