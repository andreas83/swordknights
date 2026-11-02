import { describe, expect, it } from 'vitest';
import { LEVEL_01 } from '../src/game/levels/level01';
import { World } from '../src/game/world';
import { Tile, TILE_SIZE } from '../src/game/tiles';

describe('level 01', () => {
  const world = new World(LEVEL_01);

  it('has exactly one exit and at least one relic', () => {
    const kinds = world.spawns.map((s) => s.kind);
    expect(kinds.filter((k) => k === 'exit')).toHaveLength(1);
    expect(kinds.filter((k) => k === 'relic').length).toBeGreaterThanOrEqual(3);
  });

  it('spawns the player on solid ground', () => {
    const { x, y } = world.playerSpawn;
    expect(world.tileAtWorld(x, y)).toBe(Tile.Solid);
    expect(world.tileAtWorld(x, y - TILE_SIZE)).toBe(Tile.Empty);
  });

  it('places the exit door on solid ground with headroom', () => {
    const exit = world.spawns.find((s) => s.kind === 'exit');
    expect(exit).toBeDefined();
    if (!exit) return;
    expect(world.tileAtWorld(exit.x, exit.y)).toBe(Tile.Solid);
    expect(world.tileAtWorld(exit.x, exit.y - TILE_SIZE * 2)).toBe(Tile.Empty);
  });

  it('places every guard on standable ground', () => {
    for (const patrol of world.spawns.filter((s) => s.kind === 'patrol')) {
      expect(world.tileAtWorld(patrol.x, patrol.y)).toBe(Tile.Solid);
    }
  });

  it('leaves the relics in reachable air, not inside walls', () => {
    for (const relic of world.spawns.filter((s) => s.kind === 'relic')) {
      expect(world.tileAtWorld(relic.x, relic.y - 8)).toBe(Tile.Empty);
    }
  });

  it('is wider than one screen so the camera has something to do', () => {
    expect(world.widthPx).toBeGreaterThan(480);
  });
});
