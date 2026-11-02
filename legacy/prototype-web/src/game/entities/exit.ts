import { PALETTE } from '../../render/palette';
import { TILE_SIZE } from '../tiles';
import type { Renderer } from '../../render/renderer';
import type { Rect } from '../../core/math';
import type { Entity, EntityContext } from './entity';

/** The arched doorway that ends the level. */
export class ExitDoor implements Entity {
  readonly kind = 'exit';
  readonly bounds: Rect;
  dead = false;
  open = false;

  constructor(x: number, y: number) {
    this.bounds = { x: x - TILE_SIZE / 2, y: y - TILE_SIZE * 2, w: TILE_SIZE, h: TILE_SIZE * 2 };
  }

  update(_ctx: EntityContext): void {
    /* static */
  }

  draw(renderer: Renderer, time: number): void {
    const { x, y, w, h } = this.bounds;
    renderer.fillArch(x - 2, y - 2, w + 4, h + 2, PALETTE.shadowDeep);
    renderer.fillArch(x, y, w, h, this.open ? PALETTE.lightSoft : PALETTE.ink);
    if (this.open) {
      const pulse = 0.5 + Math.sin(time * 3) * 0.15;
      renderer.fillArch(x + 2, y + 3, w - 4, h - 3, PALETTE.paper);
      renderer.fillCircle(x + w / 2, y + h * 0.5, 5 + pulse * 2, PALETTE.paper);
    } else {
      renderer.fillRect(x + w / 2 - 0.5, y + 6, 1, h - 10, PALETTE.shadowWarm);
      renderer.fillCircle(x + w / 2 - 2.5, y + h * 0.55, 1.2, PALETTE.lightWarm);
      renderer.fillCircle(x + w / 2 + 2.5, y + h * 0.55, 1.2, PALETTE.lightWarm);
    }
  }
}
