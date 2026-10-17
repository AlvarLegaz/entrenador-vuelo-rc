// Sonido (Web Audio): motor, viento, aviso de perdida y toque.
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: simulador_godot/scripts/sonido.gd.
"use strict";
// =====================================================================
//  SONIDO (Web Audio): motor segun las revoluciones y el gas, viento segun la velocidad, aviso de perdida y toque
// =====================================================================
const Sonido = {
  on: true, vol: 0.6, ctx: null, _n: null, _silencio: false,
  cargarCfg() { try { const s = JSON.parse(localStorage.getItem("sim_sonido") || "{}"); if (s.on !== undefined) this.on = !!s.on; if (s.vol !== undefined) this.vol = +s.vol; } catch (e) {} },
  guardarCfg() { try { localStorage.setItem("sim_sonido", JSON.stringify({ on: this.on, vol: this.vol })); } catch (e) {} this.aplicarVolumen(); },
  /** Crea el contexto (hace falta un gesto del usuario: se llama al pulsar Volar y al pulsar teclas). */
  iniciar() {
    if (!this.on) return;
    if (this.ctx) { if (this.ctx.state === "suspended") this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext; if (!AC) return;
    const C = this.ctx = new AC(), master = C.createGain(); master.gain.value = 0; master.connect(C.destination);
    // motor: diente de sierra (fundamental) + cuadrada (paso de pala, 2 palas), por un filtro paso bajo que se abre con el gas
    const fMotor = C.createBiquadFilter(); fMotor.type = "lowpass"; fMotor.frequency.value = 800; fMotor.Q.value = 0.9;
    const gMotor = C.createGain(); gMotor.gain.value = 0; fMotor.connect(gMotor); gMotor.connect(master);
    const o1 = C.createOscillator(); o1.type = "sawtooth"; o1.frequency.value = 60; const g1 = C.createGain(); g1.gain.value = 0.7; o1.connect(g1); g1.connect(fMotor); o1.start();
    const o2 = C.createOscillator(); o2.type = "square"; o2.frequency.value = 120; const g2 = C.createGain(); g2.gain.value = 0.22; o2.connect(g2); g2.connect(fMotor); o2.start();
    // viento: ruido blanco por un paso banda cuya frecuencia y ganancia suben con la velocidad
    const buf = C.createBuffer(1, C.sampleRate * 2, C.sampleRate), d = buf.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    const ruido = C.createBufferSource(); ruido.buffer = buf; ruido.loop = true;
    const fViento = C.createBiquadFilter(); fViento.type = "bandpass"; fViento.frequency.value = 400; fViento.Q.value = 0.5;
    const gViento = C.createGain(); gViento.gain.value = 0; ruido.connect(fViento); fViento.connect(gViento); gViento.connect(master); ruido.start();
    // aviso de perdida: pitido intermitente
    const oP = C.createOscillator(); oP.type = "sine"; oP.frequency.value = 880; const gP = C.createGain(); gP.gain.value = 0; oP.connect(gP); gP.connect(master); oP.start();
    this._n = { master, fMotor, gMotor, o1, o2, fViento, gViento, gP, buf }; this.aplicarVolumen();
  },
  aplicarVolumen() { if (this._n) this._n.master.gain.setTargetAtTime(this.on && !this._silencio ? this.vol : 0, this.ctx.currentTime, 0.05); },
  silenciar(s) { this._silencio = s; this.aplicarVolumen(); },
  actualizar(av) {
    if (!this._n) return;
    const n = this._n, t = this.ctx.currentTime, k = 0.08, rpm = av.rpm || 0, f = Math.max(25, rpm / 60);
    // en la camara del piloto el motor llega de lejos: cae con la distancia al piloto
    let lejos = 1;
    if (visor.camara === 1) { const b = visor.base || [0, 0, 0], p = ned2three(av.p); lejos = 1 / (1 + Math.hypot(p[0] - b[0], p[1] - b[1], p[2] - b[2]) / 45); }
    n.o1.frequency.setTargetAtTime(f, t, k); n.o2.frequency.setTargetAtTime(2 * f, t, k);
    n.fMotor.frequency.setTargetAtTime(500 + 2600 * av.gases, t, k);
    n.gMotor.gain.setTargetAtTime(rpm > 0 ? (0.06 + 0.3 * Math.pow(av.gases, 1.3)) * lejos : 0, t, k);
    const V = av.estado === "volando" ? (av.V || 0) : 0;
    n.fViento.frequency.setTargetAtTime(250 + 30 * V, t, k);
    n.gViento.gain.setTargetAtTime(Math.min(0.45, 0.0011 * V * V) * (visor.camara === 1 ? 0.35 * lejos : 1), t, k);
    const perdida = av.estado === "volando" && av.perdida > 0.5 && -av.p[2] > 2;
    n.gP.gain.setTargetAtTime(perdida && Math.floor(t * 4) % 2 === 0 ? 0.1 : 0, t, 0.015);
  },
  /** "toque" (aterrizaje), "roto" (accidente) y, del bipode, "pisada", "disparo" y "explosion". */
  evento(tipo) {
    if (!this._n) return;
    if (tipo === "pisada" || tipo === "disparo" || tipo === "explosion") {
      const C = this.ctx, n = this._n, t = C.currentTime, s = C.createBufferSource(); s.buffer = n.buf;
      const [fq, ga, dur, tipoF] = { pisada: [140, 0.9, 0.35, "lowpass"], disparo: [1400, 0.22, 0.07, "bandpass"], explosion: [260, 0.8, 1.2, "lowpass"] }[tipo];
      const f = C.createBiquadFilter(); f.type = tipoF; f.frequency.value = fq; f.Q.value = tipoF === "bandpass" ? 0.8 : 0.7;
      const g = C.createGain(); g.gain.setValueAtTime(ga, t); g.gain.exponentialRampToValueAtTime(0.001, t + dur);
      s.connect(f); f.connect(g); g.connect(n.master); s.start(t, Math.random() * 1.5); s.stop(t + dur + 0.05);
      if (tipo === "pisada") {                        // golpe sordo del pie: un seno grave que cae
        const o = C.createOscillator(), go = C.createGain(); o.type = "sine"; o.frequency.setValueAtTime(70, t); o.frequency.exponentialRampToValueAtTime(32, t + 0.25);
        go.gain.setValueAtTime(0.7, t); go.gain.exponentialRampToValueAtTime(0.001, t + 0.3); o.connect(go); go.connect(n.master); o.start(t); o.stop(t + 0.32);
      }
      return;
    }
    const C = this.ctx, n = this._n, t = C.currentTime, s = C.createBufferSource(); s.buffer = n.buf;
    const f = C.createBiquadFilter(); f.type = "lowpass"; f.frequency.value = tipo === "roto" ? 350 : 900;
    const g = C.createGain(); g.gain.setValueAtTime(tipo === "roto" ? 0.9 : 0.3, t); g.gain.exponentialRampToValueAtTime(0.001, t + (tipo === "roto" ? 0.7 : 0.18));
    s.connect(f); f.connect(g); g.connect(n.master); s.start(t); s.stop(t + 0.8);
  },
};
function pintarSonidoCfg() {
  document.getElementById("sonidoOn").checked = Sonido.on; document.getElementById("sonidoVol").value = Math.round(Sonido.vol * 100);
  document.getElementById("sonidoVolTxt").textContent = Math.round(Sonido.vol * 100) + " %";
}
document.getElementById("sonidoOn").addEventListener("change", e => { Sonido.on = e.target.checked; Sonido.guardarCfg(); Sonido.iniciar(); });
document.getElementById("sonidoVol").addEventListener("input", e => { Sonido.vol = +e.target.value / 100; Sonido.guardarCfg(); pintarSonidoCfg(); });
document.getElementById("pausaSonido").addEventListener("change", e => { Sonido.on = e.target.checked; Sonido.guardarCfg(); Sonido.iniciar(); });
