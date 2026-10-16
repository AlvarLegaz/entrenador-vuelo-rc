"""Exporta UxS Trainer v2 (Godot) a las gafas de realidad virtual autonomas (Pico 4, Pico Neo 3 y otras con OpenXR)
como un APK de Android, y con --instalar lo instala en las gafas conectadas por USB (modo desarrollador) y lo abre.

    python simulador_godot/exportar_pico.py [--instalar] [--zonas]

Pasos: empaqueta los datos comunes de ../simulador (aviones, mundos, escenarios, singulares, operaciones y el indice de
zonas; con --zonas tambien las zonas de detalle, unos 330 MB mas) en datos_android.zip, que va dentro del APK y la app
descomprime la primera vez (DatosComunes._datos_android); y exporta con una copia de Godot autocontenida
(herramientas/godot_android: sus ajustes y plantillas no tocan los del usuario) con el JDK 17 y el SDK de Android de
herramientas/android, compilando con Gradle (la plantilla de Android de Godot se instala en android/ la primera vez; asi
lleva el cargador de OpenXR). El APK queda en herramientas/uxs_trainer_pico.apk (firmado con la clave de depuracion).
"""
import datetime, os, pathlib, re, subprocess, sys, zipfile

REPO = pathlib.Path(__file__).resolve().parent.parent
PROY = REPO / "simulador_godot"
SIM = REPO / "simulador"
H = REPO / "herramientas"
GODOT = H / "godot_android" / "Godot_v4.7.2-stable_win64_console.exe"
JDK, SDK = H / "android" / "jdk", H / "android" / "sdk"
APK = H / "uxs_trainer_pico.apk"
ADB = SDK / "platform-tools" / "adb.exe"


def datos(con_zonas):
    """datos_android.zip con lo que Godot lee de ../simulador (DatosComunes.carpeta())."""
    z = PROY / "datos_android.zip"
    ver = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    n = 0
    with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as f:
        f.writestr("version.txt", ver)
        for rel in ["aviones", "mundos", "operaciones", "escenarios.js", "singulares.js", "zonas/indice.json"] + (["zonas"] if con_zonas else []):
            p = SIM / rel
            for q in ([p] if p.is_file() else sorted(p.rglob("*"))):
                if q.is_file():
                    arc = q.relative_to(SIM).as_posix()
                    if arc not in f.namelist(): f.write(q, arc); n += 1
    print("datos_android.zip: %d ficheros, %.1f MB (version %s)" % (n, z.stat().st_size / 1e6, ver))


def ajustes_editor():
    """El SDK de Android y el JDK en los ajustes del Godot autocontenido (los crea la primera vez)."""
    ed = GODOT.parent / "editor_data"
    if not list(ed.glob("editor_settings-*.tres")):
        subprocess.run([str(GODOT), "--headless", "--editor", "--quit", "--path", str(PROY)], capture_output=True, timeout=900)
    f = sorted(ed.glob("editor_settings-*.tres"))[-1]
    t = f.read_text(encoding="utf-8")
    for k, v in [("export/android/android_sdk_path", SDK), ("export/android/java_sdk_path", JDK)]:
        linea = '%s = "%s"' % (k, v.as_posix())
        t = re.sub(r"^%s = .*$" % re.escape(k), linea, t, flags=re.M) if re.search(r"^%s = " % re.escape(k), t, re.M) else t.replace("[resource]\n", "[resource]\n" + linea + "\n", 1)
    f.write_text(t, encoding="utf-8")
    print("ajustes del editor:", f.name)


def exportar():
    if APK.exists(): APK.unlink()
    plantilla = [] if (PROY / "android" / "build").exists() else ["--install-android-build-template"]     # la de Gradle, la primera vez
    # la salida a un fichero y no a tuberias: si queda vivo el proceso de fondo de Gradle, las tuberias no se cierran y
    # esto se quedaria esperando aunque el APK ya este hecho (por eso tambien sin el daemon de Gradle)
    os.environ["GRADLE_OPTS"] = (os.environ.get("GRADLE_OPTS", "") + " -Dorg.gradle.daemon=false").strip()
    log = H / "exportar_pico.log"
    with open(log, "w", encoding="utf-8") as f:
        subprocess.run([str(GODOT), "--headless", "--path", str(PROY), *plantilla, "--export-debug", "Pico (Android)", str(APK)], stdout=f, stderr=subprocess.STDOUT, timeout=3600)
    for l in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if re.search(r"error|warning|aviso|export", l, re.I): print("  " + l)
    if not APK.exists(): sys.exit("No se ha generado el APK")
    print("APK: %s (%.1f MB)" % (APK, APK.stat().st_size / 1e6))


def instalar():
    def adb(*a): return subprocess.run([str(ADB), *a], capture_output=True, text=True)
    disp = [l.split()[0] for l in adb("devices").stdout.splitlines()[1:] if l.strip().endswith("device")]
    if not disp: sys.exit("No hay gafas conectadas por USB con la depuracion activada (adb devices)")
    print("gafas:", disp[0], adb("shell", "getprop", "ro.product.model").stdout.strip())
    r = adb("install", "-r", str(APK)); print(r.stdout.strip() or r.stderr.strip())
    adb("shell", "monkey", "-p", "es.uxstrainer.simulador", "-c", "android.intent.category.LAUNCHER", "1")
    print("Abierto en las gafas: ponlas y a volar")


if __name__ == "__main__":
    os.environ["JAVA_HOME"] = str(JDK); os.environ["ANDROID_HOME"] = str(SDK)
    datos("--zonas" in sys.argv)
    ajustes_editor()
    exportar()
    if "--instalar" in sys.argv: instalar()
