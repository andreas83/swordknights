/**
 * Draws the prince as a posed cloak silhouette rather than a sprite sheet.
 *
 * Shapes are derived from the character's state and `stateTime`, which keeps
 * the foundation asset-free: swapping in real sprites later means replacing
 * this one file, not touching gameplay.
 */

import { PALETTE, withAlpha } from './palette';
import type { Player } from '../game/player';
import type { Renderer } from './renderer';

interface Pose {
  /** Vertical squash/stretch, 1 = neutral. */
  squash: number;
  lean: number;
  armSwing: number;
  legSwing: number;
  hoodDrop: number;
}

export class PlayerRenderer {
  draw(renderer: Renderer, player: Player, time: number): void {
    const { body } = player;
    const pose = this.posture(player, time);

    const height = body.h * pose.squash;
    const width = body.w / Math.max(0.6, pose.squash);
    const cx = body.x + body.w / 2;
    const feetY = body.y + body.h;
    const topY = feetY - height;
    const lean = pose.lean * player.facing;

    // Invulnerability flicker — skip whole frames so the hit reads clearly.
    if (player.invulnerable > 0 && Math.floor(time * 18) % 2 === 0) return;

    // Contact shadow.
    if (body.onGround) {
      renderer.fillCircle(cx + 1, feetY + 1, width * 0.72, withAlpha(PALETTE.ink, 0.25));
    }

    // Legs (only visible below the hem when moving).
    if (pose.legSwing !== 0) {
      const legY = feetY;
      renderer.fillRect(cx - 2.6 + pose.legSwing, legY - 5, 2.2, 5, PALETTE.ink);
      renderer.fillRect(cx + 0.6 - pose.legSwing, legY - 5, 2.2, 5, PALETTE.ink);
    }

    // Cloak: a cone from the shoulders to the hem, split into lit and shade halves.
    const hemHalf = width * 0.92;
    const shoulderY = topY + height * 0.2;
    const apexX = cx + lean;

    renderer.fillPoly(
      [
        [apexX, topY + height * 0.08],
        [cx + hemHalf, feetY],
        [cx - hemHalf, feetY],
      ],
      PALETTE.clothDark,
    );
    renderer.fillPoly(
      [
        [apexX, topY + height * 0.08],
        [cx + hemHalf * player.facing, feetY],
        [cx + hemHalf * player.facing * 0.1, feetY],
      ],
      PALETTE.cloth,
    );

    // Sash catching the light.
    renderer.fillRect(cx - width * 0.5 + lean * 0.4, shoulderY + height * 0.22, width, 1.6, PALETTE.lightWarm);

    // Arm / sword.
    const handX = cx + player.facing * (width * 0.7 + pose.armSwing);
    const handY = shoulderY + height * 0.18;
    if (player.state === 'attack') {
      this.drawSwing(renderer, player, cx, shoulderY, height);
    } else if (player.isHanging) {
      renderer.fillRect(cx - width * 0.8, topY + 1, width * 1.6, 2.2, PALETTE.ink);
    } else {
      renderer.fillRect(Math.min(handX, cx), handY, Math.abs(handX - cx) + 1.4, 2, PALETTE.clothDark);
    }

    // Hood.
    const hoodY = topY + 3.2 + pose.hoodDrop;
    renderer.fillCircle(apexX, hoodY, width * 0.46, PALETTE.ink);
    renderer.fillPoly(
      [
        [apexX - player.facing * width * 0.1, hoodY - width * 0.5],
        [apexX + player.facing * width * 0.62, hoodY + width * 0.1],
        [apexX - player.facing * width * 0.3, hoodY + width * 0.4],
      ],
      PALETTE.clothDark,
    );
    // Eye glint.
    renderer.fillRect(apexX + player.facing * width * 0.22, hoodY - 0.4, 1.3, 1.1, PALETTE.light);
  }

  private drawSwing(renderer: Renderer, player: Player, cx: number, shoulderY: number, height: number): void {
    const phase = Math.min(1, player.stateTime / 0.28);
    const angle = (-0.9 + phase * 2.1) * player.facing;
    const length = 15;
    const originX = cx + player.facing * 3;
    const originY = shoulderY + height * 0.16;
    const tipX = originX + Math.cos(angle) * length * player.facing;
    const tipY = originY + Math.sin(angle) * length;

    renderer.fillPoly(
      [
        [originX, originY - 1.4],
        [tipX, tipY],
        [originX, originY + 1.4],
      ],
      PALETTE.steel,
    );
    renderer.fillCircle(originX, originY, 1.8, PALETTE.lightWarm);
    if (phase > 0.25 && phase < 0.8) {
      renderer.fillCircle(tipX, tipY, 2.2, withAlpha(PALETTE.paper, 0.5));
    }
  }

  private posture(player: Player, time: number): Pose {
    const t = player.stateTime;
    switch (player.state) {
      case 'run': {
        const cycle = Math.sin(t * 16);
        return { squash: 1, lean: 2.6, armSwing: cycle * 2.4, legSwing: cycle * 2.2, hoodDrop: 0 };
      }
      case 'walk': {
        const cycle = Math.sin(t * 9);
        return { squash: 1, lean: 1.2, armSwing: cycle * 1.4, legSwing: cycle * 1.3, hoodDrop: 0 };
      }
      case 'turn':
        return { squash: 0.96, lean: -2.2, armSwing: -1.5, legSwing: 0, hoodDrop: 0.4 };
      case 'crouch':
        return { squash: 1, lean: 0.6, armSwing: 0, legSwing: 0, hoodDrop: 0.8 };
      case 'jump':
        return { squash: 1.06, lean: 1.8, armSwing: 2.8, legSwing: 1.4, hoodDrop: -0.6 };
      case 'fall':
        return { squash: 1.03, lean: 1.2, armSwing: 1.8, legSwing: -1.2, hoodDrop: -0.3 };
      case 'land':
        return { squash: 0.84, lean: 0.8, armSwing: -1, legSwing: 0, hoodDrop: 1.2 };
      case 'hang':
        return { squash: 1.08, lean: 0, armSwing: 0, legSwing: Math.sin(time * 3) * 0.6, hoodDrop: 1.4 };
      case 'climbUp':
        return { squash: 0.92, lean: 1.6, armSwing: 0, legSwing: 1.6, hoodDrop: 0.6 };
      case 'ladder':
        return { squash: 1, lean: 0, armSwing: Math.sin(t * 8) * 2, legSwing: Math.sin(t * 8) * 1.6, hoodDrop: 0 };
      case 'hurt':
        return { squash: 0.95, lean: -3, armSwing: -2.4, legSwing: 0, hoodDrop: 1.6 };
      case 'dead':
        return { squash: 0.55, lean: -4, armSwing: -3, legSwing: 0, hoodDrop: 2.4 };
      case 'attack':
        return { squash: 1, lean: 2.2, armSwing: 3.2, legSwing: 0, hoodDrop: 0 };
      default: {
        const breathe = Math.sin(time * 2.2) * 0.012;
        return { squash: 1 + breathe, lean: 0.4, armSwing: 0, legSwing: 0, hoodDrop: 0 };
      }
    }
  }
}
