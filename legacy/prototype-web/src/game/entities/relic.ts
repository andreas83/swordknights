import { PALETTE } from '../../render/palette';
import type { Renderer } from '../../render/renderer';
import type { Rect } from '../../core/math';
import type { Entity, EntityContext } from './entity';

/** A collectible shard — the level's optional objective. */
export class Relic implements Entity {
  readonly kind = 'relic';
  readonly bounds: Rect;
  dead = false;
  collected = false;

  private bob = 0;

  constructor(x: number, y: number) {
    this.bounds = { x: x - 5, y: y - 16, w: 10, h: 12 };
  }

  update(ctx: EntityContext): void {
    this.bob += ctx.dt;
  }

  collect(): void {
    this.collected = true;
    this.dead = true;
  }

  draw(renderer: Renderer, time: number): void {
    const cx = this.bounds.x + this.bounds.w / 2;
    const cy = this.bounds.y + this.bounds.h / 2 + Math.sin((time + this.bob) * 2.4) * 1.6;
    const r = 4.5;
    renderer.fillPoly(
      [
        [cx, cy - r],
        [cx + r * 0.72, cy],
        [cx, cy + r],
        [cx - r * 0.72, cy],
      ],
      PALETTE.lightSoft,
    );
    renderer.fillPoly(
      [
        [cx, cy - r],
        [cx + r * 0.72, cy],
        [cx, cy],
      ],
      PALETTE.paper,
    );
  }
}
