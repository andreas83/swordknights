/**
 * The prince: a deterministic state machine on top of an AABB body.
 *
 * All transitions live in `update`'s switch, so the whole moveset is readable
 * in one screen. Nothing here touches the renderer — the state, facing and a
 * normalised animation phase are the only things drawing code reads.
 */

import { approach, clamp, sign } from '../core/math';
import type { InputReader } from '../core/input';
import { TILE_SIZE } from './tiles';
import { TUNING } from './tuning';
import { createBody, isGrounded, moveX, moveY, resolveOverlap } from './physics';
import type { Body } from './physics';
import type { World } from './world';
import type { Rect } from '../core/math';

export type PlayerState =
  | 'idle'
  | 'walk'
  | 'run'
  | 'turn'
  | 'crouch'
  | 'jump'
  | 'fall'
  | 'land'
  | 'hang'
  | 'climbUp'
  | 'ladder'
  | 'attack'
  | 'hurt'
  | 'dead';

export interface PlayerEvents {
  onLand?(impactSpeed: number): void;
  onJump?(): void;
  onGrab?(): void;
  onAttack?(): void;
  onHurt?(remainingHealth: number): void;
  onDeath?(): void;
}

export class Player {
  readonly body: Body;

  state: PlayerState = 'idle';
  facing: 1 | -1 = 1;
  health: number = TUNING.maxHealth;
  /** Seconds spent in the current state — drives animation and timed exits. */
  stateTime = 0;
  invulnerable = 0;

  private coyote = 0;
  private turnTimer = 0;
  private landTimer = 0;
  private attackTimer = 0;
  private hurtTimer = 0;
  private climbFrom = { x: 0, y: 0 };
  private climbTo = { x: 0, y: 0 };
  private climbProgress = 0;
  private lastFallSpeed = 0;

  constructor(
    private readonly world: World,
    private readonly events: PlayerEvents = {},
  ) {
    this.body = createBody(0, 0, TUNING.bodyWidth, TUNING.bodyHeight);
    this.respawn();
  }

  get x(): number {
    return this.body.x + this.body.w / 2;
  }

  get y(): number {
    return this.body.y + this.body.h;
  }

  get alive(): boolean {
    return this.state !== 'dead';
  }

  get isHanging(): boolean {
    return this.state === 'hang' || this.state === 'climbUp';
  }

  /** Sword hitbox for the current frame, or null when not swinging. */
  get attackBox(): Rect | null {
    if (this.state !== 'attack') return null;
    // The blade only connects during the middle of the swing.
    const phase = this.attackTimer / TUNING.attackTime;
    if (phase < 0.25 || phase > 0.8) return null;
    const width = TUNING.attackReach;
    return {
      x: this.facing > 0 ? this.body.x + this.body.w : this.body.x - width,
      y: this.body.y + 3,
      w: width,
      h: TUNING.attackHeight,
    };
  }

  respawn(at = this.world.playerSpawn): void {
    this.body.x = at.x - this.body.w / 2;
    this.body.y = at.y - this.body.h;
    this.body.w = TUNING.bodyWidth;
    this.body.h = TUNING.bodyHeight;
    this.body.vx = 0;
    this.body.vy = 0;
    this.body.onGround = true;
    this.body.dropThrough = false;
    resolveOverlap(this.body, this.world);
    this.state = 'idle';
    this.stateTime = 0;
    this.health = TUNING.maxHealth;
    this.invulnerable = 0;
    this.coyote = 0;
  }

  update(dt: number, input: InputReader): void {
    this.stateTime += dt;
    if (this.invulnerable > 0) this.invulnerable = Math.max(0, this.invulnerable - dt);

    switch (this.state) {
      case 'dead':
        this.applyGravity(dt);
        this.integrate(dt);
        return;
      case 'hang':
        this.updateHang(dt, input);
        return;
      case 'climbUp':
        this.updateClimbUp(dt);
        return;
      case 'ladder':
        this.updateLadder(dt, input);
        return;
      case 'hurt':
        this.updateHurt(dt);
        return;
      default:
        break;
    }

    this.updateGrounded(dt, input);
  }

