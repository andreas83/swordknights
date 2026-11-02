import { describe, expect, it } from 'vitest';
import { World } from '../src/game/world';
import { Tile, TILE_SIZE } from '../src/game/tiles';

describe('World parsing', () => {
  const world = new World({
    id: 'parse',
    name: 'parse',
    rows: [
      '  *  D',
      '@  ^ ~',
      '######',
    ],
  });

  it('measures the grid from the longest row', () => {
    expect(world.cols).toBe(6);
    expect(world.rows).toBe(3);
    expect(world.widthPx).toBe(6 * TILE_SIZE);
  });

  it('places the player spawn at the bottom centre of its tile', () => {
    expect(world.playerSpawn.x).toBe(TILE_SIZE / 2);
    expect(world.playerSpawn.y).toBe(TILE_SIZE * 2);
  });

  it('keeps entity tiles walkable', () => {
    expect(world.tileAt(0, 1)).toBe(Tile.Empty);
    expect(world.tileAt(2, 0)).toBe(Tile.Empty);
  });

  it('collects non-player entity marks', () => {
    const kinds = world.spawns.map((s) => s.kind).sort();
    expect(kinds).toEqual(['exit', 'relic']);
  });

  it('reads hazard tiles', () => {
    expect(world.tileAt(3, 1)).toBe(Tile.Spikes);
    expect(world.tileAt(5, 1)).toBe(Tile.Water);
    expect(world.overlapsDeadly({ x: TILE_SIZE * 3, y: TILE_SIZE, w: 4, h: 4 })).toBe(true);
  });

  it('treats the area outside the left and right edges as solid', () => {
    expect(world.isSolid(-1, 1)).toBe(true);
    expect(world.isSolid(world.cols, 1)).toBe(true);
    expect(world.isSolid(1, -1)).toBe(false);
  });
});
