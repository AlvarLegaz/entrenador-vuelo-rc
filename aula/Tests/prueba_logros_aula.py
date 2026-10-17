"""Prueba de los logros del perfil (aula/servidor_aula.py, progreso -> logros y robot): levanta un servidor de prueba con
su propia carpeta de datos, crea un piloto y le manda vuelos como los mandarian los simuladores. Comprueba que cada logro
cuenta lo suyo: horas de ala fija (aviones y el UAV) y de dron (cuadricopteros y FPV; el bipode no cuenta), cada
entrenamiento solo con un vehiculo de su clase (primer_vuelo superado con el avion no vale para el dron), un NO APTO no
cuenta, todas las operaciones, y que el robot solo se desbloquea con los tres.

    python aula/Tests/prueba_logros_aula.py [puerto]      (por defecto 8098)
"""
import json, pathlib, shutil, subprocess, sys, tempfile, time, urllib.error, urllib.request, uuid

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "aula"))
PUERTO = int(sys.argv[1]) if len(sys.argv) > 1 else 8098
BASE = "http://127.0.0.1:%d" % PUERTO
fallos = 0



def alta_profesor(base, pin, usuario, clave):
    """El alumno, dado de alta por el profesor desde su panel (ya aprobado): los que se registran desde el simulador quedan
    pendientes hasta que el profesor los aprueba."""
    import json, urllib.error, urllib.request
    def post(ruta, cuerpo, tok=None):
        req = urllib.request.Request(base + ruta, data=json.dumps(cuerpo).encode(), method="POST"); req.add_header("Content-Type", "application/json")
        if tok: req.add_header("Authorization", "Bearer " + tok)
        return json.loads(urllib.request.urlopen(req, timeout=10).read())
    tok = post("/api/profesor/entrar", {"pin": pin})["token"]
    try: post("/api/profesor/alumnos", {"nombre": usuario, "clave": clave}, tok)
    except urllib.error.HTTPError as e:
        if e.code != 409: raise                                    # 409: ya estaba

def ok(nombre, cond, detalle=""):
    global fallos
    if not cond: fallos += 1
    print("  %s %s %s" % ("OK " if cond else "MAL", nombre, detalle))


def pedir(metodo, ruta, cuerpo=None, pase=None):
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    req = urllib.request.Request(BASE + ruta, data=datos, method=metodo)
    if datos is not None: req.add_header("Content-Type", "application/json")
    if pase: req.add_header("X-Alumno", pase)
    try:
        with urllib.request.urlopen(req, timeout=10) as r: return r.status, json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e: return e.code, e.read().decode("utf-8", "replace")
    except (urllib.error.URLError, OSError) as e: return 0, str(e)


def nombres():
    """id -> nombre de cada vehiculo (como aviones/*.js)"""
    import glob, re
    N = {}
    for f in glob.glob(str(REPO / "datos" / "vehiculos" / "*.js")):
        t = open(f, encoding="utf-8").read(); i = re.search(r'"id"\s*:\s*"([^"]+)"', t); nm = re.search(r'"nombre"\s*:\s*("(?:[^"\\]|\\.)*")', t)
        if i and nm: N[i.group(1)] = json.loads(nm.group(1))
    return N


