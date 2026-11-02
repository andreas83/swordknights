/**
 * Duotone palette lifted from the concept art: everything in the world is
 * lit gold or dropped into crimson shadow, with a tiny set of accents
 * (water, foliage, cloth) allowed to break the two-tone rule.
 *
 * Keep the ramp small on purpose — the look comes from flat planes of colour
 * and hard shadow edges, not from shading gradients.
 */

export const PALETTE = {
  /** Deepest value — sky top, letterbox bars, silhouettes. */
  ink: '#2B0A14',
  shadowDeep: '#7A1230',
  shadow: '#B32142',
  shadowWarm: '#D8452C',
  mid: '#E8702A',
  lightWarm: '#F2A829',
  light: '#F7CE2E',
  lightSoft: '#FFE873',
  paper: '#FFF4C2',

  /** Accents. */
  water: '#46C7B0',
  waterDeep: '#1F8F86',
  foliage: '#5FBF7A',
  cloth: '#C6354F',
  clothDark: '#8E1F38',
  steel: '#8C8FA3',
  steelDark: '#5A5D70',
} as const;

export type PaletteKey = keyof typeof PALETTE;

/**
 * Surfaces are described by how they face the light, not by a literal colour.
 * Swapping this table re-lights the entire game.
 */
export const SURFACE = {
  /** Faces the sun. */
  lit: PALETTE.light,
  litSoft: PALETTE.lightSoft,
  /** Faces away — the crimson half of the duotone. */
  shade: PALETTE.shadow,
  shadeDeep: PALETTE.shadowDeep,
  /** The warm bevel where lit meets shade. */
  bevel: PALETTE.lightWarm,
  edge: PALETTE.shadowWarm,
  /** Far background layers. */
  farA: PALETTE.shadowWarm,
  farB: PALETTE.mid,
} as const;

/** Sky gradient stops, top to bottom. */
export const SKY_STOPS: ReadonlyArray<readonly [number, string]> = [
  [0, PALETTE.shadowDeep],
  [0.45, PALETTE.shadow],
  [0.78, PALETTE.mid],
  [1, PALETTE.lightWarm],
];

export function withAlpha(hex: string, alpha: number): string {
  const value = hex.replace('#', '');
  const r = parseInt(value.slice(0, 2), 16);
  const g = parseInt(value.slice(2, 4), 16);
  const b = parseInt(value.slice(4, 6), 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}