  // --- main locomotion -----------------------------------------------------

  private updateGrounded(dt: number, input: InputReader): void {
    const wantX = input.axisX;
    const walking = input.down('walk');
    const onGround = this.body.onGround;

    if (onGround) this.coyote = TUNING.coyoteTime;
    else this.coyote = Math.max(0, this.coyote - dt);

    if (this.state === 'attack') {
      this.attackTimer += dt;
      // Attacking roots you in place — commitment is the point.
      this.body.vx = approach(this.body.vx, 0, TUNING.groundFriction * dt);
      if (this.attackTimer >= TUNING.attackTime) this.enter(onGround ? 'idle' : 'fall');
    } else if (this.state === 'land') {
      this.landTimer -= dt;
      this.body.vx = approach(this.body.vx, 0, TUNING.groundFriction * dt);
      if (this.landTimer <= 0) this.enter('idle');
    } else if (this.state === 'turn') {
      this.turnTimer -= dt;
      this.body.vx = approach(this.body.vx, 0, TUNING.groundFriction * 1.4 * dt);
      if (this.turnTimer <= 0) {
        this.facing = (-this.facing) as 1 | -1;
        this.enter(wantX === 0 ? 'idle' : walking ? 'walk' : 'run');
      }
    } else {
      this.handleFreeMovement(dt, input, wantX, walking, onGround);
    }

    this.applyGravity(dt);

    // Jump: coyote time + buffered press means a late or early tap both work.
    const canJump = this.coyote > 0 && this.state !== 'attack' && this.state !== 'crouch';
    if (canJump && input.consumePress('jump', TUNING.jumpBufferMs)) {
      this.body.vy = -TUNING.jumpSpeed;
      this.body.onGround = false;
      this.coyote = 0;
      this.enter('jump');
      this.events.onJump?.();
    }

    // Variable jump height.
    if (this.state === 'jump' && this.body.vy < 0 && !input.down('jump')) {
      this.body.vy *= TUNING.jumpCutMultiplier;
    }

    // Drop through one-way platforms with down + jump.
    this.body.dropThrough = this.body.onGround && input.down('down') && input.down('jump');

    this.integrate(dt);
    this.resolveAirState(input);
  }

  private handleFreeMovement(dt: number, input: InputReader, wantX: number, walking: boolean, onGround: boolean): void {
    if (onGround && input.pressed('action')) {
      this.attackTimer = 0;
      this.enter('attack');
      this.events.onAttack?.();
      return;
    }

    // Ladders take priority when the player asks to go up or down on one.
    if (onGround || this.state === 'fall' || this.state === 'jump') {
      const wantsLadder = input.down('up') || input.down('down');
      if (wantsLadder && this.world.overlapsClimbable(this.body)) {
        this.enter('ladder');
        this.body.vx = 0;
        this.body.vy = 0;
        return;
      }
    }

    const crouching = onGround && input.down('down') && wantX === 0;
    this.setCrouched(crouching);
    if (crouching) {
      this.body.vx = approach(this.body.vx, 0, TUNING.groundFriction * dt);
      this.enter('crouch');
      return;
    }

    // Turn-around has a wind-up on the ground, mirroring the original's weight.
    if (onGround && wantX !== 0 && wantX !== this.facing && Math.abs(this.body.vx) > TUNING.walkSpeed) {
      this.turnTimer = TUNING.turnTime;
      this.enter('turn');
      return;
    }

    const topSpeed = walking ? TUNING.walkSpeed : TUNING.runSpeed;
    const accel = onGround ? TUNING.groundAccel : TUNING.airAccel;
    const friction = onGround ? TUNING.groundFriction : TUNING.airFriction;

    if (wantX !== 0) {
      this.facing = wantX as 1 | -1;
      this.body.vx = approach(this.body.vx, wantX * topSpeed, accel * dt);
    } else {
      this.body.vx = approach(this.body.vx, 0, friction * dt);
    }

    if (onGround) {
      const speed = Math.abs(this.body.vx);
      if (speed < 1) this.enter('idle');
      else if (speed <= TUNING.walkSpeed + 1) this.enter('walk');
      else this.enter('run');
    }
  }

