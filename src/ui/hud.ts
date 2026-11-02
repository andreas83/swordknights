/** Diegetic-ish HUD: health crescents, relic tally and the level title card. */

import { PALETTE, withAlpha } from '../render/palette';
import { clamp } from '../core/math';
import type { Renderer } from '../render/renderer';

export interface HudModel {
  health: number;
  maxHealth: number;
  relics: number;
  relicsTotal: number;
  levelName: string;
  /** Seconds since the level started — drives the title card. */
  elapsed: number;
}

const TITLE_HOLD = 2.6;
const TITLE_FADE = 0.9;

export class Hud {
  draw(renderer: Renderer, model: HudModel): void {
    const safe = renderer.safe;
    const x = safe.left + 10;
    const y = safe.top + 10;

    for (let i = 0; i < model.maxHealth; i++) {
      const filled = i < model.health;
      const cx = x + i * 13;
      renderer.fillCircle(cx, y, 4.6, withAlpha(PALETTE.ink, 0.35));
      if (filled) {
        renderer.fillCircle(cx, y, 4, PALETTE.lightSoft);
        renderer.fillCircle(cx + 1.4, y - 0.8, 3.1, withAlpha(PALETTE.ink, 0.55));
      } else {
        renderer.ctx.strokeStyle = withAlpha(PALETTE.lightSoft, 0.4);
        renderer.ctx.lineWidth = 1;
        renderer.ctx.beginPath();
        renderer.ctx.arc(cx, y, 4, 0, Math.PI * 2);
        renderer.ctx.stroke();
      }
    }

    if (model.relicsTotal > 0) {
      const rx = x + model.maxHealth * 13 + 8;
      renderer.fillPoly(
        [
          [rx, y - 4.5],
          [rx + 3.2, y],
          [rx, y + 4.5],
          [rx - 3.2, y],
        ],
        PALETTE.light,
      );
      renderer.text(`${model.relics}/${model.relicsTotal}`, rx + 7, y, {
        size: 8,
        baseline: 'middle',
        color: PALETTE.paper,
        tracking: 0.4,
      });
    }

    this.drawTitleCard(renderer, model);
  }

  private drawTitleCard(renderer: Renderer, model: HudModel): void {
    if (model.elapsed > TITLE_HOLD + TITLE_FADE) return;
    const alpha = clamp(1 - (model.elapsed - TITLE_HOLD) / TITLE_FADE, 0, 1);
    const cx = renderer.width / 2;
    const cy = renderer.height * 0.33;

    renderer.text(model.levelName.toUpperCase(), cx, cy, {
      size: 15,
      align: 'center',
      baseline: 'middle',
      color: withAlpha(PALETTE.paper, alpha),
      tracking: 4,
    });
    renderer.fillRect(cx - 34, cy + 12, 68, 1, withAlpha(PALETTE.lightSoft, alpha * 0.8));
  }
}
