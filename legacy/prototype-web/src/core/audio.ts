/**
 * Tiny WebAudio blip synth.
 *
 * No audio files: the foundation only needs feedback cues, and synthesised
 * tones keep the bundle small and sidestep mobile autoplay policies (the
 * context is created lazily on the first user gesture).
 */

type Voice = 'jump' | 'land' | 'grab' | 'relic' | 'hurt' | 'sword' | 'door';

interface VoiceSpec {
  type: OscillatorType;
  from: number;
  to: number;
  duration: number;
  gain: number;
}

const VOICES: Record<Voice, VoiceSpec> = {
  jump: { type: 'triangle', from: 300, to: 620, duration: 0.11, gain: 0.16 },
  land: { type: 'sine', from: 180, to: 70, duration: 0.1, gain: 0.2 },
  grab: { type: 'square', from: 420, to: 300, duration: 0.06, gain: 0.08 },
  relic: { type: 'triangle', from: 740, to: 1180, duration: 0.22, gain: 0.14 },
  hurt: { type: 'sawtooth', from: 260, to: 90, duration: 0.26, gain: 0.18 },
  sword: { type: 'sawtooth', from: 900, to: 320, duration: 0.12, gain: 0.1 },
  door: { type: 'triangle', from: 420, to: 880, duration: 0.5, gain: 0.16 },
};

export class Audio {
  muted = false;

  private context: AudioContext | null = null;
  private master: GainNode | null = null;

  /** Must be called from a user gesture handler on mobile. */
  unlock(): void {
    if (this.context) {
      void this.context.resume();
      return;
    }
    const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Ctor) return;
    this.context = new Ctor();
    this.master = this.context.createGain();
    this.master.gain.value = 0.6;
    this.master.connect(this.context.destination);
  }

  play(voice: Voice, pitchScale = 1): void {
    if (this.muted || !this.context || !this.master) return;
    const spec = VOICES[voice];
    const now = this.context.currentTime;

    const osc = this.context.createOscillator();
    const gain = this.context.createGain();
    osc.type = spec.type;
    osc.frequency.setValueAtTime(spec.from * pitchScale, now);
    osc.frequency.exponentialRampToValueAtTime(Math.max(20, spec.to * pitchScale), now + spec.duration);
    gain.gain.setValueAtTime(spec.gain, now);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + spec.duration);

    osc.connect(gain).connect(this.master);
    osc.start(now);
    osc.stop(now + spec.duration + 0.02);
  }
}
