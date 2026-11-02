/**
 * A hooded guard that walks its ledge and turns at walls and drops.
 * Minimal on purpose: it exists so the damage, hit-reaction and combat
 * plumbing is exercised end to end by something in the level.
 */

import { PALETTE } from '../../render/palette';
import { Tile, TILE_SIZE } from '../tiles';
import { createBody, moveX, moveY } from '../physics';
import type { Body } from '../physics';
import type { Renderer } from '../../render/renderer';
import type { Rect } from '../../core/math';
import type { Entity, EntityContext } from './entity';

const SPEED = 26;
const GRAVITY = 900;
const MAX_FALL = 320;
const STAGGER_TIME = 0.4;

export class Patrol implements Entity {
  readonly kind = 'patrol';
  dead = false;

  readonly body: Body;
  facing: 1 | -1 = -1;
  health = 2;

  private stagger = 0;
  private walkPhase = 0;

  constructor(x: number, y: number) {
    this.body = createBody(x - 5, y - 20, 10, 20);
  }

  get bounds(): Rect {
    return this.body;
  }

  update(ctx: EntityContext): void {
    const { world, dt } = ctx;

    this.body.vy = Math.min(this.body.vy + GRAVITY * dt, MAX_FALL);

    if (this.stagger > 0) {
      this.stagger -= dt;
      this.body.vx *= 0.88;
    } else {
      this.body.vx = this.facing * SPEED;
      this.walkPhase += dt * 6;

      // Turn at a wall, or at the edge of the ledge.
      const aheadX = this.facing > 0 ? this.body.x + this.body.w + 2 : this.body.x - 2;
      const footY = this.body.y + this.body.h + 2;
      const wallAhead = world.isSolidAtWorld(aheadX, this.body.y + this.body.h - 4);
      const groundAhead = world.isSolidAtWorld(aheadX, footY) || world.tileAtWorld(aheadX, footY) === Tile.Platform;
      if (wallAhead || (!groundAhead && this.body.onGround)) {
        this.facing = (-this.facing) as 1 | -1;
        this.body.vx = 0;
      }
    }

    moveX(this.body, world, this.body.vx * dt);
    if (this.body.hitWall !== 0 && this.stagger <= 0) this.facing = (-this.body.hitWall) as 1 | -1;
    moveY(this.body, world, this.body.vy * dt);

    if (this.body.y > world.heightPx + TILE_SIZE * 4) this.dead = true;
  }

  /** Returns true when this hit killed it. */
  hit(fromX: number): boolean {
    this.health -= 1;
    this.stagger = STAGGER_TIME;
    this.body.vx = Math.sign(this.body.x + this.body.w / 2 - fromX || 1) * 120;
    this.body.vy = -110;
    if (this.health <= 0) {
      this.dead = true;
      return true;
    }
    return false;
  }

  draw(renderer: Renderer, _time: number): void {
    const { x, y, w, h } = this.body;
    const cx = x + w / 2;
    const sway = this.stagger > 0 ? 0 : Math.sin(this.walkPhase) * 0.8;
    const hem = y + h;

    // Cloak silhouette — the same cone shape as the figures in the concept art.
    renderer.fillPoly(
      [
        [cx + sway, y + 2],
        [cx + w * 0.78 + sway * 0.4, hem],
        [cx - w * 0.78 + sway * 0.4, hem],
      ],
      PALETTE.clothDark,
    );
    renderer.fillPoly(
      [
        [cx + sway, y + 2],
        [cx + w * 0.78 * this.facing + sway * 0.4, hem],
        [cx + sway * 0.4, hem],
      ],
      PALETTE.cloth,
    );
    // Hood.
    renderer.fillCircle(cx + sway, y + 4, 3.4, PALETTE.ink);
    renderer.fillRect(cx + sway - 0.6 + this.facing * 1.4, y + 3.2, 1.4, 1.2, PALETTE.light);
  }
}
