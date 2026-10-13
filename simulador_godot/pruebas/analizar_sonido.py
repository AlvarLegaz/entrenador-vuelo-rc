"""Analiza el WAV de pruebas/prueba_sonido.gd y lo compara con el grafo Web Audio del simulador del navegador.

La referencia se calcula aqui con las formulas de Web Audio (osciladores limitados en banda, BiquadFilter lowpass con Q en dB y
bandpass con Q lineal, setTargetAtTime / exponentialRampToValueAtTime), con los parametros del objeto Sonido de
simulador/simulador.html. Uso:  python simulador_godot/pruebas/analizar_sonido.py CARPETA   (sale con codigo 1 si algo falla)
"""
import json
import sys

import numpy as np
from scipy import signal
from scipy.io import wavfile

carpeta = sys.argv[1] if len(sys.argv) > 1 else "."
fs, x = wavfile.read(carpeta + "/sonido_prueba.wav")
x = x[:, 0].astype(np.float64)
meta = json.load(open(carpeta + "/sonido_prueba.json", encoding="utf-8"))
VOL = meta["vol"]
tramos = {t["nombre"]: t for t in meta["tramos"]}
t_ev = {e["tramo"]: e["t"] for e in meta["eventos"]}
fallos = []


def comprobar(nombre, ok, texto):
    print(("OK    " if ok else "FALLO ") + nombre + ": " + texto)
    if not ok:
        fallos.append(nombre)


def db(a):
    return 20 * np.log10(np.maximum(a, 1e-12))


def rms(s):
    return float(np.sqrt(np.mean(s ** 2)))


# ------------------------------------------------------------------ referencia Web Audio
def biquad_web(tipo, fc, q):
    w0 = 2 * np.pi * fc / fs
    c, s = np.cos(w0), np.sin(w0)
    if tipo == "lowpass":
        al = s / (2 * 10 ** (q / 20))
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
    else:
        al = s / (2 * q)
        b = [al, 0, -al]
    a = [1 + al, -2 * c, 1 - al]
    return np.array(b) / a[0], np.array(a) / a[0]


def motor_web(f, gas, n):
    t = np.arange(n) / fs
    y = np.zeros(n)
    for k in range(1, int(fs / 2 / f) + 1):          # sierra limitada en banda
        y += 0.7 * 2 / (np.pi * k) * (-1) ** (k + 1) * np.sin(2 * np.pi * k * f * t)
    for j in range(1, int(fs / 2 / (2 * f)) + 1, 2):   # cuadrada al doble
        y += 0.22 * 4 / (np.pi * j) * np.sin(2 * np.pi * j * 2 * f * t)
    b, a = biquad_web("lowpass", 500 + 2600 * gas, 0.9)
    return signal.lfilter(b, a, y)


rng = np.random.default_rng(1)
RUIDO = rng.uniform(-1, 1, 2 * fs)


def viento_web(V, n):
    b, a = biquad_web("bandpass", 250 + 30 * V, 0.5)
    return signal.lfilter(b, a, np.resize(RUIDO, n))


def ref_tramo(tr, n):
    """Senal estacionaria que daria la web en el tramo (sin el pitido)."""
    av = tr["av"]
    lejos = tr["lejos"] if tr["camara_piloto"] else 1.0
    y = np.zeros(n)
    rpm, gas = av["rpm"], av["gases"]
    if rpm > 0:
        y += motor_web(max(25, rpm / 60), gas, n) * (0.06 + 0.3 * gas ** 1.3) * lejos
    V = av["V"] if av["estado"] == "volando" else 0
    gv = min(0.45, 0.0011 * V * V) * (0.35 * lejos if tr["camara_piloto"] else 1)
    if gv > 0:
        y += viento_web(V, n) * gv
    return y * VOL


def trozo(nombre, margen=0.4):
    tr = tramos[nombre]
    return x[int((tr["ini"] + margen) * fs): int(tr["fin"] * fs)]


def centroide(s):
    f, p = signal.welch(s, fs, nperseg=min(8192, len(s)))
    return float(np.sum(f * p) / np.sum(p))


# ------------------------------------------------------------------ silencio de arranque
comprobar("arranque", rms(x[int(0.1 * fs): int(0.45 * fs)]) < 1e-4, "rms %.1e antes de mover nada" % rms(x[int(0.1 * fs): int(0.45 * fs)]))

# ------------------------------------------------------------------ motor
print("\n-- motor: frecuencia dominante = rpm/60, nivel y timbre frente a la web")
niveles = {}
for nom in ["ralenti", "gas_fondo", "medio_gas", "piloto_lejos", "sin_silenciar"]:
    s = trozo(nom)
    tr = tramos[nom]
    S = np.abs(np.fft.rfft(s * np.hanning(len(s))))
    f = np.fft.rfftfreq(len(s), 1 / fs)
    fp = f[np.argmax(S)]
    fe = max(25, tr["av"]["rpm"] / 60)
    comprobar("motor %s frecuencia" % nom, abs(fp - fe) < 1.0, "pico %.2f Hz, rpm/60 = %.2f Hz" % (fp, fe))
    r = ref_tramo(tr, len(s))
    d = db(rms(s)) - db(rms(r))
    niveles[nom] = rms(s)
    comprobar("motor %s nivel" % nom, abs(d) < 1.0, "rms %.4f, web %.4f (%+.2f dB)" % (rms(s), rms(r), d))
    cs, cr = centroide(s), centroide(r)
    comprobar("motor %s timbre" % nom, abs(cs / cr - 1) < 0.1, "centroide %.0f Hz, web %.0f Hz" % (cs, cr))
