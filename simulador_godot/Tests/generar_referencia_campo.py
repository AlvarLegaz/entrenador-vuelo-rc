"""Genera simulador_godot/Tests/referencia_campo_js.json: casos de la isla del campo de vuelo calculados con el Entorno REAL del
simulador del navegador (simulador_web/js/entorno.js), para que simulador_godot/Tests/prueba_campo.gd compare la version de Godot.

Abre simulador_web/simulador.html con Chrome (Playwright, sin ventana) y llama a new Entorno() y a sus metodos con page.evaluate:
contacto con el suelo en la isla (tambien tras volver de un mundo real), una trayectoria por el circuito con tres
ContadorVueltas (sentido libre, +1 y -1), pasadas por la pista 2 (PasadaBaja), cruces de la puerta, diana, enPista,
chocaPilon, distancia y fueraDeLimites, ordenPilones y los datos del campo (pista, circuito, pilon, zona2, limites).

Uso (desde la carpeta del repositorio):  python simulador_godot/Tests/generar_referencia_campo.py
"""
import json
import math
import random
from pathlib import Path

from playwright.sync_api import sync_playwright

AQUI = Path(__file__).resolve().parent
REPO = AQUI.parent.parent
PAGINA = (REPO / "simulador_web" / "simulador.html").as_uri()
SALIDA = AQUI / "referencia_campo_js.json"


def trayectoria_circuito():
    """[t, N, E] alrededor del centro del circuito (100, 0): vueltas en los dos sentidos, cortes por dentro, paso por el
    centro y cambios de velocidad (para la mejor vuelta). Los indices crecientes de los pilones = angulo creciente."""
    pts = []
    t = 0.0
    th = math.pi

    def add(R, th_, dt):
        nonlocal t
        t += dt
        pts.append([round(t, 6), 100 + R * math.cos(th_), R * math.sin(th_)])

    # A: 2,3 vueltas en sentido +1 por fuera (R 140)
    for _ in range(int(2.3 * 2 * math.pi / 0.02)):
        th += 0.02; add(140, th, 0.1)
    # B: media vuelta cerrandose por dentro de los pilones (R 140 -> 60)
    n = int(math.pi / 0.02)
    for k in range(n):
        th += 0.02; add(140 - 80 * k / n, th, 0.1)
    # C: abre otra vez y 2,2 vueltas en sentido -1 (R 140)
    for k in range(40):
        add(60 + 80 * (k + 1) / 40, th, 0.1)
    for _ in range(int(2.2 * 2 * math.pi / 0.02)):
        th -= 0.02; add(140, th, 0.1)
    # D: cruza por el centro (r < 15) en linea recta hasta el punto opuesto
    n0, e0 = 100 + 140 * math.cos(th), 140 * math.sin(th)
    for k in range(1, 61):
        f = k / 60
        t += 0.1
        pts.append([round(t, 6), n0 + (200 - 2 * n0) * f, e0 - 2 * e0 * f])
    th += math.pi
    # E: 1,6 vueltas en sentido +1 mas rapidas y con radio ondulado (mejor vuelta)
    for _ in range(int(1.6 * 2 * math.pi / 0.03)):
        th += 0.03; add(135 + 10 * math.sin(3 * th), th, 0.08)
    # F: 1,3 vueltas en sentido +1 mas lentas
    for _ in range(int(1.3 * 2 * math.pi / 0.02)):
        th += 0.02; add(150, th, 0.13)
    # G: zigzag: cambia de sentido a mitad de un tramo
    for _ in range(60):
        th += 0.03; add(145, th, 0.1)
    for _ in range(120):
        th -= 0.03; add(145, th, 0.1)
    return pts


