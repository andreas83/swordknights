/**
 * Unified input: keyboard, gamepad and on-screen touch controls each own a
 * private state set; the public state is their union. Gameplay code therefore
 * never asks "which device?" and releasing a key cannot clear a held thumbstick.
 *
 * Also provides the two timing tricks every platformer needs:
 *  - press buffering (`consumePress`) — a jump tapped just before landing still fires
 *  - edge queries (`pressed`, `released`) on top of held state (`down`)
 */

export const ACTIONS = ['left', 'right', 'up', 'down', 'jump', 'action', 'walk', 'pause'] as const;
export type Action = (typeof ACTIONS)[number];

export type InputSource = 'keyboard' | 'touch' | 'gamepad';

/**
 * The read-only surface gameplay code depends on. Keeping it structural means
 * the player state machine can be driven by a scripted stub in tests without
 * any DOM.
 */
export interface InputReader {
  readonly axisX: number;
  readonly axisY: number;
  down(action: Action): boolean;
  pressed(action: Action): boolean;
  released(action: Action): boolean;
  consumePress(action: Action, windowMs?: number, now?: number): boolean;
}

const KEY_MAP: Record<string, Action> = {
  ArrowLeft: 'left',
  ArrowRight: 'right',
  ArrowUp: 'up',
  ArrowDown: 'down',
  KeyA: 'left',
  KeyD: 'right',
  KeyW: 'up',
  KeyS: 'down',
  Space: 'jump',
  KeyK: 'jump',
  KeyJ: 'action',
  KeyE: 'action',
  Enter: 'action',
  ShiftLeft: 'walk',
  ShiftRight: 'walk',
  Escape: 'pause',
  KeyP: 'pause',
};

/** Standard-mapping gamepad button index -> action. */
const PAD_BUTTON_MAP: ReadonlyArray<readonly [number, Action]> = [
  [0, 'jump'], // A / cross
  [1, 'action'], // B / circle
  [2, 'action'], // X / square
  [6, 'walk'], // left trigger
  [9, 'pause'], // start
  [12, 'up'],
  [13, 'down'],
  [14, 'left'],
  [15, 'right'],
];

const PAD_DEADZONE = 0.4;

export class Input implements InputReader {
  /** Last device that produced a press — drives showing/hiding the touch UI. */
  lastSource: InputSource = 'keyboard';

  private readonly keys = new Set<Action>();
  private readonly pad = new Set<Action>();
  private readonly touch = new Set<Action>();

  private readonly current = new Set<Action>();
  private readonly previous = new Set<Action>();

  /** performance.now() of the most recent press, per action. */
  private readonly pressedAt = new Map<Action, number>();
  private readonly consumedAt = new Map<Action, number>();

  private detach: Array<() => void> = [];

  attach(target: Window = window): void {
    const onKeyDown = (e: KeyboardEvent) => {
      const action = KEY_MAP[e.code];
      if (!action) return;
      e.preventDefault();
      if (e.repeat) return;
      this.keys.add(action);
      this.notePress(action, 'keyboard');
    };
    const onKeyUp = (e: KeyboardEvent) => {
      const action = KEY_MAP[e.code];
      if (!action) return;
      e.preventDefault();
      this.keys.delete(action);
    };
    const onBlur = () => this.clear();

    target.addEventListener('keydown', onKeyDown as EventListener, { passive: false });
    target.addEventListener('keyup', onKeyUp as EventListener, { passive: false });
    target.addEventListener('blur', onBlur);

    this.detach = [
      () => target.removeEventListener('keydown', onKeyDown as EventListener),
      () => target.removeEventListener('keyup', onKeyUp as EventListener),
      () => target.removeEventListener('blur', onBlur),
    ];
  }

  dispose(): void {
    for (const off of this.detach) off();
    this.detach = [];
    this.clear();
  }

  /** Called by the on-screen controls. */
  setVirtual(action: Action, isDown: boolean): void {
    if (isDown) {
      if (this.touch.has(action)) return;
      this.touch.add(action);
      this.notePress(action, 'touch');
    } else {
      this.touch.delete(action);
    }
  }

  clearVirtual(): void {
    this.touch.clear();
  }

  clear(): void {
    this.keys.clear();
    this.pad.clear();
    this.touch.clear();
    this.current.clear();
    this.previous.clear();
  }

  /** Snapshot edges and poll gamepads. Call once per simulation step, before update. */
  poll(): void {
    this.previous.clear();
    for (const action of this.current) this.previous.add(action);

    this.pollGamepads();

    this.current.clear();
    for (const action of this.keys) this.current.add(action);
    for (const action of this.pad) this.current.add(action);
    for (const action of this.touch) this.current.add(action);
  }

  down(action: Action): boolean {
    return this.current.has(action);
  }

  pressed(action: Action): boolean {
    return this.current.has(action) && !this.previous.has(action);
  }

  released(action: Action): boolean {
    return !this.current.has(action) && this.previous.has(action);
  }

  /** -1, 0 or 1 from the horizontal actions. */
  get axisX(): number {
    return (this.down('right') ? 1 : 0) - (this.down('left') ? 1 : 0);
  }

  get axisY(): number {
    return (this.down('down') ? 1 : 0) - (this.down('up') ? 1 : 0);
  }

  /**
   * True once if `action` was pressed within the last `windowMs` and has not
   * been consumed yet. This is the jump-buffer primitive.
   */
  consumePress(action: Action, windowMs = 120, now = performance.now()): boolean {
    const at = this.pressedAt.get(action);
    if (at === undefined) return false;
    if (this.consumedAt.get(action) === at) return false;
    if (now - at > windowMs) return false;
    this.consumedAt.set(action, at);
    return true;
  }

  private notePress(action: Action, source: InputSource): void {
    this.pressedAt.set(action, performance.now());
    this.lastSource = source;
  }

  private pollGamepads(): void {
    const pads = navigator.getGamepads?.() ?? [];
    const next = new Set<Action>();

    for (const gamepad of pads) {
      if (!gamepad?.connected) continue;

      const ax = gamepad.axes[0] ?? 0;
      const ay = gamepad.axes[1] ?? 0;
      if (ax < -PAD_DEADZONE) next.add('left');
      if (ax > PAD_DEADZONE) next.add('right');
      if (ay < -PAD_DEADZONE) next.add('up');
      if (ay > PAD_DEADZONE) next.add('down');

      for (const [index, action] of PAD_BUTTON_MAP) {
        if (gamepad.buttons[index]?.pressed) next.add(action);
      }
    }

    for (const action of next) {
      if (!this.pad.has(action)) this.notePress(action, 'gamepad');
    }
    this.pad.clear();
    for (const action of next) this.pad.add(action);
  }
}
