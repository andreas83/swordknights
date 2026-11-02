/**
 * The playable scene: owns a level's world, actors, camera and presentation,
 * and arbitrates the interactions between them.
 *
 * Everything that is level-specific lives in the `LevelDefinition` it is given,
 * so adding level 2 means adding one ASCII file and nothing else.
 */

import { clamp, rectsOverlap } from '../core/math';
import { PALETTE, withAlpha } from '../render/palette';
import { Camera } from '../render/camera';
import { Parallax } from '../render/parallax';
import { PlayerRenderer } from '../render/playerrenderer';
import { WorldRenderer } from '../render/worldrenderer';
import { Hud } from '../ui/hud';
import { Player } from '../game/player';
import { TILE_SIZE } from '../game/tiles';
import { World } from '../game/world';
import { ExitDoor } from '../game/entities/exit';
import { Patrol } from '../game/entities/patrol';
import { Relic } from '../game/entities/relic';
import { Torch } from '../game/entities/torch';
import { TUNING } from '../game/tuning';
import type { Entity } from '../game/entities/entity';
import type { LevelDefinition } from '../game/world';
import type { Renderer } from '../render/renderer';
import type { GameContext, Scene } from './scene';

type Phase = 'playing' | 'dying' | 'complete' | 'paused';

const DEATH_HOLD = 1.1;
const FADE_SPEED = 2.6;

export class PlayScene implements Scene {
  private readonly world: World;
  private readonly player: Player;
  private readonly camera: Camera;
  private readonly parallax: Parallax;
  private readonly worldRenderer: WorldRenderer;
  private readonly playerRenderer = new PlayerRenderer();
  private readonly hud = new Hud();

  private entities: Entity[] = [];
  private exitDoor: ExitDoor | null = null;

  private phase: Phase = 'playing';
  private time = 0;
  private elapsed = 0;
  private deathTimer = 0;
  private relics = 0;
  private relicsTotal = 0;
  private fade = 1;
  private fadeTarget = 0;
  private damageFlash = 0;

  constructor(
    private readonly level: LevelDefinition,
    private readonly context: GameContext,
  ) {
    this.world = new World(level);
    this.worldRenderer = new WorldRenderer(this.world);
    this.parallax = new Parallax(hashSeed(level.id), this.world.widthPx);
    this.camera = new Camera(this.world.widthPx, this.world.heightPx);
    this.camera.setViewport(context.renderer.width, context.renderer.height);

    this.player = new Player(this.world, {
      onJump: () => this.context.audio.play('jump'),
      onGrab: () => this.context.audio.play('grab'),
      onAttack: () => this.context.audio.play('sword'),
      onLand: (impact) => {
        if (impact < TUNING.softLandSpeed) return;
        this.context.audio.play('land', clamp(impact / TUNING.hardLandSpeed, 0.6, 1.3));
        if (impact >= TUNING.hardLandSpeed) this.camera.shake(1.6, 0.18);
      },
      onHurt: () => {
        this.context.audio.play('hurt');
        this.camera.shake(2.4, 0.26);
        this.damageFlash = 1;
      },
      onDeath: () => {
        this.context.audio.play('hurt', 0.7);
        this.camera.shake(3, 0.4);
        this.phase = 'dying';
        this.deathTimer = DEATH_HOLD;
        this.context.save.deaths += 1;
        this.context.persist();
      },
    });

    this.spawnEntities();
    this.camera.snapTo(this.cameraTarget());
  }

  enter(): void {
    this.fade = 1;
    this.fadeTarget = 0;
  }

  update(dt: number, ctx: GameContext): void {
    this.time += dt;
    this.fade = approachValue(this.fade, this.fadeTarget, FADE_SPEED * dt);
    this.damageFlash = Math.max(0, this.damageFlash - dt * 2.4);

    if (ctx.input.pressed('pause') && (this.phase === 'playing' || this.phase === 'paused')) {
      this.phase = this.phase === 'paused' ? 'playing' : 'paused';
    }
    if (this.phase === 'paused') return;

    if (this.phase === 'complete') {
      if (ctx.input.pressed('jump') || ctx.input.pressed('action')) this.restart();
      return;
    }

    if (this.phase === 'dying') {
      this.deathTimer -= dt;
      this.player.update(dt, ctx.input);
      this.camera.update(this.cameraTarget(), dt);
      if (this.deathTimer <= 0) {
        this.fadeTarget = 1;
        if (this.fade >= 0.98) this.restart();
      }
      return;
    }

    this.elapsed += dt;
    this.player.update(dt, ctx.input);

    for (const entity of this.entities) entity.update({ world: this.world, dt });
    this.resolveInteractions(ctx);
    this.entities = this.entities.filter((entity) => !entity.dead);

    this.camera.update(this.cameraTarget(), dt);
  }

  draw(renderer: Renderer, _alpha: number, _ctx: GameContext): void {
    const camX = this.camera.viewX;
    const camY = this.camera.viewY;

    this.parallax.draw(renderer, camX, camY, this.time);

    renderer.ctx.save();
    renderer.ctx.translate(-camX, -camY);
    this.worldRenderer.draw(renderer, camX, camY, this.time);
    for (const entity of this.entities) entity.draw(renderer, this.time);
    this.playerRenderer.draw(renderer, this.player, this.time);
    renderer.ctx.restore();

    this.drawVignette(renderer);

    this.hud.draw(renderer, {
      health: this.player.health,
      maxHealth: TUNING.maxHealth,
      relics: this.relics,
      relicsTotal: this.relicsTotal,
      levelName: this.level.name,
      elapsed: this.elapsed,
    });

    if (this.phase === 'paused') this.drawOverlay(renderer, 'PAUSED', 'Press start to resume');
    if (this.phase === 'complete') {
      this.drawOverlay(renderer, 'ESCAPED', `${this.relics}/${this.relicsTotal} relics · ${this.elapsed.toFixed(1)}s · tap to replay`);
    }

    if (this.damageFlash > 0) renderer.flash(PALETTE.cloth, this.damageFlash * 0.3);
    if (this.fade > 0) renderer.flash(PALETTE.ink, this.fade);
  }

