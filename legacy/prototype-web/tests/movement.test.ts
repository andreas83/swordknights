/**
 * These tests lock the jump arc to the level geometry.
 *
 * `src/game/levels/level01.ts` is built on three rules — a 2-tile rise is a
 * hop, a 3-tile rise needs a platform step, a 4-tile rise needs a ledge grab.
 * If someone retunes `TUNING` and those stop holding, the level becomes
 * unplayable; these tests fail first instead.
 */

import { describe, expect, it } from 'vitest';
import { Player } from '../src/game/player';
import { World } from '../src/game/world';
import { TILE_SIZE } from '../src/game/tiles';
import { TUNING } from '../src/game/tuning';
import { StubInput } from './support/stubinput';

const STEP = 1 / 60;

function simulate(player: Player, input: StubInput, steps: number, onStep?: (i: number) => void): void {
  for (let i = 0; i < steps; i++) {
    onStep?.(i);
    player.update(STEP, input);
    input.endStep();
  }
}

/** A flat floor with nothing else on it. */
function flatWorld(cols = 40) {
  const ground = '#'.repeat(cols);
  const air = ' '.repeat(cols);
  return new World({
    id: 'flat',
    name: 'flat',
    rows: [air, air, air, air, air, air, air, air, `@${air.slice(1)}`, ground, ground],
  });
}

describe('jump arc', () => {
  it('clears a 2-tile rise from a standstill', () => {
    const world = flatWorld();
    const player = new Player(world);
    const input = new StubInput();
    const startFeet = player.y;

    input.press('jump');
    let highest = startFeet;
    simulate(player, input, 60, () => {
      highest = Math.min(highest, player.y);
    });

    const rise = startFeet - highest;
    expect(rise).toBeGreaterThanOrEqual(TILE_SIZE * 2);
    expect(rise).toBeLessThan(TILE_SIZE * 3);
    expect(player.body.onGround).toBe(true);
  });

  it('cuts the jump short when the button is released early', () => {
    const world = flatWorld();
    const input = new StubInput();
    const player = new Player(world);
    const startFeet = player.y;

    input.press('jump');
    let highest = startFeet;
    simulate(player, input, 60, (i) => {
      if (i === 4) input.release('jump');
      highest = Math.min(highest, player.y);
    });

    expect(startFeet - highest).toBeLessThan(TILE_SIZE * 1.5);
  });

  it('clears a 2-tile gap with a running jump', () => {
    const world = flatWorld();
    const player = new Player(world);
    const input = new StubInput();

    input.hold('right');
    simulate(player, input, 60); // build up to full running speed
    expect(Math.abs(player.body.vx)).toBeGreaterThan(TUNING.runSpeed * 0.95);

    const launchX = player.x;
    const launchY = player.y;
    input.press('jump');
    let airborneDistance = 0;
    simulate(player, input, 90, () => {
      if (player.y < launchY - 1) airborneDistance = player.x - launchX;
    });

    expect(airborneDistance).toBeGreaterThanOrEqual(TILE_SIZE * 2);
  });
});

describe('ledge grab', () => {
  /** Floor at row 9, a wall whose top edge is `rise` tiles above it. */
  function wallWorld(rise: number) {
    const width = 20;
    const wallX = 8;
    const topRow = 9 - rise;
    const rows: string[] = [];
    for (let y = 0; y < 12; y++) {
      let row = '';
      for (let x = 0; x < width; x++) {
        if (y === 8 && x === 1) row += '@';
        else if (y >= 9 && x < wallX) row += '#';
        else if (x >= wallX && y >= topRow) row += '#';
        else row += ' ';
      }
      rows.push(row);
    }
    return new World({ id: 'wall', name: 'wall', rows });
  }

  it('catches a ledge four tiles above the floor', () => {
    const world = wallWorld(4);
    const player = new Player(world);
    const input = new StubInput();

    input.hold('right');
    simulate(player, input, 60);
    input.press('jump');
    simulate(player, input, 40);

    expect(player.state).toBe('hang');
  });

  it('climbs up to stand on the ledge it grabbed', () => {
    const world = wallWorld(4);
    const player = new Player(world);
    const input = new StubInput();

    input.hold('right');
    simulate(player, input, 60);
    input.press('jump');
    simulate(player, input, 40);
    expect(player.state).toBe('hang');

    input.release('jump', 'right');
    input.hold('up');
    simulate(player, input, 60);

    expect(player.state).toBe('idle');
    expect(player.body.onGround).toBe(true);
    expect(player.y).toBeCloseTo(TILE_SIZE * 5, 0);
  });

  it('does not grab a ledge while holding down', () => {
    const world = wallWorld(4);
    const player = new Player(world);
    const input = new StubInput();

    input.hold('right');
    simulate(player, input, 60);
    input.press('jump');
    input.hold('down');
    simulate(player, input, 40);

    expect(player.state).not.toBe('hang');
  });
});

describe('forgiveness windows', () => {
  it('allows a jump shortly after walking off a ledge (coyote time)', () => {
    const world = new World({
      id: 'edge',
      name: 'edge',
      rows: ['          ', '          ', '          ', '        @ ', '  ####### ', '          '],
    });
    const player = new Player(world);
    const input = new StubInput();

    // Walk right until the ground runs out, noting the exact step.
    input.hold('right');
    let leftGroundAt = -1;
    for (let i = 0; i < 60 && leftGroundAt < 0; i++) {
      player.update(STEP, input);
      input.endStep();
      if (!player.body.onGround) leftGroundAt = i;
    }
    expect(leftGroundAt).toBeGreaterThan(0);

    // One step into free fall the jump must still be accepted.
    player.update(STEP, input);
    input.endStep();
    input.press('jump');
    player.update(STEP, input);
    expect(player.body.vy).toBeLessThan(0);
  });

  it('refuses the jump once the coyote window has expired', () => {
    const world = new World({
      id: 'edge',
      name: 'edge',
      rows: ['          ', '          ', '          ', '        @ ', '  ####### ', '          '],
    });
    const player = new Player(world);
    const input = new StubInput();

    input.hold('right');
    let leftGroundAt = -1;
    for (let i = 0; i < 60 && leftGroundAt < 0; i++) {
      player.update(STEP, input);
      input.endStep();
      if (!player.body.onGround) leftGroundAt = i;
    }

    // Well past TUNING.coyoteTime.
    simulate(player, input, Math.ceil(TUNING.coyoteTime / STEP) + 3);
    input.press('jump');
    player.update(STEP, input);
    expect(player.body.vy).toBeGreaterThan(0);
  });
});

describe('damage', () => {
  it('spends a heart and goes invulnerable, then dies at zero', () => {
    const world = flatWorld();
    const player = new Player(world);

    expect(player.damage(1, player.x - 20)).toBe(true);
    expect(player.health).toBe(TUNING.maxHealth - 1);
    // A second hit during invulnerability is ignored.
    expect(player.damage(1, player.x - 20)).toBe(false);

    player.invulnerable = 0;
    player.damage(TUNING.maxHealth, player.x - 20);
    expect(player.health).toBe(0);
    expect(player.state).toBe('dead');
    expect(player.alive).toBe(false);
  });
});
