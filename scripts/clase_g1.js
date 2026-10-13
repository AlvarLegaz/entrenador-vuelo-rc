// Poli-1 (y cualquier avion de 4 canales): fisica con alerones, profundidad y timon. scripts/modelo_aero_g1.py copia
// esta clase al principio de simulador/aviones/G1.js y registra los datos con ella.
// Como en una emisora en modo 2: la palanca derecha mueve profundidad y alerones (flechas del teclado) y la izquierda,
// de lado, el timon (A / D del teclado, mando.guinada). da > 0 = aleron derecho arriba (alabeo a la derecha); dr > 0 =
// timon a la derecha. Las derivadas Clda, Cnda, CYda (alerones) y CYdr, Cldr, Cndr (timon) salen del VLM.
// Nota: ModeloAvion.paso() multiplica CY, Cl y Cn de los mandos por el chorro de la helice cuando hay timon; en este
// avion los alerones son interiores y van en parte dentro de la estela, asi que es una aproximacion razonable.
class ModeloG1 extends ModeloAvion {
  estadoInicial() { const av = super.estadoInicial(); av.da = 0; return av; }

  /** Palancas -> consignas de profundidad (de), alerones (da) y timon (dr) -> servos con retardo y velocidad maxima. */
  servos(av, mando, dt) {
    const m = this.mandos, e = m.expo, ex = s => (1 - e) * s + e * s * s * s;
    const deObj = -ex(mando.pitch) * m.prof_max_grados * D2R + mando.trim * D2R;   // tirar -> profundidad arriba
    const daObj = ex(mando.yaw) * m.aleron_max_grados * D2R;                       // derecha -> alabeo a la derecha
    const drObj = ex(mando.guinada || 0) * m.timon_max_grados * D2R;               // palanca izquierda a la derecha -> timon a la derecha
    const vmax = m.servo_vel_grados_s * D2R;
    for (const [k, obj] of [["de", deObj], ["da", daObj], ["dr", drObj]])
      av[k] += Math.max(-vmax * dt, Math.min(vmax * dt, (obj - av[k]) * dt / m.servo_tau_s));
  }

  /** Aportacion de los mandos a los coeficientes en paso(): profundidad, alerones (guinada adversa en Cnda) y timon. */
  mandosCoef(av, d, kman) {
    const de = av.de * kman, da = av.da * kman, dr = av.dr * kman;
    return { CL: d("CLde") * de, CY: d("CYda") * da + d("CYdr") * dr, Cl: d("Clda") * da + d("Cldr") * dr,
             Cm: d("Cmde") * de, Cn: d("Cnda") * da + d("Cndr") * dr };
  }
}
