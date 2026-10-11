// Tandem T1: fisica con ELEVONES. scripts/modelo_aero_t1.py copia esta clase al principio de simulador/aviones/T1.js
// y registra los datos con ella.
// Las dos superficies del ala trasera hacen de profundidad y de alerones a la vez: cada elevon recibe la suma de la
// consigna de profundidad (de, + = borde de fuga abajo) y la de alabeo (da, + = elevon derecho arriba = alabeo a la
// derecha), con el recorrido mecanico de cada superficie (mandos.elevon_max_grados) como tope: si la suma se pasa,
// se reducen las dos consignas en la misma proporcion, como hace el mezclador de la emisora. Las derivadas CLde, Cmde,
// Clda, Cnda y CYda salen del VLM (analisis/vlm_e1.py, configuracion tandem). No hay timon (dr siempre 0).
// La resistencia de la helice parada (CD_helice_parada) la suma ModeloAvion.paso().
class ModeloT1 extends ModeloAvion {
  estadoInicial() { const av = super.estadoInicial(); av.da = 0; av.elevon_izq = 0; av.elevon_der = 0; return av; }

  /** Palanca -> consignas de profundidad (de) y alabeo (da) -> mezcla y tope por elevon -> servos con retardo. */
  servos(av, mando, dt) {
    const m = this.mandos, e = m.expo, ex = s => (1 - e) * s + e * s * s * s;
    let deObj = -ex(mando.pitch) * m.prof_max_grados * D2R + mando.trim * D2R;    // tirar -> borde de fuga arriba
    let daObj = ex(mando.yaw) * m.aleron_max_grados * D2R;                        // derecha -> alabeo a la derecha
    const tope = m.elevon_max_grados * D2R, suma = Math.abs(deObj) + Math.abs(daObj);
    if (suma > tope) { deObj *= tope / suma; daObj *= tope / suma; }
    // cada elevon es un servo: izquierdo = de + da (con da > 0 baja), derecho = de - da (sube)
    const vmax = m.servo_vel_grados_s * D2R;
    for (const [k, obj] of [["elevon_izq", deObj + daObj], ["elevon_der", deObj - daObj]])
      av[k] += Math.max(-vmax * dt, Math.min(vmax * dt, (obj - av[k]) * dt / m.servo_tau_s));
    av.de = 0.5 * (av.elevon_izq + av.elevon_der);
    av.da = 0.5 * (av.elevon_izq - av.elevon_der);
    av.dr = 0;
  }

  /** Aportacion de los elevones a los coeficientes en paso(): la parte simetrica (de) como profundidad y la
   *  antisimetrica (da) como alerones, con su guinada adversa (Cnda). */
  mandosCoef(av, d, kman) {
    const de = av.de * kman, da = av.da * kman;
    return { CL: d("CLde") * de, CY: d("CYda") * da, Cl: d("Clda") * da, Cm: d("Cmde") * de, Cn: d("Cnda") * da };
  }

}
