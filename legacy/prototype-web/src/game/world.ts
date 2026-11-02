/**
 * Tile world: parses an ASCII level into a grid plus entity spawn marks, and
 * answers the collision questions physics and the player state machine ask.
 */

import { ENTITY_LEGEND, Tile, TILE_LEGEND, TILE_SIZE, blocksMovement, isClimbable, isDeadly, isOneWay } from './tiles';
import type { EntityMark } from './tiles';
import type { Rect } from '../core/math';

export interface EntitySpawn {
  kind: EntityMark;
  /** Centre of the tile, in world units. */
  x: number;
  /** Bottom of the tile, in world units. */
  y: number;
}

export interface LevelDefinition {
  id: string;
  name: string;
  /** Equal-length rows is not required — short rows are padded with empty. */
  rows: readonly string[];
  /** Background hue variation, 0..1. Feeds the parallax layers. */
  mood?: number;
}

export class World {
  readonly cols: number;
  readonly rows: number;
  readonly widthPx: number;
  readonly heightPx: number;
  readonly spawns: EntitySpawn[] = [];
  readonly playerSpawn = { x: TILE_SIZE * 2, y: TILE_SIZE * 2 };

  private readonly grid: Uint8Array;

  constructor(readonly definition: LevelDefinition) {
    this.rows = definition.rows.length;
    this.cols = definition.rows.reduce((max, row) => Math.max(max, row.length), 0);
    this.widthPx = this.cols * TILE_SIZE;
    this.heightPx = this.rows * TILE_SIZE;
    this.grid = new Uint8Array(this.cols * this.rows);

    for (let ty = 0; ty < this.rows; ty++) {
      const row = definition.rows[ty];
      for (let tx = 0; tx < row.length; tx++) {
        const char = row[tx];

        const entityKind = (ENTITY_LEGEND as Record<string, EntityMark | undefined>)[char];
        if (entityKind) {
          const spawn: EntitySpawn = {
            kind: entityKind,
            x: tx * TILE_SIZE + TILE_SIZE / 2,
            y: (ty + 1) * TILE_SIZE,
          };
          if (entityKind === 'spawn') {
            this.playerSpawn.x = spawn.x;
            this.playerSpawn.y = spawn.y;
          } else {
            this.spawns.push(spawn);
          }
          continue;
        }

        const tile = TILE_LEGEND[char];
        if (tile !== undefined && tile !== Tile.Empty) {
          this.grid[ty * this.cols + tx] = tile;
        }
      }
    }
  }

  tileAt(tx: number, ty: number): Tile {
    if (tx < 0 || ty < 0 || tx >= this.cols || ty >= this.rows) {
      // Outside the level: walls on the sides, open sky above, pit below.
      if (ty >= this.rows) return Tile.Empty;
      if (tx < 0 || tx >= this.cols) return Tile.Solid;
      return Tile.Empty;
    }
    return this.grid[ty * this.cols + tx] as Tile;
  }

  tileAtWorld(x: number, y: number): Tile {
    return this.tileAt(Math.floor(x / TILE_SIZE), Math.floor(y / TILE_SIZE));
  }

  isSolid(tx: number, ty: number): boolean {
    return blocksMovement(this.tileAt(tx, ty));
  }

  isSolidAtWorld(x: number, y: number): boolean {
    return blocksMovement(this.tileAtWorld(x, y));
  }

  /** True if any solid tile overlaps the rect. */
  overlapsSolid(r: Rect): boolean {
    const x0 = Math.floor(r.x / TILE_SIZE);
    const x1 = Math.floor((r.x + r.w - 1e-6) / TILE_SIZE);
    const y0 = Math.floor(r.y / TILE_SIZE);
    const y1 = Math.floor((r.y + r.h - 1e-6) / TILE_SIZE);
    for (let ty = y0; ty <= y1; ty++) {
      for (let tx = x0; tx <= x1; tx++) {
        if (this.isSolid(tx, ty)) return true;
      }
    }
    return false;
  }

  /**
   * One-way platforms the rect's feet would land on while falling.
   * Returns the top edge of the highest such platform, or null.
   */
  oneWayTopUnder(r: Rect, previousBottom: number): number | null {
    const x0 = Math.floor(r.x / TILE_SIZE);
    const x1 = Math.floor((r.x + r.w - 1e-6) / TILE_SIZE);
    const bottom = r.y + r.h;
    const y0 = Math.floor((bottom - 1e-6) / TILE_SIZE);

    for (let tx = x0; tx <= x1; tx++) {
      const tile = this.tileAt(tx, y0);
      if (!isOneWay(tile)) continue;
      const top = y0 * TILE_SIZE;
      // Only collide when we were fully above it a moment ago.
      if (previousBottom <= top + 1e-3 && bottom >= top) return top;
    }
    return null;
  }

  overlapsDeadly(r: Rect): boolean {
    return this.anyTileIn(r, isDeadly);
  }

  overlapsClimbable(r: Rect): boolean {
    return this.anyTileIn(r, isClimbable);
  }

  private anyTileIn(r: Rect, predicate: (tile: Tile) => boolean): boolean {
    const x0 = Math.floor(r.x / TILE_SIZE);
    const x1 = Math.floor((r.x + r.w - 1e-6) / TILE_SIZE);
    const y0 = Math.floor(r.y / TILE_SIZE);
    const y1 = Math.floor((r.y + r.h - 1e-6) / TILE_SIZE);
    for (let ty = y0; ty <= y1; ty++) {
      for (let tx = x0; tx <= x1; tx++) {
        if (predicate(this.tileAt(tx, ty))) return true;
      }
    }
    return false;
  }
}
