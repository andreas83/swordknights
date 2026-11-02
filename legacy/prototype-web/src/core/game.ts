/**
 * Top-level wiring: owns the canvas, renderer, input, audio, loop and the
 * current scene, and keeps them alive across resizes, orientation changes and
 * the app being backgrounded.
 */

import { Audio } from './audio';
import { GameLoop } from './loop';
import { Input } from './input';
import { Renderer } from '../render/renderer';
import { TouchControls } from '../ui/touchcontrols';
import { loadSave, writeSave } from './storage';
import type { SaveData } from './storage';
import type { GameContext, Scene } from '../scenes/scene';

export class Game implements GameContext {
  readonly renderer: Renderer;
  readonly input = new Input();
  readonly audio = new Audio();
  readonly save: SaveData;

  private readonly loop: GameLoop;
  private readonly touch: TouchControls;
  private scene: Scene | null = null;
  private pendingScene: Scene | null = null;
  private resizePending = false;

  constructor(canvas: HTMLCanvasElement) {
    this.renderer = new Renderer(canvas);
    this.save = loadSave();
    this.audio.muted = this.save.muted;
    this.touch = new TouchControls(this.renderer, this.input);
    this.loop = new GameLoop({ update: (dt) => this.update(dt), render: (alpha) => this.render(alpha) }, 60);

    this.input.attach(window);
    this.touch.attach(canvas);

    // Phones and tablets should see the controls before touching anything;
    // the first key or pad press flips this back and hides them again.
    if (window.matchMedia?.('(pointer: coarse)').matches) this.input.lastSource = 'touch';

    window.addEventListener('resize', this.onResize);
    window.addEventListener('orientationchange', this.onResize);
    document.addEventListener('visibilitychange', this.onVisibilityChange);

    // Mobile browsers only allow audio after a gesture.
    const unlock = () => this.audio.unlock();
    window.addEventListener('pointerdown', unlock, { once: true });
    window.addEventListener('keydown', unlock, { once: true });
  }

  setScene(scene: Scene): void {
    // Defer the swap so a scene can replace itself from inside its own update.
    this.pendingScene = scene;
  }

  persist(): void {
    this.save.muted = this.audio.muted;
    writeSave(this.save);
  }

  start(): void {
    this.applyPendingScene();
    this.loop.start();
  }

  stop(): void {
    this.loop.stop();
  }

  dispose(): void {
    this.stop();
    this.scene?.exit?.(this);
    this.touch.dispose();
    this.input.dispose();
    window.removeEventListener('resize', this.onResize);
    window.removeEventListener('orientationchange', this.onResize);
    document.removeEventListener('visibilitychange', this.onVisibilityChange);
  }

  private update(dt: number): void {
    this.applyPendingScene();
    if (this.resizePending) {
      this.resizePending = false;
      this.renderer.resize();
      this.touch.layout();
      this.scene?.resize?.(this);
    }
    this.input.poll();
    this.scene?.update(dt, this);
  }

  private render(alpha: number): void {
    this.renderer.begin();
    this.scene?.draw(this.renderer, alpha, this);
    this.touch.draw(this.renderer);
    this.renderer.end();
  }

  private applyPendingScene(): void {
    if (!this.pendingScene) return;
    this.scene?.exit?.(this);
    this.scene = this.pendingScene;
    this.pendingScene = null;
    this.scene.enter?.(this);
  }

  private onResize = (): void => {
    this.resizePending = true;
  };

  private onVisibilityChange = (): void => {
    if (document.hidden) {
      this.loop.stop();
      this.input.clear();
    } else {
      this.loop.resetClock();
      this.loop.start();
    }
  };
}
