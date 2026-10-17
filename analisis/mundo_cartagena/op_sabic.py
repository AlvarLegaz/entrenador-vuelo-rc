"""El trabajo de operador "Inspección de la fábrica de SABIC" (escenarios.js, op_sabic) con lo que YA hay en la fábrica
(datos/escenarios/singulares.js, entrada de SABIC, generada por sabic_industria.py): no se crea ningún edificio nuevo.

  - racks: los racks de tuberias de mas de 50 m con su centro a menos de 430 m del despegue; entre ellos se sortean los
    puntos calientes (aislamiento roto) y sus tuberias amarillas son las de vapor (calientes de verdad: distractores);
  - unidades: los recintos de las unidades de proceso de sabic_industria.py (UNIDADES) a menos de 450 m, con la altura
    de su estructura mas alta; en una se sortea la fuga y alrededor esta la zona ATEX;
  - antorcha: la chimenea mas alta a menos de 450 m (en la boca, la placa y el piloto); chimeneas: las demas, templadas.

El despegue es un descampado entre las unidades de policarbonato y el espinazo de racks, comprobado: sin solidos ni
edificios a menos de 15 m.

    python analisis/mundo_cartagena/op_sabic.py
"""
import json, math, os, re, sys

AQUI = os.path.dirname(os.path.abspath(__file__))
SIM = os.path.join(AQUI, "..", "..", "datos")             # datos comunes de los simuladores
sys.path.insert(0, AQUI)
import sabic_industria as SI

SALIDA_UV = (10, -140)                 # (u, v) del despegue en el marco de la fabrica (sabic_industria.py)
R_RACKS, R_UNIDADES = 430, 450