  resize(ctx: GameContext): void {
    this.camera.setViewport(ctx.renderer.width, ctx.renderer.height);
    this.camera.snapTo(this.cameraTarget());
  }

  // --- internals -----------------------------------------------------------

  private spawnEntities(): void {
    this.entities = [];
    this.relics = 0;
    this.relicsTotal = 0;
    this.exitDoor = null;

    for (const spawn of this.world.spawns) {
      switch (spawn.kind) {
        case 'relic':
          this.entities.push(new Relic(spawn.x, spawn.y));
          this.relicsTotal += 1;
          break;
        case 'exit': {
          const door = new ExitDoor(spawn.x, spawn.y);
          this.exitDoor = door;
          this.entities.push(door);
          break;
        }
        case 'torch':
          this.entities.push(new Torch(spawn.x, spawn.y));
          break;
        case 'patrol':
          this.entities.push(new Patrol(spawn.x, spawn.y));
          break;
        default:
          break;
      }
    }
  }

  private resolveInteractions(ctx: GameContext): void {
    const body = this.player.body;

    // Hazard tiles and bottomless falls.
    if (this.player.alive) {
      if (this.world.overlapsDeadly(body)) {
        this.player.kill();
        return;
      }
      if (body.y > this.world.heightPx + TILE_SIZE * 3) {
        this.player.kill();
        return;
      }
    }

    const attack = this.player.attackBox;

    for (const entity of this.entities) {
      if (entity instanceof Relic) {
        if (rectsOverlap(body, entity.bounds)) {
          entity.collect();
          this.relics += 1;
          ctx.audio.play('relic');
          const key = this.level.id;
          ctx.save.relics[key] = Math.max(ctx.save.relics[key] ?? 0, this.relics);
          ctx.persist();
        }
        continue;
      }

      if (entity instanceof Patrol) {
        const centreX = entity.bounds.x + entity.bounds.w / 2;

        if (attack && rectsOverlap(attack, entity.bounds)) {
          if (entity.hit(this.player.x)) ctx.audio.play('sword', 0.6);
          continue;
        }

        if (!rectsOverlap(body, entity.bounds)) continue;

        // A falling player lands on the guard instead of taking the hit.
        const stomping = body.vy > 40 && body.y + body.h - entity.bounds.y < 10;
        if (stomping) {
          entity.hit(this.player.x);
          body.vy = -TUNING.jumpSpeed * 0.68;
          ctx.audio.play('land', 1.3);
        } else {
          this.player.damage(1, centreX);
        }
        continue;
      }

      if (entity === this.exitDoor && this.exitDoor) {
        this.exitDoor.open = true;
        if (rectsOverlap(body, this.exitDoor.bounds) && this.phase === 'playing') {
          this.complete(ctx);
        }
      }
    }
  }

  private complete(ctx: GameContext): void {
    this.phase = 'complete';
    ctx.audio.play('door');
    const key = this.level.id;
    const best = ctx.save.bestTimes[key];
    if (best === undefined || this.elapsed < best) ctx.save.bestTimes[key] = this.elapsed;
    ctx.persist();
  }

  private restart(): void {
    this.player.respawn();
    this.spawnEntities();
    this.phase = 'playing';
    this.elapsed = 0;
    this.damageFlash = 0;
    this.fade = 1;
    this.fadeTarget = 0;
    this.camera.snapTo(this.cameraTarget());
  }

  private cameraTarget() {
    return {
      x: this.player.x,
      y: this.player.y,
      facing: this.player.facing,
      onGround: this.player.body.onGround,
    };
  }

  private drawVignette(renderer: Renderer): void {
    renderer.verticalGradient(0, 0, renderer.width, 34, [
      [0, withAlpha(PALETTE.ink, 0.35)],
      [1, withAlpha(PALETTE.ink, 0)],
    ]);
    renderer.verticalGradient(0, renderer.height - 38, renderer.width, 38, [
      [0, withAlpha(PALETTE.ink, 0)],
      [1, withAlpha(PALETTE.ink, 0.38)],
    ]);
  }

  private drawOverlay(renderer: Renderer, title: string, subtitle: string): void {
    renderer.flash(PALETTE.ink, 0.55);
    renderer.text(title, renderer.width / 2, renderer.height / 2 - 8, {
      size: 20,
      align: 'center',
      baseline: 'middle',
      color: PALETTE.paper,
      tracking: 6,
    });
    renderer.text(subtitle, renderer.width / 2, renderer.height / 2 + 14, {
      size: 8,
      align: 'center',
      baseline: 'middle',
      color: withAlpha(PALETTE.lightSoft, 0.8),
      tracking: 1,
      weight: 500,
    });
  }
}

function approachValue(current: number, target: number, maxDelta: number): number {
  if (current < target) return Math.min(current + maxDelta, target);
  if (current > target) return Math.max(current - maxDelta, target);
  return target;
}

function hashSeed(value: string): number {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}