rl = niveles["piloto_lejos"] / niveles["gas_fondo"]
comprobar("camara del piloto", abs(rl / tramos["piloto_lejos"]["lejos"] - 1) < 0.12,
          "a 135 m el motor queda a %.3f del de cerca; lejos = 1/(1+135/45) = %.3f" % (rl, tramos["piloto_lejos"]["lejos"]))

# ------------------------------------------------------------------ viento
print("\n-- viento: la banda sube con V")
picos = []
for nom in ["planeo_8", "planeo_15", "planeo_25"]:
    s = trozo(nom)
    tr = tramos[nom]
    V = tr["av"]["V"]
    f, p = signal.welch(s, fs, nperseg=4096)
    r = ref_tramo(tr, len(s))
    fr, pr = signal.welch(r, fs, nperseg=4096)
    ps = np.convolve(p, np.ones(9) / 9, "same")
    fp = f[np.argmax(ps)]
    picos.append(fp)
    fc = 250 + 30 * V
    comprobar("viento V=%g banda" % V, abs(fp / fc - 1) < 0.2, "maximo del espectro %.0f Hz, centro 250+30V = %.0f Hz" % (fp, fc))
    d = db(rms(s)) - db(rms(r))
    comprobar("viento V=%g nivel" % V, abs(d) < 1.0, "rms %.4f, web %.4f (%+.2f dB)" % (rms(s), rms(r), d))
    # forma del espectro: diferencia media en dB entre 100 Hz y 5 kHz
    m = (f > 100) & (f < 5000)
    dd = db(np.sqrt(p[m])) - db(np.sqrt(pr[m]))
    comprobar("viento V=%g forma" % V, np.abs(dd - dd.mean()).mean() < 1.0, "desviacion media del espectro frente a la web %.2f dB" % np.abs(dd - dd.mean()).mean())
comprobar("viento sube con V", picos[0] < picos[1] < picos[2], "maximos %s Hz" % ", ".join("%.0f" % p for p in picos))

