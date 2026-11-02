import type { Rect } from '../../core/math';
import type { Renderer } from '../../render/renderer';
import type { World } from '../world';

export interface EntityContext {
  world: World;
  dt: number;
}

/** Everything the level spawns implements this. */
export interface Entity {
  readonly kind: string;
  /** World-space collision/trigger box. */
  readonly bounds: Rect;
  /** Set to true to have the scene drop it at the end of the step. */
  dead: boolean;
  update(ctx: EntityContext): void;
  draw(renderer: Renderer, time: number): void;
}
