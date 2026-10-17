// Entrenador E2: fisica con alerones y profundidad. scripts/modelo_aero_e1.py (con ENTRENADOR=E2) copia esta
// clase al principio de datos/vehiculos/E2.js y registra los datos con ella.
// Las flechas izquierda/derecha mueven los alerones (da, + = aleron derecho arriba = alabeo a la derecha) en vez
// del timon; la deriva es fija (dr siempre 0). Las derivadas Clda, Cnda y CYda salen del VLM (analisis/vlm_e1.py).
class ModeloE2 extends ModeloAvion {
  estadoInicial() { const av = super.estadoInicial(); av.da = 0; return av; }

  /** Palanca -> consigna de profundidad (de) y alerones (da) -> servos con retardo y velocidad maxima. */
  servos(av, mando, dt) {
    const m = this.mandos, e = m.expo, ex = s => (1 - e) * s + e * s * s * s;
    const deObj = -ex(mando.pitch) * m.prof_max_grados * D2R + mando.trim * D2R;   // tirar -> profundidad arriba
    const daObj = ex(mando.yaw) * m.aleron_max_grados * D2R;                       // derecha -> alabeo a la derecha
    const vmax = m.servo_vel_grados_s * D2R;
    for (const [k, obj] of [["de", deObj], ["da", daObj]])
      av[k] += Math.max(-vmax * dt, Math.min(vmax * dt, (obj - av[k]) * dt / m.servo_tau_s));
    av.dr = 0;
  }

  /** Aportacion de los mandos a los coeficientes en paso(): profundidad y alerones (guinada adversa incluida en Cnda). */
  mandosCoef(av, d, kman) {
    const de = av.de * kman, da = av.da * kman;
    return { CL: d("CLde") * de, CY: d("CYda") * da, Cl: d("Clda") * da, Cm: d("Cmde") * de, Cn: d("Cnda") * da };
  }
}
