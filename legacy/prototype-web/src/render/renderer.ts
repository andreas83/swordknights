/**
 * Canvas2D renderer with a fixed virtual resolution.
 *
 * The game always draws into a VIRTUAL_WIDTH x VIRTUAL_HEIGHT coordinate
 * space. On resize we letterbox-fit that box into the real canvas and bake the
 * scale into the transform, so no gameplay or UI code ever sees device pixels,
 * notches or device-pixel-ratio.
 */

import { clamp } from '../core/math';
import { PALETTE, withAlpha } from './palette';

/**
 * The virtual view is a fixed height with an aspect-derived width. Height is
 * what sets how big the character reads on screen, so it stays constant; width
 * flexes so a tall 20:9 phone sees more of the room instead of black bars.
 * The clamp keeps ultrawide and square displays from seeing unreasonably much
 * or little of the level.
 */
export const VIRTUAL_HEIGHT = 180;
export const MIN_VIRTUAL_WIDTH = 264;
export const MAX_VIRTUAL_WIDTH = 440;
export const DEFAULT_VIRTUAL_WIDTH = 320;

export interface SafeArea {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export class Renderer {
  readonly ctx: CanvasRenderingContext2D;
  /** Virtual view size. `width` changes with the display aspect ratio. */
  width = DEFAULT_VIRTUAL_WIDTH;
  readonly height = VIRTUAL_HEIGHT;

  /** Virtual units per CSS pixel. */
  scale = 1;
  /** Letterbox offset in CSS pixels. */
  offsetX = 0;
  offsetY = 0;
  /** Safe-area insets expressed in virtual units. */
  safe: SafeArea = { top: 0, right: 0, bottom: 0, left: 0 };

  private dpr = 1;

  constructor(readonly canvas: HTMLCanvasElement) {
    const ctx = canvas.getContext('2d', { alpha: false });
    if (!ctx) throw new Error('Canvas 2D context unavailable');
    this.ctx = ctx;
    this.resize();
  }

  resize(): void {
    const cssWidth = this.canvas.clientWidth || window.innerWidth;
    const cssHeight = this.canvas.clientHeight || window.innerHeight;
    this.dpr = Math.min(window.devicePixelRatio || 1, 3);

    const backingWidth = Math.max(1, Math.round(cssWidth * this.dpr));
    const backingHeight = Math.max(1, Math.round(cssHeight * this.dpr));
    if (this.canvas.width !== backingWidth) this.canvas.width = backingWidth;
    if (this.canvas.height !== backingHeight) this.canvas.height = backingHeight;

    const aspect = cssWidth / Math.max(1, cssHeight);
    this.width = Math.round(clamp(aspect * VIRTUAL_HEIGHT, MIN_VIRTUAL_WIDTH, MAX_VIRTUAL_WIDTH));

    this.scale = Math.min(cssWidth / this.width, cssHeight / VIRTUAL_HEIGHT);
    this.offsetX = (cssWidth - this.width * this.scale) / 2;
    this.offsetY = (cssHeight - VIRTUAL_HEIGHT * this.scale) / 2;

    this.safe = this.readSafeArea();
  }

  /** Begin a frame: reset transform, clear letterbox, clip to the virtual box. */
  begin(): void {
    const { ctx } = this;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = PALETTE.ink;
    ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

    const s = this.scale * this.dpr;
    ctx.setTransform(s, 0, 0, s, this.offsetX * this.dpr, this.offsetY * this.dpr);
    ctx.imageSmoothingEnabled = true;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, 0, this.width, this.height);
    ctx.clip();
  }

  end(): void {
    this.ctx.restore();
  }

  /** Convert a pointer event position into virtual coordinates. */
  toVirtual(clientX: number, clientY: number): { x: number; y: number } {
    const bounds = this.canvas.getBoundingClientRect();
    return {
      x: (clientX - bounds.left - this.offsetX) / this.scale,
      y: (clientY - bounds.top - this.offsetY) / this.scale,
    };
  }

  // --- drawing helpers -----------------------------------------------------

  fillRect(x: number, y: number, w: number, h: number, color: string): void {
    this.ctx.fillStyle = color;
    this.ctx.fillRect(x, y, w, h);
  }

  strokeRect(x: number, y: number, w: number, h: number, color: string, lineWidth = 1): void {
    this.ctx.strokeStyle = color;
    this.ctx.lineWidth = lineWidth;
    this.ctx.strokeRect(x, y, w, h);
  }

  fillPoly(points: ReadonlyArray<readonly [number, number]>, color: string): void {
    const { ctx } = this;
    if (points.length < 3) return;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(points[0][0], points[0][1]);
    for (let i = 1; i < points.length; i++) ctx.lineTo(points[i][0], points[i][1]);
    ctx.closePath();
    ctx.fill();
  }

  fillCircle(x: number, y: number, radius: number, color: string): void {
    const { ctx } = this;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.fill();
  }

  /** Rounded arch — the recurring motif of the architecture in the concept art. */
  fillArch(x: number, y: number, w: number, h: number, color: string): void {
    const { ctx } = this;
    const radius = Math.min(w / 2, h);
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(x, y + h);
    ctx.lineTo(x, y + radius);
    ctx.arc(x + w / 2, y + radius, radius, Math.PI, 0);
    ctx.lineTo(x + w, y + h);
    ctx.closePath();
    ctx.fill();
  }

  verticalGradient(x: number, y: number, w: number, h: number, stops: ReadonlyArray<readonly [number, string]>): void {
    const { ctx } = this;
    const gradient = ctx.createLinearGradient(x, y, x, y + h);
    for (const [offset, color] of stops) gradient.addColorStop(offset, color);
    ctx.fillStyle = gradient;
    ctx.fillRect(x, y, w, h);
  }

  text(
    value: string,
    x: number,
    y: number,
    options: { size?: number; color?: string; align?: CanvasTextAlign; baseline?: CanvasTextBaseline; tracking?: number; weight?: number } = {},
  ): void {
    const { ctx } = this;
    const size = options.size ?? 8;
    ctx.save();
    ctx.font = `${options.weight ?? 700} ${size}px ui-sans-serif, system-ui, sans-serif`;
    ctx.fillStyle = options.color ?? PALETTE.paper;
    ctx.textAlign = options.align ?? 'left';
    ctx.textBaseline = options.baseline ?? 'top';
    if (options.tracking) {
      ctx.letterSpacing = `${options.tracking}px`;
    }
    ctx.fillText(value, x, y);
    ctx.restore();
  }

  /** Full-screen colour wash, used for fades and damage flashes. */
  flash(color: string, alpha: number): void {
    if (alpha <= 0) return;
    this.fillRect(0, 0, this.width, this.height, withAlpha(color, Math.min(1, alpha)));
  }

  private readSafeArea(): SafeArea {
    const probe = document.createElement('div');
    probe.style.cssText =
      'position:fixed;top:0;left:0;visibility:hidden;' +
      'padding-top:env(safe-area-inset-top);padding-right:env(safe-area-inset-right);' +
      'padding-bottom:env(safe-area-inset-bottom);padding-left:env(safe-area-inset-left);';
    document.body.appendChild(probe);
    const style = getComputedStyle(probe);
    const toVirtual = (value: string) => (parseFloat(value) || 0) / Math.max(1e-6, this.scale);
    const safe: SafeArea = {
      top: toVirtual(style.paddingTop),
      right: toVirtual(style.paddingRight),
      bottom: toVirtual(style.paddingBottom),
      left: toVirtual(style.paddingLeft),
    };
    probe.remove();
    return safe;
  }
}
