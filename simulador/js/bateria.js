"use strict";
// =====================================================================
//  BATERIA de los vehiculos electricos (scripts/bateria.gd en Godot: el mismo calculo, para que los dos simuladores
//  vuelen igual). Celdas en serie con su curva de tension en vacio segun la carga, LiPo (FPV y aviones) o Li-ion
//  (drones comerciales); resistencia interna que hace caer la tension con la corriente (mas con frio); capacidad algo
//  menor con frio; un pequeno desequilibrio entre celdas que crece al vaciarse; y la temperatura del pack, que sube con
//  la corriente (I^2 R) y se enfria hacia la del aire. Agotada, la tension se desploma.
//  Uso en un modelo: B = Bateria.datos(propulsion); estado e = Bateria.nueva(B, tempC); en cada paso V =
//  Bateria.tension(B, e) (con la potencia del paso anterior) y, con la potencia de este paso, Bateria.gastar(B, e, P, dt).
// =====================================================================
const Bateria = {
  // tension en vacio de una celda (V) segun la carga que le queda (0 vacia, 1 llena)
  CURVAS: {
    lipo: { soc: [0, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1], v: [3.27, 3.5, 3.62, 3.7, 3.75, 3.79, 3.83, 3.87, 3.92, 4.0, 4.08, 4.2] },
    liion: { soc: [0, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1], v: [3.0, 3.3, 3.42, 3.52, 3.6, 3.66, 3.72, 3.8, 3.89, 3.98, 4.08, 4.2] },
  },
  DESEQUILIBRIO_V: [0, -0.006, 0.003, -0.004, 0.005, -0.002],      // de cada celda respecto a la media, con la bateria llena
  H_W_K: 0.3,                                                         // enfriamiento del pack (W por grado sobre el aire)

  /** Datos de la bateria de un vehiculo: su bloque "bateria" o, si no lo tiene, los de su propulsion (el FPV: celdas,
   *  mAh, resistencia y curva) o los de un avion electrico (LiPo 3S con la energia de masa_bateria_Wh). */
  datos(pr) {
    if (pr.bateria) return Object.assign({ curva: null, R_ohm: 0.05, masa_kg: 0.1 }, pr.bateria);
    if (pr.celdas) return { quimica: "lipo", celdas: pr.celdas, capacidad_mAh: pr.capacidad_mAh, R_ohm: pr.R_ohm, masa_kg: pr.masa_bateria_Wh / 140,
                            curva: pr.curva_soc ? { soc: pr.curva_soc, v: pr.curva_v } : null };
    return { quimica: "lipo", celdas: 3, capacidad_mAh: Math.round(pr.masa_bateria_Wh / 11.1 * 1000), R_ohm: 0.03, masa_kg: pr.masa_bateria_Wh / 140, curva: null };
  },
  /** Bateria llena a la temperatura del aire (grados C). */
  nueva(B, tempC) {
    const e = { mAh: 0, Wh: 0, P: 0, I: 0, V: 0, T: tempC, Tamb: tempC, celdas: new Array(B.celdas).fill(0),
                fCap: Math.max(0.6, Math.min(1, 1 - 0.008 * Math.max(0, 25 - tempC))) };     // con frio rinde menos
    Bateria.tension(B, e);
    return e;
  },
  capacidad(B, e) { return B.capacidad_mAh * e.fCap; },
  /** Carga que le queda (%). */
  pct(B, e) { return Math.max(0, 100 * (1 - e.mAh / Bateria.capacidad(B, e))); },
  /** Resistencia interna del pack a su temperatura (sube con el frio). */
  R(B, e) { return B.R_ohm * (1 + 0.04 * Math.max(0, 25 - e.T)); },
  /** Tension en vacio de una celda con la carga gastada; agotada (mas alla de su capacidad), se desploma (hasta 2,5 V). */
  ocvCelda(B, e) {
    const C = B.curva || Bateria.CURVAS[B.quimica] || Bateria.CURVAS.lipo, cap = Bateria.capacidad(B, e);
    const soc = Math.max(0, Math.min(1, 1 - e.mAh / cap));
    return Math.max(2.5, interp(C.soc, C.v, soc) - 6 * Math.max(0, e.mAh - cap) / cap);
  },
  /** Tension en bornes (V) con la potencia que se pide (la del paso anterior, e.P): en vacio menos la caida por la
   *  resistencia interna. Si se pide mas de lo que puede dar, se queda en la mitad (potencia maxima). Pone tambien la
   *  tension de cada celda. */
  tension(B, e) {
    const soc = Math.max(0, Math.min(1, 1 - e.mAh / Bateria.capacidad(B, e))), ocv = Bateria.ocvCelda(B, e), R = Bateria.R(B, e), n = B.celdas;
    let Voc = 0;
    for (let i = 0; i < n; i++) { e.celdas[i] = ocv + Bateria.DESEQUILIBRIO_V[i % 6] * (1 + 2 * (1 - soc)); Voc += e.celdas[i]; }
    const disc = Voc * Voc - 4 * R * e.P, V = disc > 0 ? 0.5 * (Voc + Math.sqrt(disc)) : 0.5 * Voc, I = e.P / Math.max(0.1, V);
    for (let i = 0; i < n; i++) e.celdas[i] -= I * R / n;
    e.V = V; e.I = I;
    return V;
  },
  /** Gasta la potencia P (W) durante dt (s): corriente, carga, energia y calentamiento. */
  gastar(B, e, P, dt) {
    e.P = Math.max(0, P); e.I = e.P / Math.max(0.1, e.V);
    e.mAh += e.I * dt / 3.6; e.Wh += e.P * dt / 3600;
    e.T += (e.I * e.I * Bateria.R(B, e) - Bateria.H_W_K * (e.T - e.Tamb)) * dt / (1000 * B.masa_kg);
  },
  /** Tension de la celda mas baja (V). */
  celdaMin(B, e) { let m = Infinity; for (const c of e.celdas) m = Math.min(m, c); return m; },
};
