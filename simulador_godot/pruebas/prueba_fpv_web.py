"""Prueba del dron FPV en el simulador del navegador: carga sin errores, se elige el FPV, sale el OSD y la ayuda del
FPV, no arma con el gas arriba, arma con el gas abajo, W sube el gas y despega, M cambia de modo, 1/2/3 cambian la
camara, L desarma; y el E3 y el dron comercial siguen arrancando. Con una ruta, guarda ademas capturas del vuelo con la camara
FPV (3) y la de persecucion (2).

Uso (desde la carpeta del repositorio; necesita Python con playwright y Google Chrome instalado):
    python simulador_godot/pruebas/prueba_fpv_web.py [carpeta de las capturas]
"""
import pathlib, sys, time
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
PAGINA = (REPO / "simulador" / "simulador.html").as_uri()
fallos = 0


def ok(nombre, cond, detalle=""):
    global fallos
    if not cond:
        fallos += 1
    print(f"  {'OK ' if cond else 'MAL'} {nombre} {detalle}")


def main():
    salida = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        pg = nav.new_page(viewport={"width": 1440, "height": 900})
        errores = []
        pg.on("pageerror", lambda e: errores.append(str(e)))
        pg.on("console", lambda m: errores.append(m.text) if m.type == "error" else None)
        pg.goto(PAGINA)
        pg.wait_for_function("typeof visor !== 'undefined' && visor && typeof empezar === 'function' && !!Modelos.datos('FPV')", timeout=120000)
        print("Dron FPV en el navegador:")
        ok("el FPV esta en la lista de aviones", pg.evaluate("Modelos.ids().includes('FPV')"))
        pg.evaluate("salirDelAula(); irInicio(); elegirAvion('FPV'); irHangar()")
        ok("hangar: tarjeta del FPV", pg.evaluate("[...document.querySelectorAll('#selAviones .avCarta')].some(b => b.textContent.includes('dron FPV'))"))
        pg.evaluate("async () => { sesion.escenario = 'libre'; await empezar(); }")
        time.sleep(1.5)
        ok("modelo FPV en ANGLE", pg.evaluate("modelo.esFPV && modelo.modo === 'ANGLE'"))
        ok("camara FPV (3) por defecto", pg.evaluate("visor.camara") == 3)
        ok("OSD a la vista (y no la app del dron comercial)", pg.evaluate("getComputedStyle(document.getElementById('fpv')).display !== 'none' && getComputedStyle(document.getElementById('dji')).display === 'none'"))
        ok("OSD: DISARMED y tension de la bateria", pg.evaluate("document.getElementById('fpvArm').textContent === 'DISARMED' && document.getElementById('fpvBat').textContent.startsWith('16.8V')"),
           pg.evaluate("document.getElementById('fpvArm').textContent + ' · ' + document.getElementById('fpvBat').textContent"))
        ok("ayuda del FPV", pg.evaluate("document.getElementById('ayudaTeclasFPV').style.display === '' && document.getElementById('ayudaTeclasDron').style.display === 'none'"))
        pg.evaluate("av.gases = 0.5; fpvArmar()")
        ok("con el gas arriba no arma", pg.evaluate("av.estado") == "en mano")
        pg.evaluate("av.gases = 0")
        pg.keyboard.press("KeyL"); time.sleep(0.3)
        ok("L arma con el gas abajo", pg.evaluate("av.estado === 'volando' && av.armado && av.posado"))
        ok("armado y con gas cero, motores al ralenti", pg.evaluate("av.motores.every(f => f > 0.03 && f < 0.08)"), str(pg.evaluate("av.motores.map(f => +f.toFixed(3))")))
        pg.keyboard.down("KeyW"); time.sleep(1.4); pg.keyboard.up("KeyW")
        g = pg.evaluate("av.gases")
        ok("W sube el gas", g > 0.35, f"({g:.2f})")
        time.sleep(2.0)
        h = pg.evaluate("-av.p[2] - (entorno.altura ? entorno.altura(av.p[0], av.p[1]) : 0)")
        ok("despega", h > 1.0, f"(altura {h:.1f} m)")
        pg.evaluate("av.gases = 0.33")
        pg.keyboard.press("KeyM"); time.sleep(0.2)
        ok("M cambia a HORIZON", pg.evaluate("modelo.modo") == "HORIZON")
        ok("OSD: modo HOR", pg.evaluate("document.getElementById('fpvModo').textContent") == "HOR")
        pg.keyboard.press("KeyM"); pg.keyboard.press("KeyM"); time.sleep(0.2)
        ok("M vuelve a ANGLE", pg.evaluate("modelo.modo") == "ANGLE")
        if salida:
            salida.mkdir(parents=True, exist_ok=True)
            pg.evaluate("av.gases = 0.36")
            time.sleep(2.5)
            pg.screenshot(path=str(salida / "web_fpv_camara3.png")); print("  captura:", salida / "web_fpv_camara3.png")
        pg.keyboard.press("Digit2"); time.sleep(0.2)
        ok("2: camara de persecucion", pg.evaluate("visor.camara") == 2)
        if salida:
            time.sleep(1.0); pg.screenshot(path=str(salida / "web_fpv_camara2.png")); print("  captura:", salida / "web_fpv_camara2.png")
        pg.keyboard.press("Digit1"); time.sleep(0.2)
        ok("1: camara del piloto", pg.evaluate("visor.camara") == 1)
        pg.keyboard.press("KeyT"); time.sleep(0.2)
        ok("T abre los controles", pg.evaluate("document.getElementById('ayuda').style.display") == "block")
        pg.keyboard.press("Escape"); time.sleep(0.2)
        pg.keyboard.press("Escape"); time.sleep(0.2)
        ok("Esc pausa, con 'OSD' y camara FPV en la pausa", pg.evaluate("pausado && document.getElementById('btnPausaInstr').textContent.startsWith('OSD')"))
        pg.keyboard.press("Escape"); time.sleep(0.2)
        pg.keyboard.press("KeyL"); time.sleep(0.2)
        ok("L desarma en el aire", pg.evaluate("!av.armado"))
        for _ in range(24):                          # desde unos 30 m tarda mas de 3 s en caer
            if pg.evaluate("av.estado") in ("roto", "aterrizado"): break
            time.sleep(0.5)
        ok("desarmado cae y el vuelo termina", pg.evaluate("av.estado") in ("roto", "aterrizado"), "(" + str(pg.evaluate("vuelo && vuelo.final")) + ")")
        # los otros siguen funcionando
        for avion in ("E3", "DJI_MINI"):
            pg.evaluate(f"async () => {{ salirAlMenu(); elegirAvion('{avion}'); sesion.escenario = 'libre'; await empezar(); }}")
            time.sleep(1.0)
            ok(f"{avion} arranca", pg.evaluate("!modelo.esFPV && av.estado === 'en mano' && !document.body.classList.contains('fpv')"))
        ok("sin errores en la pagina", not errores, "; ".join(errores[:5]))
        nav.close()
    print("RESULTADO: " + ("todo bien" if fallos == 0 else f"{fallos} fallos"))
    sys.exit(1 if fallos else 0)


if __name__ == "__main__":
    main()