def main():
    global fallos
    import servidor_aula as sa
    datos = tempfile.mkdtemp(prefix="aula_logros_")
    sa.usar_datos(datos); sa.crear_bd()
    con = sa.conectar()                                       # sin PIN del profesor el servidor no arranca
    with con: con.execute("INSERT OR REPLACE INTO config (clave, valor) VALUES ('pin', ?)", (sa.hash_pin("2468"),))
    con.close()
    pr = subprocess.Popen([sys.executable, str(REPO / "aula" / "servidor_aula.py"), "--puerto", str(PUERTO), "--datos", datos],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            if pedir("GET", "/api/estado")[0] == 200: break
            time.sleep(0.1)
        else: raise SystemExit("el servidor de prueba no arranca")
        pruebas(sa)
    finally:
        pr.kill(); pr.wait(); shutil.rmtree(datos, ignore_errors=True)
    print("RESULTADO:", "todo bien" if not fallos else "%d fallos" % fallos)
    sys.exit(1 if fallos else 0)


def pruebas(sa):
    K = sa.catalogo_logros()
    ok("catalogo: el E3, el T1, el Poli-1 y el XM-7 son de ala fija; los dos drones y el FPV, de dron; el bipode, de nada",
       all(K["clase"].get(a) == "ala" for a in ("E3", "T1", "G1", "XM7")) and all(K["clase"].get(a) == "dron" for a in ("DJI_MINI", "HQ3T", "FPV"))
       and K["clase"].get("BIPODE") is None, str(K["clase"]))
    ok("catalogo: tambien por el nombre y por las palabras de los nombres de antes", sa.clase_vehiculo(K, "Dron FPV de 5 pulgadas") == "dron" and sa.clase_vehiculo(K, "Cuadricóptero DJI Mini 4K") == "dron"
       and sa.clase_vehiculo(K, "Entrenador E2") == "ala" and sa.clase_vehiculo(K, "Cernícalo XM-7") == "ala")
    ok("catalogo: entrenamientos de ala fija y de dron, y 12 operaciones", len(K["ala"]) >= 4 and "primer_vuelo" in K["dron"] and len(K["operaciones"]) == 12,
       "%d / %d / %d" % (len(K["ala"]), len(K["dron"]), len(K["operaciones"])))
    alta_profesor(BASE, "2468", "Piloto de logros", "abcd")
    c, a = pedir("POST", "/api/entrar", {"usuario": "Piloto de logros", "clave": "abcd"})
    pase, aid = a["pase"], a["alumno"]["id"]
    g = a["alumno"]["progreso"]
    ok("un piloto nuevo: tres logros sin conseguir y el robot bloqueado", [x["id"] for x in g["logros"]] == ["ala_fija", "dron", "operaciones"]
       and not any(x["ok"] for x in g["logros"]) and g["robot"] is False, str([(x["id"], x["ok"]) for x in g["logros"]]))
    n = [0]

    NOMBRE = nombres()

    def vuelo(avion, escenario, minutos, res="APTO", marca=None):
        """como lo mandan los simuladores: con el NOMBRE del vehiculo (no su id)"""
        n[0] += 1
        c, r = pedir("POST", "/api/vuelos", {"id": str(uuid.uuid4()), "alumno_id": aid, "inicio": "2026-10-15T%02d:%02d:00" % (8 + n[0] // 60, n[0] % 60),
                                            "avion": NOMBRE.get(avion, avion), "escenario": escenario, "resultado": res, "tiempo_vuelo_s": minutos * 60, "marca": marca}, pase=pase)
        assert c in (200, 201), (c, r)
        return {x["id"]: x for x in r["progreso"]["logros"]}, r["progreso"]["robot"]

    # ---- ala fija: los entrenamientos del avion con el E3 y 2 h repartidas entre el E3 y el XM-7 ----
    for e in K["ala"]: L, rb = vuelo("E3", e, 5)
    ok("todos los entrenamientos del avion, pero sin 2 h: ala fija aun no", not L["ala_fija"]["ok"] and L["ala_fija"]["hechas"] == len(K["ala"]), "%.2f h" % L["ala_fija"]["horas"])
    ok("y primer_vuelo superado con el avion no cuenta para el dron", L["dron"]["hechas"] == 0, str(L["dron"]["hechas"]))
    L, rb = vuelo("XM7", "libre", 120 - 5 * len(K["ala"]) - 1)
    ok("con 1 min menos de 2 h, todavia no", not L["ala_fija"]["ok"], "%.3f h" % L["ala_fija"]["horas"])
    L, rb = vuelo("XM7", "libre", 1)
    ok("con 2 h (el UAV cuenta como ala fija): Piloto de ala fija", L["ala_fija"]["ok"] and not rb, "%.3f h" % L["ala_fija"]["horas"])
    # ---- dron: horas con el bipode no cuentan; NO APTO no cuenta ----
    L, rb = vuelo("BIPODE", "libre", 200)
    ok("las horas con el bipode no cuentan para ningun logro", L["dron"]["horas"] == 0 and L["ala_fija"]["horas"] < 2.01, "%.2f h" % L["dron"]["horas"])
    L, rb = vuelo("DJI_MINI", K["dron"][0], 10, "NO APTO")
    ok("un NO APTO no supera el entrenamiento", L["dron"]["hechas"] == 0 and K["dron"][0] in L["dron"]["pendientes"])
    for e in K["dron"]: L, rb = vuelo("DJI_MINI", e, 10)
    L, rb = vuelo("FPV", "libre", 120 - 10 * (len(K["dron"]) + 1))
    ok("2 h entre el Mini Dron y el FPV y sus entrenamientos: Piloto de dron", L["dron"]["ok"] and not rb, "%.3f h, %d/%d" % (L["dron"]["horas"], L["dron"]["hechas"], L["dron"]["total"]))
    # ---- operaciones ----
    ops = [e for e in K["operaciones"] if e != "op_carrera"] + ["op_carrera"]
    for e in ops[:-1]: L, rb = vuelo("DJI_MINI", e, 10)
    ok("con una operacion pendiente (la carrera), ni el logro ni el robot", not L["operaciones"]["ok"] and not rb and L["operaciones"]["pendientes"] == ["op_carrera"])
    L, rb = vuelo("FPV", "op_carrera", 2, marca=95.3)
    ok("todas las operaciones: Operador profesional y el robot desbloqueado", L["operaciones"]["ok"] and rb is True)
    c, a = pedir("GET", "/api/alumnos/" + aid)
    ok("la ficha del piloto lo dice tambien", c == 200 and a["progreso"]["robot"] is True and all(x["ok"] for x in a["progreso"]["logros"]))
    alta_profesor(BASE, "2468", "Otro piloto", "abcd")
    c, b = pedir("POST", "/api/entrar", {"usuario": "Otro piloto", "clave": "abcd"})
    ok("y otro piloto sigue con el robot bloqueado", b["alumno"]["progreso"]["robot"] is False)
    # ---- la carrera de drones: el mejor tiempo historico en el perfil ----
    ok("el perfil guarda el tiempo de la carrera", a["progreso"]["carrera"] and a["progreso"]["carrera"]["mejor"] == 95.3, str(a["progreso"].get("carrera")))
    vuelo("DJI_MINI", "op_carrera", 3, marca=88.14, res="NO APTO"); vuelo("FPV", "op_carrera", 2, marca=101.0)
    c, a = pedir("GET", "/api/alumnos/" + aid); C = a["progreso"]["carrera"]
    ok("y se queda el mejor de todos (aunque el vuelo no fuera APTO por otra cosa)", C["mejor"] == 88.14 and C["avion"] == NOMBRE["DJI_MINI"], str(C))
    ok("otro piloto sin carrera: sin tiempo", b["alumno"]["progreso"]["carrera"] is None)
    c, r = pedir("POST", "/api/vuelos", {"id": str(uuid.uuid4()), "alumno_id": aid, "inicio": "2026-10-15T12:00:00", "avion": "FPV", "escenario": "op_carrera",
                                        "resultado": "APTO", "tiempo_vuelo_s": 60, "marca": 0.2}, pase=pase)
    ok("un tiempo imposible (0,2 s) se rechaza", c == 400, str(c))
    # ---- la carrera en una sala: el mejor de la sala, aunque el que lo hizo se vaya ----
    c, d = pedir("POST", "/api/profesor/entrar", {"pin": "2468"}); tok = d.get("token")
    req = urllib.request.Request(BASE + "/api/salas", data=json.dumps({"escenario": "op_carrera", "nombre": "Carrera"}).encode(), method="POST")
    req.add_header("Content-Type", "application/json"); req.add_header("Authorization", "Bearer " + tok)
    cod = json.loads(urllib.request.urlopen(req, timeout=10).read())["codigo"]
    est = lambda jid, nombre, avion, t: pedir("POST", "/api/salas/%s/estado" % cod, {"id": jid, "nombre": nombre, "avion": avion, "p": [0, 0, 0], "q": [1, 0, 0, 0], "carrera": t})
    est("a", "Ana", "FPV", None); c, r = est("b", "Bea", "DJI_MINI", None)
    ok("sala nueva: sin mejor tiempo", r["sala"].get("record") is None, str(r["sala"].get("record")))
    est("a", "Ana", "FPV", 70.5); est("b", "Bea", "DJI_MINI", 65.25); c, r = est("a", "Ana", "FPV", 80)
    ok("el mejor de la sala es el mas rapido de todos", r["sala"]["record"] == {"nombre": "Bea", "avion": "DJI_MINI", "t": 65.25}, str(r["sala"]["record"]))
    pedir("POST", "/api/salas/%s/salir" % cod, {"id": "b"}); c, r = est("a", "Ana", "FPV", 70.5)
    ok("y sigue aunque Bea se vaya de la sala", r["sala"]["record"]["nombre"] == "Bea")
    c, r = est("a", "Ana", "FPV", "rapidisimo"); c2, r2 = est("a", "Ana", "FPV", -5)
    ok("tiempos raros (texto, negativos) no cuentan", r["sala"]["record"]["t"] == 65.25 and r2["sala"]["record"]["t"] == 65.25)


if __name__ == "__main__":
    main()