# ------------------------------------------------------------------ pitido de perdida
print("\n-- pitido de perdida")
s = trozo("perdida", 0.3)
f, p = signal.welch(s, fs, nperseg=16384)
comprobar("pitido frecuencia", abs(f[np.argmax(p)] - 880) < 3, "pico %.1f Hz" % f[np.argmax(p)])
b, a = signal.butter(4, [830, 930], "bandpass", fs=fs)
e = np.sqrt(signal.lfilter(*signal.butter(2, 60, fs=fs), signal.filtfilt(b, a, s) ** 2).clip(0))
ed = e[:: fs // 1000]                                 # envolvente a 1 kHz
E = np.abs(np.fft.rfft(ed - ed.mean(), 8 * len(ed)))
fE = np.fft.rfftfreq(8 * len(ed), 1e-3)
fm = fE[np.argmax(E * (fE > 0.5))]
comprobar("pitido intermitencia", abs(fm - 2.0) < 0.05, "la envolvente se repite a %.3f Hz" % fm)
alto = ed > 0.5 * np.percentile(ed, 95)
comprobar("pitido ciclo", abs(alto.mean() - 0.5) < 0.08, "encendido el %.0f %% del tiempo" % (100 * alto.mean()))
nivel_on = np.percentile(ed, 90)
esperado = 0.1 * VOL / np.sqrt(2)
comprobar("pitido nivel", abs(db(nivel_on) - db(esperado)) < 1.0, "rms encendido %.4f, web 0,1*vol/sqrt2 = %.4f" % (nivel_on, esperado))
# a menos de 2 m de altura no pita: en la banda de 870-890 Hz solo queda lo que deja pasar el filtro del viento (V = 9)
s2 = trozo("perdida_suelo", 0.3)
b, a = signal.butter(4, [870, 890], "bandpass", fs=fs)
b8 = rms(signal.filtfilt(b, a, s2))
b8r = rms(signal.filtfilt(b, a, ref_tramo(tramos["perdida_suelo"], len(s2))))
comprobar("sin pitido a menos de 2 m", b8 < 2 * b8r and b8 < 0.2 * nivel_on, "rms en 870-890 Hz %.1e (viento de la web %.1e; con pitido %.4f)" % (b8, b8r, nivel_on))

# ------------------------------------------------------------------ eventos
print("\n-- eventos (envolvente y filtro)")


def rafaga_web(fc, g0, T, n):
    b, a = biquad_web("lowpass", fc, 1.0)
    y = signal.lfilter(b, a, RUIDO[:n])
    t = np.arange(n) / fs
    g = np.where(t < T, g0 * (0.001 / g0) ** (t / T), 0.001)
    return y * g * VOL


def envolvente(s, ventana=0.005):
    w = int(ventana * fs)
    return np.sqrt(np.convolve(s ** 2, np.ones(w) / w, "same"))


cents = {}
for nom, fc, g0, T in [("toque", 900, 0.3, 0.18), ("roto", 350, 0.9, 0.7)]:
    a0 = int((t_ev[nom] - 0.05) * fs)
    s = x[a0: a0 + int(1.2 * fs)]
    env = envolvente(s)
    on = int(np.argmax(env > 0.2 * env.max()))              # arranque de la rafaga
    r = rafaga_web(fc, g0, T, int(0.8 * fs))
    er = envolvente(r)
    seg = s[on: on + int(0.8 * fs)]
    es = envolvente(seg)
    # pendiente de caida en dB/s entre 10 ms y 0,8 T
    i0, i1 = int(0.01 * fs), int(0.8 * T * fs)
    tt = np.arange(i0, i1) / fs
    ps = np.polyfit(tt, db(es[i0:i1]), 1)[0]
    pr = np.polyfit(tt, db(er[i0:i1]), 1)[0]
    pe = 20 * np.log10(0.001 / g0) / T
    comprobar("%s caida" % nom, abs(ps / pe - 1) < 0.15, "%.0f dB/s, web %.0f dB/s (%.0f dB en %.2f s)" % (ps, pr, pe * T, T))
    n0 = int(0.03 * fs)
    d = db(rms(seg[:n0])) - db(rms(r[:n0]))
    comprobar("%s nivel inicial" % nom, abs(d) < 1.5, "rms 30 ms %.4f, web %.4f (%+.2f dB)" % (rms(seg[:n0]), rms(r[:n0]), d))
    cs, cr = centroide(seg[: int(T * fs)]), centroide(r[: int(T * fs)])
    cents[nom] = cs
    comprobar("%s filtro" % nom, abs(cs / cr - 1) < 0.15, "centroide %.0f Hz, web %.0f Hz (paso bajo %d Hz)" % (cs, cr, fc))
    fin = rms(s[on + int(0.85 * fs): on + int(1.1 * fs)])
    comprobar("%s termina" % nom, fin < 1e-4, "rms despues de 0,85 s %.1e" % fin)
comprobar("roto mas grave que toque", cents["roto"] < cents["toque"], "%.0f Hz < %.0f Hz" % (cents["roto"], cents["toque"]))

# ------------------------------------------------------------------ silenciar y apagar
print("\n-- volumen general")
for nom in ["silenciado", "apagado"]:
    v = rms(trozo(nom, 0.5))
    comprobar(nom, v < 1e-4, "rms %.1e con el motor a fondo" % v)
# suavizado de los objetivos en _process (setTargetAtTime): el volumen general tarda 50 ms en caer a 1/e y la frecuencia del
# motor 80 ms en recorrer el 63 % del salto. Se mira en la traza por cuadro (con el reloj) porque el driver Dummy de --headless mezcla a
# rafagas (~93 ms, en el WAV se ven escalones); con tarjeta de sonido la mezcla va en trozos pequenos y sigue la curva.
tz = np.array(meta["traza"])
k_ev = {e["tramo"]: e["cuadro"] for e in meta["eventos"]}
k0 = k_ev["silenciado"]
g0 = tz[k0 - 1, 1]
t63 = np.interp(-np.exp(-1) * g0, -tz[k0 - 1:, 1], tz[k0 - 1:, 0]) - tz[k0 - 1, 0]
comprobar("silenciar suave", abs(t63 - 0.05) < 0.02, "el volumen general cae a 1/e en %.0f ms (web: setTargetAtTime de 50 ms)" % (1000 * t63))
k1 = k_ev["gas_fondo"]
f63 = np.interp(50 + 200 * (1 - np.exp(-1)), tz[k1 - 1:k1 + 60, 3], tz[k1 - 1:k1 + 60, 0]) - tz[k1 - 1, 0]
comprobar("motor sube de vueltas", abs(f63 - 0.08) < 0.025, "de 50 a 250 Hz: el 63 %% en %.0f ms (web: 80 ms)" % (1000 * f63))
s = x[int(t_ev["silenciado"] * fs): int((t_ev["silenciado"] + 0.6) * fs)]
env = envolvente(s, 0.008)
n90 = int(np.argmax(env < 0.9 * env[: int(0.01 * fs)].mean()))
n10 = int(np.argmax(env < 0.1 * env[: int(0.01 * fs)].mean()))
comprobar("silenciar sin chasquido", (n10 - n90) / fs > 0.005, "en el WAV la caida del 90 %% al 10 %% dura %.1f ms (no es un corte seco)" % (1000 * (n10 - n90) / fs))

print("\nCoste en el hilo principal: %.1f us por cuadro de media (actualizar + _process), maximo %d us, %d cuadros a %.1f fps"
      % (meta["us_por_cuadro"], meta["us_max"], meta["cuadros"], meta["fps"]))
print("\n%d comprobaciones fallidas" % len(fallos) if fallos else "\nTODO OK")
sys.exit(1 if fallos else 0)
