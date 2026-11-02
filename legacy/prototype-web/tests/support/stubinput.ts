import type { Action, InputReader } from '../../src/core/input';

/**
 * A scripted InputReader so the player state machine can be simulated
 * headlessly. `press` marks an edge for exactly one step and feeds the
 * press buffer that `consumePress` reads.
 */
export class StubInput implements InputReader {
  private held = new Set<Action>();
  private edges = new Set<Action>();
  private consumed = new Set<Action>();

  hold(...actions: Action[]): this {
    for (const action of actions) this.held.add(action);
    return this;
  }

  release(...actions: Action[]): this {
    for (const action of actions) this.held.delete(action);
    return this;
  }

  press(action: Action): this {
    this.held.add(action);
    this.edges.add(action);
    this.consumed.delete(action);
    return this;
  }

  /** Call once per simulated step, after the player has read the input. */
  endStep(): void {
    this.edges.clear();
  }

  get axisX(): number {
    return (this.down('right') ? 1 : 0) - (this.down('left') ? 1 : 0);
  }

  get axisY(): number {
    return (this.down('down') ? 1 : 0) - (this.down('up') ? 1 : 0);
  }

  down(action: Action): boolean {
    return this.held.has(action);
  }

  pressed(action: Action): boolean {
    return this.edges.has(action);
  }

  released(): boolean {
    return false;
  }

  consumePress(action: Action): boolean {
    if (!this.edges.has(action) || this.consumed.has(action)) return false;
    this.consumed.add(action);
    return true;
  }
}
