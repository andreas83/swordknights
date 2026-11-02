/** Tile vocabulary. Levels are authored as ASCII art; this is the legend. */

export const TILE_SIZE = 16;

export enum Tile {
  Empty = 0,
  Solid = 1,
  /** One-way: you land on it from above, you jump up through it. */
  Platform = 2,
  Spikes = 3,
  Water = 4,
  Ladder = 5,
  /** Visually solid background filler — never collides. */
  Backdrop = 6,
}

export const TILE_LEGEND: Readonly<Record<string, Tile>> = {
  ' ': Tile.Empty,
  '.': Tile.Empty,
  '#': Tile.Solid,
  '=': Tile.Platform,
  '^': Tile.Spikes,
  '~': Tile.Water,
  H: Tile.Ladder,
  ':': Tile.Backdrop,
};

/** Characters that mark an entity and leave the tile itself empty. */
export const ENTITY_LEGEND = {
  '@': 'spawn',
  '*': 'relic',
  D: 'exit',
  t: 'torch',
  p: 'patrol',
} as const;

export type EntityMark = (typeof ENTITY_LEGEND)[keyof typeof ENTITY_LEGEND];

export function blocksMovement(tile: Tile): boolean {
  return tile === Tile.Solid;
}

export function isOneWay(tile: Tile): boolean {
  return tile === Tile.Platform;
}

export function isClimbable(tile: Tile): boolean {
  return tile === Tile.Ladder;
}

export function isDeadly(tile: Tile): boolean {
  return tile === Tile.Spikes || tile === Tile.Water;
}