  private applyGravity(dt: number): void {
    const nearApex = Math.abs(this.body.vy) < TUNING.apexThreshold;
    const scale = nearApex && !this.body.onGround ? TUNING.apexGravityScale : 1;
    this.body.vy = Math.min(this.body.vy + TUNING.gravity * scale * dt, TUNING.maxFallSpeed);
  }

  private integrate(dt: number): void {
    moveX(this.body, this.world, this.body.vx * dt);
    const fallSpeedBefore = this.body.vy;
    const wasAirborne = !this.body.onGround;
    moveY(this.body, this.world, this.body.vy * dt);

    if (wasAirborne && this.body.onGround) {
      this.lastFallSpeed = fallSpeedBefore;
      this.onTouchedGround(fallSpeedBefore);
    }
    if (!this.body.onGround) this.body.onGround = isGrounded(this.body, this.world);
  }

  private onTouchedGround(impact: number): void {
    if (this.state === 'dead' || this.state === 'hurt') return;
    this.events.onLand?.(impact);
    if (impact >= TUNING.hardLandSpeed) {
      this.landTimer = TUNING.landRecoverTime * 1.6;
      this.enter('land');
    } else if (impact >= TUNING.softLandSpeed) {
      this.landTimer = TUNING.landRecoverTime;
      this.enter('land');
    }
  }

  private resolveAirState(input: InputReader): void {
    if (this.body.onGround) return;
    if (this.state === 'attack' || this.state === 'hurt') return;

    if (this.body.vy > 0) {
      if (this.state !== 'fall') this.enter('fall');
      this.tryGrabLedge(input);
    } else if (this.state !== 'jump') {
      this.enter('jump');
    }
  }

  // --- ledges --------------------------------------------------------------

  /**
   * Looks for a corner at hand height in the facing direction. The player must
   * be falling (not too fast) and pushing towards the wall, which keeps grabs
   * intentional rather than sticky.
   */
  private tryGrabLedge(input: InputReader): void {
    if (this.body.vy > TUNING.maxGrabFallSpeed) return;
    if (input.down('down')) return;

    const direction = input.axisX !== 0 ? (input.axisX as 1 | -1) : this.facing;
    const handX = direction > 0 ? this.body.x + this.body.w + TUNING.grabReach : this.body.x - TUNING.grabReach;
    const tx = Math.floor(handX / TILE_SIZE);
    const ty = Math.floor((this.body.y + TUNING.grabProbeY) / TILE_SIZE);

    // A grabbable ledge is a solid tile with nothing solid on top of it.
    if (!this.world.isSolid(tx, ty)) return;
    if (this.world.isSolid(tx, ty - 1)) return;

    const ledgeTop = ty * TILE_SIZE;
    const hangY = ledgeTop - TUNING.grabProbeY;
    const hangX = direction > 0 ? tx * TILE_SIZE - this.body.w : (tx + 1) * TILE_SIZE;

    // Refuse the grab if the hanging pose would clip into geometry.
    if (this.world.overlapsSolid({ x: hangX, y: hangY, w: this.body.w, h: this.body.h })) return;

    this.body.x = hangX;
    this.body.y = hangY;
    this.body.vx = 0;
    this.body.vy = 0;
    this.facing = direction;
    this.enter('hang');
    this.events.onGrab?.();
  }

  private updateHang(_dt: number, input: InputReader): void {
    this.body.vx = 0;
    this.body.vy = 0;

    if (this.stateTime < TUNING.hangHoldTime) return;

    if (input.down('down')) {
      this.enter('fall');
      this.body.vy = 20;
      return;
    }

    const climbRequested = input.down('up') || input.consumePress('jump', TUNING.jumpBufferMs);
    if (!climbRequested) return;

    const ledgeTop = this.body.y + TUNING.grabProbeY;
    const standX = this.facing > 0 ? this.body.x + TILE_SIZE * 0.5 : this.body.x - TILE_SIZE * 0.5;
    const target = { x: standX, y: ledgeTop - this.body.h };

    if (this.world.overlapsSolid({ x: target.x, y: target.y, w: this.body.w, h: this.body.h })) {
      // No room to stand up — let go instead of clipping into the wall.
      this.enter('fall');
      return;
    }

    this.climbFrom = { x: this.body.x, y: this.body.y };
    this.climbTo = target;
    this.climbProgress = 0;
    this.enter('climbUp');
  }

