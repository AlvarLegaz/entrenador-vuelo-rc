"""Que entrenador generan los scripts: E1 (por defecto) o el que diga la variable de entorno ENTRENADOR.

    set ENTRENADOR=E2            (cmd)        $env:ENTRENADOR = "E2"   (PowerShell)
    python scripts/geom_e1.py ...

Todos los scripts (geom, masas, vlm, modelo_aero, vistas) leen de aqui el modulo de parametros (P) y la
carpeta de salida: scripts/out para el E1 y scripts/out_E2 para el E2.
"""
import importlib, os

ID = os.environ.get("ENTRENADOR", "E1").strip().upper() or "E1"
P = importlib.import_module("parametros_" + ID.lower())
OUT_NOMBRE = "out" if ID == "E1" else "out_" + ID
