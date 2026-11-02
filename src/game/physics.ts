/**
 * Axis-separated swept AABB movement against the tile grid.
 *
 * Movement is split into sub-steps no larger than a tile so a fast fall can
 * never tunnel through a floor. Horizontal and vertical passes are separate,
 * which is what gives platformers their predictable "slide along the wall"
 * feel, and it keeps the collision response trivial to reason about.
 */

import { TILE_SIZE } from './tiles';
import type { World } from './world';
import type { Rect } from '../core/math';

export interface Body extends Rect {
  vx: number;
  vy: number;
  onGround: boolean;
  /** Set when the last horizontal move was stopped by a wall. -1 left, 1 right, 0 none. */
  hitWall: number;
  /** Set when the last vertical move was stopped by a ceiling. */
  hitCeiling: boolean;
  /** Whether this body is allowed to stand on one-way platforms. */
  usesOneWay: boolean;
  /** When true, one-way platforms are ignored for this step (drop-through). */
  dropThrough: boolean;
}

export function createBody(x: number, y: number, w: number, h: number): Body {
  return {
    x,
    y,
    w,
    h,
    vx: 0,
    vy: 0,
    onGround: false,
    hitWall: 0,
    hitCeiling: false,
    usesOneWay: true,
    dropThrough: false,
  };
}

const EPSILON = 1e-4;

/** Moves the body horizontally, stopping at solid tiles. Returns distance actually moved. */
export function moveX(body: Body, world: World, dx: number): number {
  body.hitWall = 0;
  if (dx === 0) return 0;

  const direction = Math.sign(dx);
  let remaining = Math.abs(dx);
  let moved = 0;

  while (remaining > EPSILON) {
    const stepSize = Math.min(remaining, TILE_SIZE - EPSILON);
    const candidate: Rect = { x: body.x + direction * stepSize, y: body.y, w: body.w, h: body.h };

    if (world.overlapsSolid(candidate)) {
      // Binary-narrow onto the contact point so we end up flush with the wall.
      let lo = 0;
      let hi = stepSize;
      for (let i = 0; i < 8; i++) {
        const mid = (lo + hi) / 2;
        const probe: Rect = { x: body.x + direction * mid, y: body.y, w: body.w, h: body.h };
        if (world.overlapsSolid(probe)) hi = mid;
        else lo = mid;
      }
      body.x += direction * lo;
      moved += direction * lo;
      body.vx = 0;
      body.hitWall = direction;
      return moved;
    }

    body.x = candidate.x;
    moved += direction * stepSize;
    remaining -= stepSize;
  }

  return moved;
}

/** Moves the body vertically, resolving floors, ceilings and one-way platforms. */
export function moveY(body: Body, world: World, dy: number): number {
  body.hitCeiling = false;
  const wasOnGround = body.onGround;
  body.onGround = false;

  if (dy === 0) {
    // Still need a ground probe so standing still keeps `onGround` true.
    body.onGround = isGrounded(body, world);
    return 0;
  }

  const direction = Math.sign(dy);
  let remaining = Math.abs(dy);
  let moved = 0;

  while (remaining > EPSILON) {
    const stepSize = Math.min(remaining, TILE_SIZE - EPSILON);
    const previousBottom = body.y + body.h;
    const candidate: Rect = { x: body.x, y: body.y + direction * stepSize, w: body.w, h: body.h };

    let blockedAt: number | null = null;

    if (world.overlapsSolid(candidate)) {
      let lo = 0;
      let hi = stepSize;
      for (let i = 0; i < 8; i++) {
        const mid = (lo + hi) / 2;
        const probe: Rect = { x: body.x, y: body.y + direction * mid, w: body.w, h: body.h };
        if (world.overlapsSolid(probe)) hi = mid;
        else lo = mid;
      }
      blockedAt = lo;
    } else if (direction > 0 && body.usesOneWay && !body.dropThrough) {
      const platformTop = world.oneWayTopUnder(candidate, previousBottom);
      if (platformTop !== null) blockedAt = platformTop - previousBottom;
    }

    if (blockedAt !== null) {
      const clamped = Math.max(0, blockedAt);
      body.y += direction * clamped;
      moved += direction * clamped;
      body.vy = 0;
      if (direction > 0) body.onGround = true;
      else body.hitCeiling = true;
      return moved;
    }

    body.y = candidate.y;
    moved += direction * stepSize;
    remaining -= stepSize;
  }

  if (!body.onGround && direction >= 0) body.onGround = isGrounded(body, world);
  if (wasOnGround && direction < 0) body.onGround = false;
  return moved;
}

/** Probe one pixel below the body for solid ground or a one-way top. */
export function isGrounded(body: Body, world: World): boolean {
  const probe: Rect = { x: body.x, y: body.y + 1, w: body.w, h: body.h };
  if (world.overlapsSolid(probe)) return true;
  if (!body.usesOneWay || body.dropThrough) return false;
  return world.oneWayTopUnder(probe, body.y + body.h) !== null;
}

/**
 * Nudges a body out of a solid tile it is already embedded in. Used after
 * teleports, spawns and level transitions so the player never starts stuck.
 */
export function resolveOverlap(body: Body, world: World, maxPush = TILE_SIZE * 2): boolean {
  if (!world.overlapsSolid(body)) return true;
  for (let push = 1; push <= maxPush; push++) {
    const candidates: Array<[number, number]> = [
      [0, -push],
      [0, push],
      [-push, 0],
      [push, 0],
    ];
    for (const [ox, oy] of candidates) {
      const probe: Rect = { x: body.x + ox, y: body.y + oy, w: body.w, h: body.h };
      if (!world.overlapsSolid(probe)) {
        body.x = probe.x;
        body.y = probe.y;
        return true;
      }
    }
  }
  return false;
}
