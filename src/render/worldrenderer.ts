/**
 * Paints the tile grid in the concept art's duotone language:
 *   - the top face of every block is lit gold,
 *   - the front face falls into crimson shade,
 *   - a warm bevel marks the edge between them,
 *   - everything casts a hard offset shadow to the lower-left.
 *
 * Only the tiles inside the camera view are visited, so level size costs
 * nothing at draw time.
 */

import { PALETTE, SURFACE, withAlpha } from './palette';
import { Tile, TILE_SIZE } from '../game/tiles';
import type { Renderer } from './renderer';
import type { World } from '../game/world';

const CAP_HEIGHT = 4;
const SHADOW_OFFSET = 3;

export class WorldRenderer {
  constructor(private readonly world: World) {}

  draw(renderer: Renderer, cameraX: number, cameraY: number, time: number): void {
    const x0 = Math.max(0, Math.floor(cameraX / TILE_SIZE) - 1);
    const y0 = Math.max(0, Math.floor(cameraY / TILE_SIZE) - 1);
    const x1 = Math.min(this.world.cols - 1, Math.ceil((cameraX + renderer.width) / TILE_SIZE));
    const y1 = Math.min(this.world.rows - 1, Math.ceil((cameraY + renderer.height) / TILE_SIZE));

    // Pass 1: cast shadows first so no block is ever shadowed by its neighbour.
    for (let ty = y0; ty <= y1; ty++) {
      for (let tx = x0; tx <= x1; tx++) {
        const tile = this.world.tileAt(tx, ty);
        if (tile !== Tile.Solid && tile !== Tile.Platform) continue;
        if (this.world.tileAt(tx - 1, ty) === Tile.Solid && this.world.tileAt(tx, ty - 1) === Tile.Solid) continue;
        const h = tile === Tile.Platform ? CAP_HEIGHT : TILE_SIZE;
        renderer.fillRect(tx * TILE_SIZE - SHADOW_OFFSET, ty * TILE_SIZE + SHADOW_OFFSET, TILE_SIZE, h, withAlpha(PALETTE.ink, 0.22));
      }
    }

    // Pass 2: the blocks themselves.
    for (let ty = y0; ty <= y1; ty++) {
      for (let tx = x0; tx <= x1; tx++) {
        this.drawTile(renderer, tx, ty, this.world.tileAt(tx, ty), time);
      }
    }
  }

  private drawTile(renderer: Renderer, tx: number, ty: number, tile: Tile, time: number): void {
    const x = tx * TILE_SIZE;
    const y = ty * TILE_SIZE;

    switch (tile) {
      case Tile.Solid:
        this.drawSolid(renderer, x, y, tx, ty);
        break;
      case Tile.Platform:
        renderer.fillRect(x, y, TILE_SIZE, CAP_HEIGHT, SURFACE.lit);
        renderer.fillRect(x, y + CAP_HEIGHT, TILE_SIZE, 1.5, SURFACE.bevel);
        break;
      case Tile.Spikes:
        this.drawSpikes(renderer, x, y);
        break;
      case Tile.Water:
        this.drawWater(renderer, x, y, time);
        break;
      case Tile.Ladder:
        this.drawLadder(renderer, x, y);
        break;
      case Tile.Backdrop:
        renderer.fillRect(x, y, TILE_SIZE, TILE_SIZE, SURFACE.shadeDeep);
        renderer.fillArch(x + 3, y + 3, TILE_SIZE - 6, TILE_SIZE - 3, withAlpha(PALETTE.ink, 0.35));
        break;
      default:
        break;
    }
  }

  private drawSolid(renderer: Renderer, x: number, y: number, tx: number, ty: number): void {
    const openAbove = this.world.tileAt(tx, ty - 1) !== Tile.Solid;

    renderer.fillRect(x, y, TILE_SIZE, TILE_SIZE, SURFACE.shade);

    if (openAbove) {
      renderer.fillRect(x, y, TILE_SIZE, CAP_HEIGHT, SURFACE.lit);
      renderer.fillRect(x, y + CAP_HEIGHT, TILE_SIZE, 1.5, SURFACE.bevel);
    } else {
      renderer.fillRect(x, y, TILE_SIZE, TILE_SIZE, SURFACE.shadeDeep);
    }

    // Masonry: a single joint line, offset per row, reads as stone without noise.
    const jointY = y + TILE_SIZE - 5;
    renderer.fillRect(x, jointY, TILE_SIZE, 0.75, withAlpha(PALETTE.ink, 0.22));
    const jointX = x + (ty % 2 === 0 ? TILE_SIZE * 0.5 : TILE_SIZE * 0.25);
    renderer.fillRect(jointX, jointY, 0.75, TILE_SIZE - (jointY - y), withAlpha(PALETTE.ink, 0.22));

    // Lit left edge where the block faces the sun.
    if (this.world.tileAt(tx - 1, ty) !== Tile.Solid) {
      renderer.fillRect(x, y + (openAbove ? CAP_HEIGHT : 0), 1, TILE_SIZE - (openAbove ? CAP_HEIGHT : 0), withAlpha(PALETTE.lightWarm, 0.32));
    }
  }

  private drawSpikes(renderer: Renderer, x: number, y: number): void {
    const base = y + TILE_SIZE;
    renderer.fillRect(x, base - 3, TILE_SIZE, 3, SURFACE.shadeDeep);
    const count = 4;
    const step = TILE_SIZE / count;
    for (let i = 0; i < count; i++) {
      const sx = x + i * step;
      renderer.fillPoly(
        [
          [sx + step * 0.5, base - TILE_SIZE * 0.72],
          [sx + step, base - 2],
          [sx, base - 2],
        ],
        PALETTE.steel,
      );
      renderer.fillPoly(
        [
          [sx + step * 0.5, base - TILE_SIZE * 0.72],
          [sx + step * 0.5, base - 2],
          [sx, base - 2],
        ],
        PALETTE.steelDark,
      );
    }
  }

  private drawWater(renderer: Renderer, x: number, y: number, time: number): void {
    const wave = Math.sin(time * 1.8 + x * 0.18) * 1.1;
    renderer.fillRect(x, y + 2, TILE_SIZE, TILE_SIZE - 2, withAlpha(PALETTE.waterDeep, 0.85));
    renderer.fillRect(x, y + 2 + wave, TILE_SIZE, 2.2, PALETTE.water);
    renderer.fillRect(x + 3, y + 6 + wave * 0.6, TILE_SIZE * 0.45, 1, withAlpha(PALETTE.paper, 0.3));
  }

  private drawLadder(renderer: Renderer, x: number, y: number): void {
    renderer.fillRect(x + 3, y, 1.6, TILE_SIZE, PALETTE.shadowDeep);
    renderer.fillRect(x + TILE_SIZE - 4.6, y, 1.6, TILE_SIZE, PALETTE.shadowDeep);
    for (let i = 0; i < 3; i++) {
      renderer.fillRect(x + 3, y + 2 + i * 5, TILE_SIZE - 6, 1.4, PALETTE.lightWarm);
    }
  }
}
