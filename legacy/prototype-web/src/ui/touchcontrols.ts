/**
 * On-screen controls for touch devices.
 *
 * Left half of the screen is a floating virtual stick: wherever the thumb
 * lands becomes the origin, which beats a fixed pad on phones of every size.
 * Right half holds the two action buttons. Multi-touch is handled per pointer
 * id, so holding a direction while tapping jump works.
 *
 * The controls auto-hide as soon as a keyboard or gamepad is used.
 */

import { PALETTE, withAlpha } from '../render/palette';
import type { Renderer } from '../render/renderer';
import type { Action, Input } from '../core/input';

interface Button {
  action: Action;
  label: string;
  x: number;
  y: number;
  radius: number;
}

interface StickState {
  pointerId: number;
  originX: number;
  originY: number;
  x: number;
  y: number;
}

const STICK_RADIUS = 30;
const STICK_DEADZONE = 7;
const VERTICAL_BIAS = 0.75;

export class TouchControls {
  private stick: StickState | null = null;
  private readonly buttons: Button[] = [];
  private readonly buttonPointers = new Map<number, Button>();
  private detach: Array<() => void> = [];

  constructor(
    private readonly renderer: Renderer,
    private readonly input: Input,
  ) {
    this.layout();
  }

  /** Recompute button positions — call on resize so safe-area insets apply. */
  layout(): void {
    const safe = this.renderer.safe;
    const right = this.renderer.width - safe.right;
    const bottom = this.renderer.height - safe.bottom;

    this.buttons.length = 0;
    this.buttons.push(
      { action: 'jump', label: 'JUMP', x: right - 40, y: bottom - 38, radius: 24 },
      { action: 'action', label: 'SWORD', x: right - 88, y: bottom - 26, radius: 19 },
      { action: 'pause', label: 'II', x: right - 16, y: safe.top + 16, radius: 11 },
    );
  }

  attach(canvas: HTMLCanvasElement): void {
    const onDown = (e: PointerEvent) => {
      if (e.pointerType === 'mouse') return;
      // Registering the source here (and not only on the first drag) is what
      // makes a plain tap on the stick zone reveal the controls.
      this.input.lastSource = 'touch';
      const point = this.renderer.toVirtual(e.clientX, e.clientY);

      const button = this.hitButton(point.x, point.y);
      if (button) {
        this.buttonPointers.set(e.pointerId, button);
        this.input.setVirtual(button.action, true);
        canvas.setPointerCapture(e.pointerId);
        e.preventDefault();
        return;
      }

      if (!this.stick && point.x < this.renderer.width * 0.55) {
        this.stick = { pointerId: e.pointerId, originX: point.x, originY: point.y, x: point.x, y: point.y };
        canvas.setPointerCapture(e.pointerId);
        e.preventDefault();
      }
    };

    const onMove = (e: PointerEvent) => {
      if (!this.stick || this.stick.pointerId !== e.pointerId) return;
      const point = this.renderer.toVirtual(e.clientX, e.clientY);
      this.stick.x = point.x;
      this.stick.y = point.y;
      this.applyStick();
      e.preventDefault();
    };

    const onUp = (e: PointerEvent) => {
      const button = this.buttonPointers.get(e.pointerId);
      if (button) {
        this.buttonPointers.delete(e.pointerId);
        // Only release if no other finger holds the same action.
        if (![...this.buttonPointers.values()].some((b) => b.action === button.action)) {
          this.input.setVirtual(button.action, false);
        }
      }
      if (this.stick?.pointerId === e.pointerId) {
        this.stick = null;
        this.releaseDirections();
      }
    };

    const onContextMenu = (e: Event) => e.preventDefault();

    canvas.addEventListener('pointerdown', onDown, { passive: false });
    canvas.addEventListener('pointermove', onMove, { passive: false });
    canvas.addEventListener('pointerup', onUp);
    canvas.addEventListener('pointercancel', onUp);
    canvas.addEventListener('contextmenu', onContextMenu);

    this.detach = [
      () => canvas.removeEventListener('pointerdown', onDown),
      () => canvas.removeEventListener('pointermove', onMove),
      () => canvas.removeEventListener('pointerup', onUp),
      () => canvas.removeEventListener('pointercancel', onUp),
      () => canvas.removeEventListener('contextmenu', onContextMenu),
    ];
  }

  dispose(): void {
    for (const off of this.detach) off();
    this.detach = [];
    this.input.clearVirtual();
  }

  /** Shown whenever touch was the most recent input; a key press hides them. */
  get visible(): boolean {
    return this.input.lastSource === 'touch';
  }

  draw(renderer: Renderer): void {
    if (!this.visible) return;

    for (const button of this.buttons) {
      const held = this.input.down(button.action);
      renderer.fillCircle(button.x, button.y, button.radius, withAlpha(PALETTE.ink, held ? 0.4 : 0.22));
      renderer.ctx.strokeStyle = withAlpha(PALETTE.lightSoft, held ? 0.85 : 0.45);
      renderer.ctx.lineWidth = 1.2;
      renderer.ctx.beginPath();
      renderer.ctx.arc(button.x, button.y, button.radius, 0, Math.PI * 2);
      renderer.ctx.stroke();
      renderer.text(button.label, button.x, button.y, {
        size: button.radius > 14 ? 7 : 6,
        align: 'center',
        baseline: 'middle',
        color: withAlpha(PALETTE.paper, held ? 1 : 0.7),
        tracking: 0.5,
      });
    }

    if (this.stick) {
      const { originX, originY } = this.stick;
      const dx = this.stick.x - originX;
      const dy = this.stick.y - originY;
      const distance = Math.hypot(dx, dy) || 1;
      const clamped = Math.min(distance, STICK_RADIUS);
      const knobX = originX + (dx / distance) * clamped;
      const knobY = originY + (dy / distance) * clamped;

      renderer.fillCircle(originX, originY, STICK_RADIUS, withAlpha(PALETTE.ink, 0.18));
      renderer.fillCircle(knobX, knobY, 11, withAlpha(PALETTE.lightSoft, 0.55));
    }
  }

  private hitButton(x: number, y: number): Button | null {
    for (const button of this.buttons) {
      // Generous hit radius: the drawn circle is the visual, not the target.
      const r = button.radius + 8;
      if ((x - button.x) ** 2 + (y - button.y) ** 2 <= r * r) return button;
    }
    return null;
  }

  private applyStick(): void {
    if (!this.stick) return;
    const dx = this.stick.x - this.stick.originX;
    const dy = this.stick.y - this.stick.originY;

    this.input.setVirtual('left', dx < -STICK_DEADZONE);
    this.input.setVirtual('right', dx > STICK_DEADZONE);
    // Vertical needs a bigger push so running does not trigger ladders.
    const vertical = STICK_DEADZONE / VERTICAL_BIAS + 4;
    this.input.setVirtual('up', dy < -vertical);
    this.input.setVirtual('down', dy > vertical);
    // A small push walks, a full push runs.
    this.input.setVirtual('walk', Math.abs(dx) < STICK_RADIUS * 0.55);
  }

  private releaseDirections(): void {
    for (const action of ['left', 'right', 'up', 'down', 'walk'] as const) {
      this.input.setVirtual(action, false);
    }
  }
}
