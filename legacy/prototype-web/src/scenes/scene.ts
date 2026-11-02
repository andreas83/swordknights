import type { Audio } from '../core/audio';
import type { Input } from '../core/input';
import type { Renderer } from '../render/renderer';
import type { SaveData } from '../core/storage';

export interface GameContext {
  readonly renderer: Renderer;
  readonly input: Input;
  readonly audio: Audio;
  readonly save: SaveData;
  persist(): void;
  setScene(scene: Scene): void;
}

export interface Scene {
  enter?(ctx: GameContext): void;
  exit?(ctx: GameContext): void;
  update(dt: number, ctx: GameContext): void;
  /** `alpha` is the sub-step progress from the fixed-timestep loop. */
  draw(renderer: Renderer, alpha: number, ctx: GameContext): void;
  resize?(ctx: GameContext): void;
}
