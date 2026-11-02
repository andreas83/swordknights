/**
 * Layered backdrop: a crimson sun-washed skyline of arches, towers and domes.
 *
 * Generated procedurally from a seeded PRNG so there are no image assets to
 * ship (important for an install-size-sensitive mobile build) and so the
 * silhouette can be re-rolled per level by changing the seed.
 */

import { mulberry32 } from '../core/math';
import { PALETTE, SKY_STOPS, withAlpha } from './palette';
import { MAX_VIRTUAL_WIDTH } from './renderer';
import type { Renderer } from './renderer';

interface Building {
  x: number;
  w: number;
  h: number;
  /** 0 flat roof, 1 dome, 2 stepped tower. */
  cap: number;
  windows: number;
}

interface Layer {
  depth: number;
  color: string;
  /** Horizon height as a fraction of the view, resolved at draw time. */
  baseline: number;
  buildings: Building[];
}

export class Parallax {
  private readonly layers: Layer[];

  constructor(seed: number, worldWidth: number) {
    const rng = mulberry32(seed);
    const spans = Math.max(MAX_VIRTUAL_WIDTH * 2, worldWidth * 0.6);

    this.layers = [
      { depth: 0.12, color: withAlpha(PALETTE.shadow, 0.55), baseline: 0.74, buildings: [] },
      { depth: 0.26, color: withAlpha(PALETTE.shadowWarm, 0.72), baseline: 0.82, buildings: [] },
      { depth: 0.46, color: PALETTE.mid, baseline: 0.92, buildings: [] },
    ];

    for (const layer of this.layers) {
      let x = -MAX_VIRTUAL_WIDTH * 0.5;
      const scale = 0.55 + layer.depth;
      while (x < spans) {
        const w = (18 + rng() * 44) * scale;
        const h = (26 + rng() * 78) * scale;
        layer.buildings.push({
          x,
          w,
          h,
          cap: Math.floor(rng() * 3),
          windows: Math.floor(rng() * 4),
        });
        x += w + rng() * 10 * scale;
      }
    }
  }

  draw(renderer: Renderer, cameraX: number, cameraY: number, time: number): void {
    const viewWidth = renderer.width;
    const viewHeight = renderer.height;
    renderer.verticalGradient(0, 0, viewWidth, viewHeight, SKY_STOPS);
    this.drawSun(renderer, cameraX, time);

    for (const layer of this.layers) {
      const offsetX = -cameraX * layer.depth;
      const offsetY = -cameraY * layer.depth * 0.35;
      const baseline = viewHeight * layer.baseline + offsetY;
      for (const building of layer.buildings) {
        const bx = building.x + offsetX;
        if (bx + building.w < -8 || bx > viewWidth + 8) continue;
        this.drawBuilding(renderer, building, bx, baseline, layer.color);
      }
      // Haze band hides the layer's feet and separates it from the next one.
      renderer.verticalGradient(0, baseline - 4, viewWidth, 24, [
        [0, withAlpha(PALETTE.mid, 0)],
        [1, withAlpha(PALETTE.mid, 0.5)],
      ]);
    }
  }

  private drawBuilding(renderer: Renderer, b: Building, x: number, baseline: number, color: string): void {
    const top = baseline - b.h;
    renderer.fillRect(x, top, b.w, b.h, color);

    switch (b.cap) {
      case 1: {
        // Onion dome.
        const r = Math.min(b.w * 0.42, 14);
        renderer.fillCircle(x + b.w / 2, top - r * 0.45, r, color);
        renderer.fillRect(x + b.w / 2 - 0.6, top - r * 2.1, 1.2, r * 0.9, color);
        break;
      }
      case 2: {
        const w2 = b.w * 0.42;
        renderer.fillRect(x + (b.w - w2) / 2, top - b.h * 0.3, w2, b.h * 0.3, color);
        break;
      }
      default:
        renderer.fillRect(x - 1.5, top - 2, b.w + 3, 2.5, color);
        break;
    }

    // Arched window rows — the Moorish motif read even at this scale.
    const count = b.windows;
    if (count <= 0 || b.w < 12) return;
    const slot = b.w / (count + 1);
    for (let i = 1; i <= count; i++) {
      const wx = x + slot * i - 1.6;
      renderer.fillArch(wx, top + 6, 3.2, Math.min(7, b.h * 0.35), withAlpha(PALETTE.ink, 0.28));
    }
  }

  private drawSun(renderer: Renderer, cameraX: number, time: number): void {
    const x = renderer.width * 0.72 - cameraX * 0.04;
    const y = renderer.height * 0.28;
    const pulse = 1 + Math.sin(time * 0.6) * 0.02;
    renderer.fillCircle(x, y, 52 * pulse, withAlpha(PALETTE.lightWarm, 0.1));
    renderer.fillCircle(x, y, 34 * pulse, withAlpha(PALETTE.light, 0.14));
    renderer.fillCircle(x, y, 17 * pulse, withAlpha(PALETTE.lightSoft, 0.4));
  }
}
