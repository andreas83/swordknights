/**
 * Every number that defines how the character feels, in one place.
 * Units are virtual pixels and seconds (1 tile = 16 px).
 *
 * The defaults aim at the Prince of Persia cadence: deliberate on the ground,
 * committed in the air, and forgiving at the edges (coyote time, jump buffer,
 * ledge grabs) so touch input does not punish the player for a late tap.
 */
export const TUNING = {
  // Body
  bodyWidth: 9,
  bodyHeight: 22,
  crouchHeight: 13,

  // Horizontal motion
  runSpeed: 88,
  walkSpeed: 40,
  groundAccel: 520,
  groundFriction: 760,
  airAccel: 340,
  airFriction: 150,
  /** Time spent in the turn-around pose before running the other way. */
  turnTime: 0.09,

  // Vertical motion
  gravity: 900,
  maxFallSpeed: 330,
  jumpSpeed: 252,
  /** Velocity is multiplied by this when jump is released early. */
  jumpCutMultiplier: 0.42,
  /** Extra float at the apex makes mid-air control readable. */
  apexGravityScale: 0.72,
  apexThreshold: 36,

  // Forgiveness windows
  coyoteTime: 0.1,
  jumpBufferMs: 140,

  // Ledges
  grabProbeY: 6,
  /** How far the hands reach past the body. */
  grabReach: 3,
  hangHoldTime: 0.08,
  climbUpTime: 0.34,
  /** Falling faster than this is too fast to catch a ledge. */
  maxGrabFallSpeed: 260,

  // Ladders
  ladderSpeed: 48,

  // Combat / damage
  maxHealth: 3,
  invulnerableTime: 1.1,
  knockbackX: 90,
  knockbackY: 150,
  attackTime: 0.28,
  attackReach: 14,
  attackHeight: 14,

  // Landing
  /** Below this impact speed the landing is silent; above it the prince crouches. */
  softLandSpeed: 190,
  hardLandSpeed: 300,
  landRecoverTime: 0.18,
} as const;

export type Tuning = typeof TUNING;