def pasadas():
    """Lista de puntos [N, E, D] por la pista 2 (N -45, E -35..35, ancho 10 + margen 5, h 2 a 8 m)."""
    p = []

    def recta(n0, e0, h0, n1, e1, h1, pasos=60):
        for k in range(pasos + 1):
            f = k / pasos
            p.append([n0 + (n1 - n0) * f, e0 + (e1 - e0) * f, -(h0 + (h1 - h0) * f)])

    recta(-45, -60, 5, -45, 60, 5)            # buena, hacia el este
    recta(-60, 60, 5, -60, 70, 5, 5)          # sale de la pista
    recta(-44, 60, 4, -46, -60, 6)            # buena, hacia el oeste
    recta(-45, -60, 12, -45, 60, 12)          # demasiado alta
    recta(-45, 60, 1.2, -45, -60, 1.5)        # demasiado baja
    recta(-45, -60, 5, -45, 0, 5)             # entra por el oeste...
    recta(-45, 0, 5, -45, -60, 5)             # ...y vuelve a salir por el oeste
    recta(-45, -50, 5, -45, -10, 5)           # entra y se sale por un lado tras 30 m
    recta(-45, -10, 5, -70, -10, 5)
    recta(-70, -10, 5, -70, 20, 5, 5)
    recta(-30, 10, 30, -60, 10, 30)           # la cruza alta de lado (no avisa)
    recta(-30, 0, 5, -60, 5, 5)               # la cruza baja de lado (sin recorrerla: no avisa)
    recta(-45, -60, 3, -45, 60, 9)            # sube por encima de hmax al final
    recta(-41, 60, 7.9, -49, -60, 2.1)        # justo dentro de los limites
    return p


