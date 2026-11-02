import { describe, expect, it } from 'vitest';
import { World } from '../src/game/world';
import { TILE_SIZE } from '../src/game/tiles';
import { createBody, isGrounded, moveX, moveY, resolveOverlap } from '../src/game/physics';

/** 6x6 tile sandbox: floor along the bottom, a wall, and a one-way platform. */
function sandbox() {
  return new World({
    id: 'test',
    name: 'test',
    rows: [
      '......',
      '......',
      '..==..',
      '....#.',
      '....#.',
      '######',
    ],
  });
}

describe('moveX', () => {
  it('stops flush against a wall instead of tunnelling', () => {
    const world = sandbox();
    const body = createBody(TILE_SIZE, TILE_SIZE * 3, 8, 12);
    moveX(body, world, 500);
    expect(body.hitWall).toBe(1);
    expect(body.x + body.w).toBeCloseTo(TILE_SIZE * 4, 1);
  });

  it('reports no wall contact when the path is clear', () => {
    const world = sandbox();
    const body = createBody(TILE_SIZE, 0, 8, 12);
    const moved = moveX(body, world, 20);
    expect(body.hitWall).toBe(0);
    expect(moved).toBeCloseTo(20, 4);
  });
});

describe('moveY', () => {
  it('lands on the floor from any fall speed', () => {
    const world = sandbox();
    const body = createBody(TILE_SIZE, 0, 8, 12);
    body.vy = 4000;
    moveY(body, world, 4000);
    expect(body.onGround).toBe(true);
    expect(body.y + body.h).toBeCloseTo(TILE_SIZE * 5, 1);
  });

  it('stops at a ceiling and reports the hit', () => {
    const world = new World({ id: 't', name: 't', rows: ['####', '....', '....', '####'] });
    const body = createBody(TILE_SIZE, TILE_SIZE * 2, 8, 12);
    moveY(body, world, -200);
    expect(body.hitCeiling).toBe(true);
    expect(body.y).toBeCloseTo(TILE_SIZE, 1);
  });

  it('lands on a one-way platform when falling onto it', () => {
    const world = sandbox();
    const body = createBody(TILE_SIZE * 2.2, TILE_SIZE * 2 - 14, 8, 12);
    body.vy = 120;
    moveY(body, world, 40);
    expect(body.onGround).toBe(true);
    expect(body.y + body.h).toBeCloseTo(TILE_SIZE * 2, 1);
  });

  it('passes up through a one-way platform', () => {
    const world = sandbox();
    const body = createBody(TILE_SIZE * 2.2, TILE_SIZE * 3, 8, 12);
    moveY(body, world, -TILE_SIZE * 2);
    expect(body.hitCeiling).toBe(false);
    expect(body.y).toBeCloseTo(TILE_SIZE, 1);
  });

  it('drops through a one-way platform when dropThrough is set', () => {
    const world = sandbox();
    const body = createBody(TILE_SIZE * 2.2, TILE_SIZE * 2 - 14, 8, 12);
    body.dropThrough = true;
    moveY(body, world, 30);
    expect(body.onGround).toBe(false);
  });
});

describe('grounding', () => {
  it('detects ground one pixel below the feet', () => {
    const world = sandbox();
    const body = createBody(TILE_SIZE, TILE_SIZE * 5 - 12, 8, 12);
    expect(isGrounded(body, world)).toBe(true);
    body.y -= 4;
    expect(isGrounded(body, world)).toBe(false);
  });
});

describe('resolveOverlap', () => {
  it('pushes an embedded body out of a solid tile', () => {
    const world = sandbox();
    const body = createBody(TILE_SIZE * 4, TILE_SIZE * 3, 8, 12);
    expect(world.overlapsSolid(body)).toBe(true);
    expect(resolveOverlap(body, world)).toBe(true);
    expect(world.overlapsSolid(body)).toBe(false);
  });
});
