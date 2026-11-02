import { PALETTE, withAlpha } from '../../render/palette';
import type { Renderer } from '../../render/renderer';
import type { Rect } from '../../core/math';
import type { Entity, EntityContext } from './entity';

/** Pure decoration: a wall torch whose flicker sells the hard duotone light. */
export class Torch implements Entity {
  readonly kind = 'torch';
  readonly bounds: Rect;
  dead = false;

  private readonly phase: number;

  constructor(x: number, y: number) {
    this.bounds = { x: x - 2, y: y - 14, w: 4, h: 14 };
    this.phase = (x * 0.37 + y * 0.11) % Math.PI;
  }

  update(_ctx: EntityContext): void {
    /* static */
  }

  draw(renderer: Renderer, time: number): void {
    const cx = this.bounds.x + this.bounds.w / 2;
    const top = this.bounds.y;
    const flicker = 0.72 + Math.sin(time * 9 + this.phase) * 0.12 + Math.sin(time * 23 + this.phase) * 0.06;

    renderer.fillCircle(cx, top + 2, 11 * flicker, withAlpha(PALETTE.light, 0.1));
    renderer.fillCircle(cx, top + 2, 6 * flicker, withAlpha(PALETTE.lightSoft, 0.16));
    renderer.fillRect(cx - 1, top + 4, 2, this.bounds.h - 4, PALETTE.shadowDeep);
    renderer.fillPoly(
      [
        [cx, top - 4 * flicker],
        [cx + 2.4, top + 3],
        [cx, top + 5],
        [cx - 2.4, top + 3],
      ],
      PALETTE.lightSoft,
    );
    renderer.fillPoly(
      [
        [cx, top - 1 * flicker],
        [cx + 1.2, top + 3],
        [cx - 1.2, top + 3],
      ],
      PALETTE.paper,
    );
  }
}