def main():
    rnd = random.Random(20261013)
    eul = lambda: [rnd.uniform(-0.8, 0.8), rnd.uniform(-0.6, 0.6), rnd.uniform(-3, 3)]
    contacto = [
        {"p": [10, 0, -5], "e": [0, 0, 0], "vn": [10, 0, 1]},          # en el aire
        {"p": [20, 1, 0.3], "e": [0.1, 0.05, 0.2], "vn": [8, 0, 1]},   # aterrizado (bajo el suelo: lo sube a 0)
        {"p": [20, 1, 0], "e": [0, 0, 0], "vn": [8, 0, 3]},            # demasiado descenso
        {"p": [20, 1, 0], "e": [0.6, 0, 0], "vn": [8, 0, 1]},          # ala en el suelo
        {"p": [20, 1, 0], "e": [0, 0, 0], "vn": [13, 0, 1]},           # demasiada velocidad
        {"p": [20, 1, 0], "e": [0, -0.5, 0], "vn": [8, 0, 1]},         # morro en el suelo
        {"p": [3000, -2500, 0.5], "e": [0, 0, 1], "vn": [5, 2, 0.5]},  # lejos (en la isla no hay mar)
    ]
    for _ in range(40):
        contacto.append({"p": [rnd.uniform(-800, 800), rnd.uniform(-800, 800), rnd.uniform(-0.5, 0.2)], "e": eul(),
                         "vn": [rnd.uniform(-15, 15), rnd.uniform(-15, 15), rnd.uniform(-1, 4)]})
    puerta = [[[-115, 50, -10], [-115, 70, -10]], [[-110, 70, -5], [-112, 50, -6]], [[-115, 50, -25], [-115, 70, -25]],
              [[-100, 50, -10], [-100, 70, -10]], [[-160, 50, -10], [-160, 70, -10]], [[-115, 50, -50], [-115, 70, -50]],
              [[-115, 59, -10], [-115, 60, -10]], [[-115, 60, -10], [-115, 61, -10]], [[-115, 55, -10], [-115, 58, -10]]]
    for _ in range(300):
        n, e, h = rnd.uniform(-170, -60), rnd.uniform(40, 80), rnd.uniform(0, 50)
        puerta.append([[n, e, -h], [n + rnd.uniform(-3, 3), e + rnd.uniform(-12, 12), -(h + rnd.uniform(-2, 2))]])
    # la puerta verde (girada: se cruza de norte a sur en N = -135, entre E -31 y -15)
    puerta_verde = [[[-125, -23, -10], [-145, -23, -10]], [[-145, -20, -5], [-125, -22, -6]], [[-125, -23, -25], [-145, -23, -25]],
                    [[-125, -40, -10], [-145, -40, -10]], [[-125, 20, -10], [-145, 20, -10]], [[-125, -23, -50], [-145, -23, -50]],
                    [[-134, -23, -10], [-135, -23, -10]], [[-135, -23, -10], [-136, -23, -10]], [[-130, -23, -10], [-133, -23, -10]],
                    [[-115, 50, -10], [-115, 70, -10]]]
    for _ in range(300):
        n, e, h = rnd.uniform(-150, -120), rnd.uniform(-70, 30), rnd.uniform(0, 50)
        puerta_verde.append([[n, e, -h], [n + rnd.uniform(-12, 12), e + rnd.uniform(-3, 3), -(h + rnd.uniform(-2, 2))]])
    diana = [[-45, 0], [-45, 5], [-45, 5.0001], [-35, 0], [-45, 20], [-45, 21]] + [[rnd.uniform(-80, -10), rnd.uniform(-30, 30)] for _ in range(300)]
    en_pista = [[10, 0, None], [5, 8, None], [4.9, 0, None], [85, 0, None], [85.1, 0, None], [40, 8.1, None], [40, 8, 3], [40, 6, 0]]
    en_pista += [[rnd.uniform(-20, 100), rnd.uniform(-15, 15), rnd.choice([None, 0, 1.5, 5])] for _ in range(400)]
    choca = []
    pil = [[40, -90], [160, -90], [160, 90], [40, 90], [-123, 60], [-107, 60]]
    for s in pil:
        for _ in range(60):
            choca.append([[s[0] + rnd.uniform(-4, 4), s[1] + rnd.uniform(-4, 4), -rnd.uniform(-1, 22)], rnd.choice([0.3, 0.75, 1.2])])
    choca += [[[40, -90, -20.3], 0.1], [[40, -90, -20.31], 0.1], [[40, -91.6, -1], 0.1], [[40, -91.3, 0.5], 0.1]]
    fuera = [[0, 0, -5], [650, 0, -5], [650.01, 0, -5], [-400, 520, -30]] + [[rnd.uniform(-900, 900), rnd.uniform(-900, 900), -rnd.uniform(0, 200)] for _ in range(200)]
    decor = {"pts": [[rnd.uniform(-300, 300), rnd.uniform(-300, 300)] for _ in range(300)] + [[-0.5, -1.5], [255.9, -256.1], [0, 0]],
             "th": [rnd.uniform(-4, 8) for _ in range(200)],
             "en": [[rnd.uniform(-1800, 1800), rnd.uniform(-1800, 1800)] for _ in range(300)] + [[-109.9, 3], [-110.1, 3], [-600, 10]],
             "n": [rnd.uniform(-1700, 1700) for _ in range(200)]}
    entrada = {"decor": decor, "contacto": contacto, "circuito": trayectoria_circuito(), "pasadas": pasadas(), "puerta": puerta, "puerta_verde": puerta_verde,
               "diana": diana, "en_pista": en_pista, "choca": choca, "fuera": fuera}

    js = """(d) => {
      const ent = new Entorno();
      const r = { datos: { pista: ent.pista, circuito: ent.circuito, pilon: ent.pilon, zona2: ent.zona2, limites: ent.limites } };
      const contacto = (lista) => lista.map(c => {
        const q = Cuat.desdeEuler(c.e[0], c.e[1], c.e[2]), av = { p: c.p.slice(), q };
        const res = ent.contactoSuelo(av, c.vn);
        return { q, res, p: av.p };
      });
      r.contacto = contacto(d.contacto);
      r.contactoTrasMundo = null;
      if (Mundos.datos("cartagena")) {           // ida y vuelta a un mundo real: la isla tiene que quedar igual
        ent.ponerMundo(Mundos.datos("cartagena"));
        r.fueraEnMundo = d.fuera.map(p => ent.fueraDeLimites(p));
        r.chocaEnMundo = d.choca.map(([p, s]) => ent.chocaPilon(p, s));
        ent.ponerMundo(null);
        r.contactoTrasMundo = contacto(d.contacto);
      }
      r.circuito = {};
      for (const s of [0, 1, -1]) {
        const cv = ent.contadorVueltas(s), ev = [], P = d.circuito;
        for (let k = 1; k < P.length; k++) {
          const e = cv.actualizar([P[k - 1][1], P[k - 1][2], -50], [P[k][1], P[k][2], -50], P[k][0]);
          if (e) ev.push({ k, e, sig: cv.siguiente() });
        }
        r.circuito[s] = { eventos: ev, vueltas: cv.vueltas, mejor: cv.mejor, ultima: cv.ultima, siguiente: cv.siguiente() };
      }
      const pb = ent.pasadaBaja(), pas = [];
      d.pasadas.forEach((p, k) => { const e = pb.actualizar(p); if (e) pas.push({ k, e }); });
      r.pasadas = { resultados: pas, validas: pb.validas };
      r.puerta = d.puerta.map(([a, b]) => ent.cruzaPuerta(a, b));
      r.puerta_verde = d.puerta_verde.map(([a, b]) => ent.cruzaPuerta(a, b, "verde"));
      r.diana = d.diana.map(([n, e]) => ent.diana(n, e));
      r.en_pista = d.en_pista.map(([n, e, m]) => m === null ? ent.enPista(n, e) : ent.enPista(n, e, m));
      r.choca = d.choca.map(([p, s]) => ent.chocaPilon(p, s));
      r.fuera = d.fuera.map(p => [ent.distancia(p), ent.fueraDeLimites(p)]);
      r.orden = [-1, 0, 1].map(s => ent.ordenPilones(s));
      // generadores del decorado de visor.js (Campo3D los repite): semilla, ruido, fbm, costa, alturaTerreno, bordeMonte
      // y la lista de almendros que sale de pintarCampo (no depende de la escala del lienzo: uno pequeno basta)
      const s23 = semilla(23), D = d.decor;
      const arb = [], [lz, gz] = lienzo(64, 64); pintarCampo(gz, 64 / 1400, -700, 900, arb, ent.zona2);
      r.decor = { semilla: Array.from({ length: 50 }, () => s23()), ruido: D.pts.map(([x, y]) => ruido(x, y)),
                  fbm: D.pts.map(([x, y]) => fbm(x / 37, y / 41)), costa: D.th.map(t => costa(t)),
                  altura: D.en.map(([e, n]) => alturaTerreno(e, n)), borde: D.n.map(n => bordeMonte(n)),
                  arboles: { n: arb.length, muestra: arb.filter((a, i) => i % 97 === 0 || i === arb.length - 1),
                             suma: arb.reduce((s, a) => s + a[0] + 2 * a[1] + 3 * a[2], 0) } };
      return r;
    }"""
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True,
                                args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        pag = nav.new_page()
        errores = []
        pag.on("pageerror", lambda e: errores.append(str(e)))
        pag.goto(PAGINA)
        pag.wait_for_function("typeof Entorno !== 'undefined' && typeof Cuat !== 'undefined'")
        salida = pag.evaluate(js, entrada)
        nav.close()
    if errores:
        print("Errores de la pagina (no afectan a Entorno):", errores[:3])
    if salida["contactoTrasMundo"] is None:
        print("AVISO: no estaba el mundo de Cartagena: sin la prueba de ida y vuelta")
    SALIDA.write_text(json.dumps({"entrada": entrada, "js": salida}, ensure_ascii=False), encoding="utf-8")
    ev = {s: len(salida["circuito"][s]["eventos"]) for s in salida["circuito"]}
    print(f"{SALIDA.name}: {len(contacto)} contactos, {len(entrada['circuito'])} puntos de circuito (sucesos {ev}), "
          f"{len(salida['pasadas']['resultados'])} pasadas, {len(puerta)} puertas, {len(diana)} dianas, "
          f"{len(en_pista)} enPista, {len(choca)} choques, {len(fuera)} limites")
    for s in salida["circuito"]:
        c = salida["circuito"][s]
        print(f"  sentido {s}: {c['vueltas']} vueltas, mejor {c['mejor']}, tipos {sorted(set(e['e']['tipo'] for e in c['eventos']))}")
    print("  almendros de pintarCampo:", salida["decor"]["arboles"]["n"])
    print("  pasadas:", [(x["e"]["ok"], x["e"].get("motivo", "")) for x in salida["pasadas"]["resultados"]])


if __name__ == "__main__":
    main()
