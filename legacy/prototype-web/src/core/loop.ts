/**
 * Fixed-timestep game loop.
 *
 * Simulation always advances in constant `step` slices so physics is identical
 * on a 60 Hz phone and a 120 Hz tablet. Rendering happens once per animation
 * frame with an `alpha` value for interpolating between the last two states.
 */

export interface LoopHandlers {
  /** Advance the simulation by exactly `dt` seconds. */
  update(dt: number): void;
  /** Draw. `alpha` is 0..1 progress towards the next simulation step. */
  render(alpha: number): void;
}

export class GameLoop {
  readonly step: number;

  private accumulator = 0;
  private lastTime = 0;
  private rafId = 0;
  private running = false;

  /** Hard cap so a backgrounded tab does not produce a death-spiral catch-up. */
  private readonly maxFrameTime: number;

  constructor(private readonly handlers: LoopHandlers, stepHz = 60) {
    this.step = 1 / stepHz;
    this.maxFrameTime = this.step * 5;
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    this.lastTime = performance.now();
    this.accumulator = 0;
    this.rafId = requestAnimationFrame(this.tick);
  }

  stop(): void {
    this.running = false;
    cancelAnimationFrame(this.rafId);
  }

  /** Drop accumulated time — call after a long pause to avoid a time jump. */
  resetClock(): void {
    this.lastTime = performance.now();
    this.accumulator = 0;
  }

  private tick = (now: number): void => {
    if (!this.running) return;
    this.rafId = requestAnimationFrame(this.tick);

    let frameTime = (now - this.lastTime) / 1000;
    this.lastTime = now;
    if (!Number.isFinite(frameTime) || frameTime < 0) frameTime = 0;
    if (frameTime > this.maxFrameTime) frameTime = this.maxFrameTime;

    this.accumulator += frameTime;
    while (this.accumulator >= this.step) {
      this.handlers.update(this.step);
      this.accumulator -= this.step;
    }

    this.handlers.render(this.accumulator / this.step);
  };
}
