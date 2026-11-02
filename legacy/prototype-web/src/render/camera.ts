/**
 * Follow camera with a dead zone, facing look-ahead and level clamping.
 *
 * Prince-of-Persia-style rooms want a camera that is mostly still: the dead
 * zone means small hops and turn-arounds do not shove the whole screen around.
 */

import { clamp, damp } from '../core/math';
import { DEFAULT_VIRTUAL_WIDTH, VIRTUAL_HEIGHT } from './renderer';

export interface CameraTarget {
  x: number;
  y: number;
  facing: number;
  onGround: boolean;
}

export class Camera {
  x = 0;
  y = 0;

  /** Half-size of the box the target may move in before the camera reacts. */
  deadZoneX = 28;
  deadZoneY = 24;
  /** How far ahead of the target we bias the view, in virtual units. */
  lookAhead = 34;
  lookAheadSmoothing = 0.22;
  smoothing = 0.09;

  private lookAheadCurrent = 0;
  private anchorY = 0;
  private shakeTime = 0;
  private shakeMagnitude = 0;
  private shakeX = 0;
  private shakeY = 0;

  /** Size of the visible view; kept in sync with the renderer on resize. */
  viewWidth = DEFAULT_VIRTUAL_WIDTH;
  viewHeight = VIRTUAL_HEIGHT;

  constructor(
    public boundsWidth: number,
    public boundsHeight: number,
  ) {}

  setViewport(width: number, height: number): void {
    this.viewWidth = width;
    this.viewHeight = height;
  }

  snapTo(target: CameraTarget): void {
    this.lookAheadCurrent = target.facing * this.lookAhead;
    this.anchorY = target.y;
    this.x = this.clampX(target.x + this.lookAheadCurrent - this.viewWidth / 2);
    this.y = this.clampY(target.y - this.viewHeight * 0.58);
  }

  update(target: CameraTarget, dt: number): void {
    this.lookAheadCurrent = damp(this.lookAheadCurrent, target.facing * this.lookAhead, this.lookAheadSmoothing, dt);

    // Horizontal: only chase once the target leaves the dead zone.
    const centreX = this.x + this.viewWidth / 2 - this.lookAheadCurrent;
    const dx = target.x - centreX;
    if (Math.abs(dx) > this.deadZoneX) {
      const desired = this.x + (dx - Math.sign(dx) * this.deadZoneX);
      this.x = damp(this.x, this.clampX(desired), this.smoothing, dt);
    }

    // Vertical: follow the last grounded height so jumping does not pan the view.
    if (target.onGround) this.anchorY = target.y;
    const centreY = this.y + this.viewHeight * 0.58;
    const dy = this.anchorY - centreY;
    if (Math.abs(dy) > this.deadZoneY) {
      const desired = this.y + (dy - Math.sign(dy) * this.deadZoneY);
      this.y = damp(this.y, this.clampY(desired), this.smoothing * 1.6, dt);
    }

    this.x = this.clampX(this.x);
    this.y = this.clampY(this.y);

    this.updateShake(dt);
  }

  shake(magnitude: number, duration = 0.25): void {
    this.shakeMagnitude = Math.max(this.shakeMagnitude, magnitude);
    this.shakeTime = Math.max(this.shakeTime, duration);
  }

  /** Camera position including shake — what the renderer should translate by. */
  get viewX(): number {
    return Math.round(this.x + this.shakeX);
  }

  get viewY(): number {
    return Math.round(this.y + this.shakeY);
  }

  private updateShake(dt: number): void {
    if (this.shakeTime <= 0) {
      this.shakeX = 0;
      this.shakeY = 0;
      this.shakeMagnitude = 0;
      return;
    }
    this.shakeTime -= dt;
    const falloff = Math.max(0, this.shakeTime) / 0.25;
    const amount = this.shakeMagnitude * Math.min(1, falloff);
    this.shakeX = (Math.random() * 2 - 1) * amount;
    this.shakeY = (Math.random() * 2 - 1) * amount;
  }

  private clampX(value: number): number {
    const max = Math.max(0, this.boundsWidth - this.viewWidth);
    return clamp(value, 0, max);
  }

  private clampY(value: number): number {
    const max = Math.max(0, this.boundsHeight - this.viewHeight);
    return clamp(value, 0, max);
  }
}