  private updateClimbUp(dt: number): void {
    this.climbProgress = clamp(this.climbProgress + dt / TUNING.climbUpTime, 0, 1);
    const t = this.climbProgress;
    // Up first, then across — the classic mantle arc.
    const vertical = Math.min(1, t * 1.6);
    const horizontal = Math.max(0, (t - 0.45) / 0.55);
    this.body.y = this.climbFrom.y + (this.climbTo.y - this.climbFrom.y) * vertical;
    this.body.x = this.climbFrom.x + (this.climbTo.x - this.climbFrom.x) * horizontal;

    if (t >= 1) {
      this.body.vx = 0;
      this.body.vy = 0;
      this.body.onGround = true;
      this.enter('idle');
    }
  }

  // --- ladders -------------------------------------------------------------

  private updateLadder(dt: number, input: InputReader): void {
    if (!this.world.overlapsClimbable(this.body)) {
      this.enter('fall');
      return;
    }

    this.body.vx = 0;
    this.body.vy = input.axisY * TUNING.ladderSpeed;
    moveX(this.body, this.world, input.axisX * TUNING.walkSpeed * 0.5 * dt);
    moveY(this.body, this.world, this.body.vy * dt);
    if (input.axisX !== 0) this.facing = sign(input.axisX) as 1 | -1;

    if (input.consumePress('jump', TUNING.jumpBufferMs)) {
      this.body.vy = -TUNING.jumpSpeed * 0.82;
      this.enter('jump');
      this.events.onJump?.();
    }
  }

  // --- damage --------------------------------------------------------------

  private updateHurt(dt: number): void {
    this.hurtTimer -= dt;
    this.body.vx = approach(this.body.vx, 0, TUNING.groundFriction * 0.5 * dt);
    this.applyGravity(dt);
    this.integrate(dt);
    if (this.hurtTimer <= 0) this.enter(this.body.onGround ? 'idle' : 'fall');
  }

  damage(amount = 1, fromX = this.x): boolean {
    if (this.invulnerable > 0 || this.state === 'dead') return false;

    this.health = Math.max(0, this.health - amount);
    this.invulnerable = TUNING.invulnerableTime;
    const away = fromX === this.x ? -this.facing : sign(this.x - fromX) || 1;
    this.body.vx = away * TUNING.knockbackX;
    this.body.vy = -TUNING.knockbackY;
    this.body.onGround = false;
    this.setCrouched(false);

    if (this.health <= 0) {
      this.enter('dead');
      this.events.onDeath?.();
    } else {
      this.hurtTimer = 0.32;
      this.enter('hurt');
      this.events.onHurt?.(this.health);
    }
    return true;
  }

  kill(): void {
    if (this.state === 'dead') return;
    this.health = 0;
    this.body.vx = 0;
    this.body.vy = -TUNING.knockbackY * 0.6;
    this.enter('dead');
    this.events.onDeath?.();
  }

  /** Impact speed of the most recent landing — used for dust and camera shake. */
  get lastImpact(): number {
    return this.lastFallSpeed;
  }

  private setCrouched(crouched: boolean): void {
    const targetHeight = crouched ? TUNING.crouchHeight : TUNING.bodyHeight;
    if (this.body.h === targetHeight) return;
    const bottom = this.body.y + this.body.h;
    const candidate = { x: this.body.x, y: bottom - targetHeight, w: this.body.w, h: targetHeight };
    // Standing up into a ceiling is not allowed.
    if (!crouched && this.world.overlapsSolid(candidate)) return;
    this.body.h = targetHeight;
    this.body.y = bottom - targetHeight;
  }

  private enter(next: PlayerState): void {
    if (this.state === next) return;
    this.state = next;
    this.stateTime = 0;
  }
}
