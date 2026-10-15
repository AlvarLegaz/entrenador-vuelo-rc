"""El trabajo de operador "Patrulla del Mar Menor: vertidos" (escenarios.js, op_patrulla) con el UAV Cernicalo XM-7: despega
de la pista 05R de San Javier, busca con la torreta EO/IR tres vertidos (manchas de hidrocarburo en el agua) en los
sectores que da el aviso de un pesquero, los fotografia enviando su posicion y vuelve a aterrizar en la pista.

Los sitios posibles de los vertidos salen del propio mapa (simulador/mundos/cartagena.js): celdas de la laguna del Mar
Menor (laguna_b64) a mas de 700 m de cualquier tierra (agua_b64), dentro de lo que cubre el terreno, cada ~1,2 km.
Operacion.sortear elige tres separados (operaciones.js) y les pone forma, tamano y sector al azar.

La pista es la 05R/23L real (OpenStreetMap, aeroway=runway): umbral 05R en 37.7676 N / 0.8195 W.

    python analisis/mundo_cartagena/op_patrulla.py
"""
import base64, json, math, os, re
import numpy as np

AQUI = os.path.dirname(os.path.abspath(__file__))
SIM = os.path.join(AQUI, "..", "..", "simulador")
PISTA = {"nombre": "San Javier 05R/23L", "n": 17121.5, "e": 20133.2, "rumbo": 45.86, "largo": 2311, "ancho": 45}
LEJOS_ORILLA, PASO_CAND = 700.0, 1200.0


def main():
    t = open(os.path.join(SIM, "mundos", "cartagena.js"), encoding="utf-8").read()
    M = json.loads(t[t.index("Mundos.registrar(") + 17:t.rindex(")")])
    T = M["terreno"]; nN, nE, paso, N0, E0 = T["nN"], T["nE"], T["paso"], T["N0"], T["E0"]
    bits = lambda k: np.unpackbits(np.frombuffer(base64.b64decode(T[k]), np.uint8))[:nN * nE].reshape(nN, nE).astype(bool)
    agua, laguna = bits("agua_b64"), bits("laguna_b64")
    # distancia (celdas) a la tierra mas cercana: barrido en anillos (pocas celdas)
    r = int(math.ceil(LEJOS_ORILLA / paso)) + 1; tierra = ~agua; lejos = laguna.copy()
    for di in range(-r, r + 1):
        for dj in range(-r, r + 1):
            if di * di + dj * dj > (LEJOS_ORILLA / paso) ** 2: continue
            sh = np.zeros_like(tierra)
            sh[max(0, di):nN + min(0, di), max(0, dj):nE + min(0, dj)] = tierra[max(0, -di):nN - max(0, di), max(0, -dj):nE - max(0, dj)]
            lejos &= ~sh
    lejos[nN - r:, :] = False                                         # nada pegado al borde del terreno (la punta norte esta cortada)
    cand = []
    for i, j in zip(*np.nonzero(lejos)):
        n, e = N0 + i * paso, E0 + j * paso
        if all(math.hypot(n - a, e - b) >= PASO_CAND for a, b in cand): cand.append((round(float(n), 1), round(float(e), 1)))
    print("%d celdas de la laguna a mas de %.0f m de tierra; %d candidatos" % (int(lejos.sum()), LEJOS_ORILLA, len(cand)))
    r_ = PISTA["rumbo"] * math.pi / 180
    salida = {"n": round(PISTA["n"] + 60 * math.cos(r_), 1), "e": round(PISTA["e"] + 60 * math.sin(r_), 1), "rumbo": PISTA["rumbo"]}
    O = {
        "nombre": "Patrulla del Mar Menor: vertidos",
        "vehiculos": ["uav"],
        "mundo": "cartagena",
        "zona": 3,
        "dificultad": 3,
        "viento": {"vel": 5, "desde": 60, "rachas": True},
        "desc": "Un pesquero ha avisado de tres manchas de hidrocarburo en el Mar Menor. Con el UAV de vigilancia Cernícalo XM-7, despega de la pista 05R de la base aérea de San Javier, patrulla los tres sectores del aviso, encuentra cada vertido con la torreta EO/IR (zoom y cámara térmica), fotografíalo con la cruz sobre la mancha para enviar su posición a Salvamento Marítimo y vuelve a aterrizar en la pista.",
        "objetivos": [
            ["vertidos", "Localizar los 3 vertidos y fotografiarlos con la cruz de la torreta sobre la mancha (su posición se envía con la foto)"],
            ["despegue", "Despegar de la pista 05R de San Javier"],
            ["a_mano", "Despegar y aterrizar a mano (sin el despegue ni el aterrizaje automáticos)"],
            ["altura", "Patrullar a 150 m o más sobre el agua (salvo a menos de 5 km de la pista)"],
            ["techo", "Sin pasar de 900 m sobre el suelo"],
            ["tiempo", "Los tres vertidos en 40 minutos desde el despegue"],
            ["pista", "Aterrizar en la pista de San Javier y pararse en ella"],
            ["aterrizar", "Aterrizar sin daños"]],
        "operacion": {
            "avion": "XM7",
            "cliente": "Capitanía Marítima de Cartagena · Salvamento Marítimo",
            "lugar": "Base aérea de San Javier (Murcia), pista 05R/23L de 2.311 m. Patrulla sobre el Mar Menor.",
            "trabajo": "Despegue de la 05R, vuelo a los sectores del aviso (círculos naranjas en el mapa) y búsqueda de las manchas con la torreta: en la cámara normal son manchas oscuras con brillos de colores; en la térmica, el hidrocarburo calentado por el sol sale más caliente que el agua. Con el piloto automático en «ir a punto» (clic en el mapa) el avión da vueltas sobre el sector y las flechas mueven la torreta; K la fija sobre un punto. Foto (F) con la cruz sobre la mancha, a una distancia razonable para su zoom.",
            "entrega": "Una foto de cada vertido con su posición, para enviar las embarcaciones de limpieza.",
            "salida": salida,
            "pista": PISTA,
            "candidatos_vertido": cand, "vertidos": 3, "separacion": 3000, "radio_sector": 1000,
            "dist_foto": 450, "h_min": 150, "techo": 900, "radio_pista": 5000, "limite_s": 2400,
        },
    }
    p = os.path.join(SIM, "escenarios.js"); t = open(p, encoding="utf-8").read()
    bloque = ' "op_patrulla": ' + json.dumps(O, indent=1, ensure_ascii=False).replace("\n", "\n ") + ",\n"
    if '\n "op_patrulla": {' in t:
        i = t.index('\n "op_patrulla": {') + 1; j = t.index('\n "', i + 5) + 1; t = t[:i] + bloque + t[j:]
    else:
        i = t.index('\n "libre_cartagena": {') + 1; t = t[:i] + bloque + t[i:]
    m = re.search(r"(?m)^window[.]ESCENARIOS = ", t); json.loads(t[m.end():t.rindex("}") + 1])
    open(p, "w", encoding="utf-8", newline="\n").write(t)
    print("escrito op_patrulla en escenarios.js")


if __name__ == "__main__":
    main()