def main():
    Z = json.load(open(os.path.join(SIM, "escenarios", "zonas", "fotovoltaica", "zona.json")))
    N0z, E0z = Z["N0"], Z["E0"]
    EN = lambda u, v: (E0z + 2000 + u * SI.SU + v * SI.CU, N0z + 2000 + u * SI.CU - v * SI.SU)
    s = open(os.path.join(SIM, "escenarios", "singulares.js"), encoding="utf-8").read()
    L = json.loads(s[s.index("window.SINGULARES = ") + 20:s.rindex("]") + 1])
    P = next(q for q in L if q["nombre"] == SI.NOMBRE)["piezas"]
    e_s, n_s = EN(*SALIDA_UV)
    # ---- el despegue, despejado ----
    def dist_pieza(q):
        if q["tipo"] == "rack":
            de, dn = q["e1"] - q["e0"], q["n1"] - q["n0"]; L2 = de * de + dn * dn; t = max(0, min(1, ((e_s - q["e0"]) * de + (n_s - q["n0"]) * dn) / L2))
            return math.hypot(q["e0"] + t * de - e_s, q["n0"] + t * dn - n_s) - q["ancho"] / 2
        return math.hypot(q["e"] - e_s, q["n"] - n_s) - max(q.get("radio", 0), q.get("largo", 0) / 2, q.get("ancho", 0) / 2)
    cerca = min(dist_pieza(q) for q in P)
    ed = json.load(open(os.path.join(SIM, "escenarios", "zonas", "fotovoltaica", "edificios.json")))
    def dist_edif(d):
        p = d["p"]; return min(math.hypot(p[i] - e_s, p[i + 1] - n_s) for i in range(0, len(p), 2))
    cerca_e = min(dist_edif(d) for d in ed)
    print("despegue E %.1f N %.1f: pieza mas cercana a %.0f m, edificio a %.0f m" % (e_s, n_s, cerca, cerca_e))
    assert cerca > 15 and cerca_e > 15, "el despegue no esta despejado"
    # ---- racks ----
    racks = []
    for q in P:
        if q["tipo"] != "rack": continue
        Lr = math.hypot(q["e1"] - q["e0"], q["n1"] - q["n0"])
        if Lr >= 50 and math.hypot((q["e0"] + q["e1"]) / 2 - e_s, (q["n0"] + q["n1"]) / 2 - n_s) <= R_RACKS:
            racks.append({k: q[k] for k in ("e0", "n0", "e1", "n1", "alto", "ancho", "niveles")})
    racks.sort(key=lambda q: math.hypot((q["e0"] + q["e1"]) / 2 - e_s, (q["n0"] + q["n1"]) / 2 - n_s))
    for i, q in enumerate(racks): q["nombre"] = "R-%d" % (i + 1)
    # ---- unidades de proceso: los recintos con su estructura mas alta ----
    estr = [q for q in P if q["tipo"] in ("estructura", "columna")]
    unidades = []
    for (U0, U1, V0, V1) in SI.UNIDADES:
        esq = [EN(U0, V0), EN(U1, V0), EN(U1, V1), EN(U0, V1)]
        ce, cn = sum(x[0] for x in esq) / 4, sum(x[1] for x in esq) / 4
        if math.hypot(ce - e_s, cn - n_s) > R_UNIDADES: continue
        dentro = [q for q in estr if U0 - 2 <= (q["e"] - E0z - 2000) * SI.SU + (q["n"] - N0z - 2000) * SI.CU <= U1 + 2
                  and V0 - 2 <= (q["e"] - E0z - 2000) * SI.CU - (q["n"] - N0z - 2000) * SI.SU <= V1 + 2]
        est = [q for q in dentro if q["tipo"] == "estructura"]
        if not est: continue
        alto = max(q["alto"] for q in dentro)
        # la valvula de la fuga: en la cara de una estructura (la que mas cerca este del centro), a 0,4 de su altura
        unidades.append({"poligono": [[round(n, 1), round(e, 1)] for e, n in esq], "alto": round(alto, 1),
                         "valvulas": [[q["e"], q["n"], round(0.4 * q["alto"], 1), q["largo"], q["ancho"], q["rumbo"]] for q in sorted(est, key=lambda q: math.hypot(q["e"] - ce, q["n"] - cn))[:4]]})
    unidades.sort(key=lambda q: math.hypot(sum(p[1] for p in q["poligono"]) / 4 - e_s, sum(p[0] for p in q["poligono"]) / 4 - n_s))
    for i, q in enumerate(unidades): q["nombre"] = "U-%d" % (i + 1)
    # ---- antorcha y chimeneas ----
    chim = [q for q in P if q["tipo"] == "chimenea"]
    cerca_ch = [q for q in chim if math.hypot(q["e"] - e_s, q["n"] - n_s) <= R_UNIDADES]
    ant = max(cerca_ch, key=lambda q: q["alto"])
    antorcha = {"n": ant["n"], "e": ant["e"], "alto": ant["alto"], "radio": ant["radio"]}
    chimeneas = [{"n": q["n"], "e": q["e"], "alto": q["alto"], "radio": q["radio"]} for q in chim if q is not ant]
    print("racks %d, unidades %d (%s), antorcha %.0f m a %.0f m del despegue" % (len(racks), len(unidades), [u["nombre"] for u in unidades], ant["alto"], math.hypot(ant["e"] - e_s, ant["n"] - n_s)))
    O = {
        "nombre": "Inspección de la fábrica de SABIC",
        "vehiculos": ["dron"],
        "mundo": "cartagena",
        "zona": 3,
        "dificultad": 3,
        "viento": {"vel": 6, "desde": 290, "rachas": True},
        "desc": "Trabajo largo (30 minutos) para pilotos con soltura: tres tareas de mantenimiento en la fábrica de SABIC de La Aljorra con el dron de inspección (zoom y cámara térmica). Prepara antes la estrategia: el orden de las tareas, la altura y por dónde vas a volar entre las unidades de proceso. Las pistas están en el GPS: los racks donde están los puntos calientes, la unidad con la alarma de gas y la antorcha.",
        "objetivos": [
            ["calientes", "Encontrar con la térmica los 4 puntos calientes de los racks: medidor puntual sobre cada uno 3 s, a menos de 15 m (o con zoom)"],
            ["fuga", "Localizar la fuga de gas de la unidad con alarma y medir su temperatura con la térmica"],
            ["atex", "No entrar en la zona ATEX: 30 m alrededor de la unidad con la fuga"],
            ["placa", "Leer con el zoom (28x o más) la placa de la boca de la antorcha: foto desde más de 60 m de altura y a más de 50 m de ella"],
            ["piloto", "Foto con la térmica del piloto de la antorcha (¿encendido o apagado?)"],
            ["unidades", "Nunca a menos de 10 m por encima de las unidades de proceso"],
            ["tiempo", "Las tres tareas en 30 minutos"],
            ["techo", "Sin pasar de 120 m de altura sobre el suelo"],
            ["vlos", "Siempre a la vista: a menos de 500 m del piloto"],
            ["zona", "Fuera de la zona del aeropuerto de San Javier (8 km)"],
            ["casa", "Aterrizar a menos de 10 m del punto de despegue"],
            ["reserva", "Aterrizar con más del 20 % de batería"],
            ["aterrizar", "Aterrizar sin daños"]],
        "operacion": {
            "avion": "HQ3T",
            "cliente": "Fábrica de policarbonato de La Aljorra · mantenimiento y seguridad",
            "lugar": "Fábrica de SABIC, La Aljorra (Cartagena). Despegue en el descampado entre las unidades de policarbonato y el rack principal.",
            "trabajo": "Tres tareas con el dron de inspección: 1) puntos calientes en los racks de tuberías (aislamiento roto: solo se ven con la térmica; las tuberías amarillas de vapor también están calientes y no son averías); 2) fuga de gas en la unidad con alarma: con la térmica el gas sale frío, y no se puede entrar en la zona ATEX de 30 m; 3) la antorcha: leer con el zoom la placa de su boca y comprobar con la térmica si su piloto está encendido. Pistas en el GPS: en naranja los racks con puntos calientes, en rojo la unidad con la alarma y su zona ATEX, y la antorcha.",
            "entrega": "La posición y temperatura de cada punto caliente y de la fuga, la foto de la placa y la foto térmica del piloto.",
            "salida": {"n": round(n_s, 1), "e": round(e_s, 1), "rumbo": 46},
            "racks": racks, "calientes": 4, "unidades": unidades, "antorcha": antorcha, "chimeneas": chimeneas,
            "atex": 30, "sobre_unidades": 10, "dist_caliente": 15, "dist_fuga": 45, "medir_s": 3,
            "placa": {"altura": 60, "distancia": 50, "zoom": 28}, "limite_s": 1800,
            "sin_arboles": [[round(n_s + dn, 1), round(e_s + de, 1)] for dn, de in ((-25, -25), (-25, 25), (25, 25), (25, -25))],
        },
    }
    # ---- a escenarios.js, antes de libre_cartagena (o en su sitio si ya estaba) ----
    sys.path.insert(0, SIM); from leer_datos import escribir             # datos/operaciones/op_sabic.js y la lista de datos/escenarios.js
    print("escrito op_sabic en", escribir("op_sabic", O, "operaciones"))


if __name__ == "__main__":
    main()
