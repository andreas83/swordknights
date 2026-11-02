import { Game } from './core/game';
import { PlayScene } from './scenes/playscene';
import { LEVEL_01 } from './game/levels/level01';

const canvas = document.querySelector<HTMLCanvasElement>('#stage');
if (!canvas) throw new Error('#stage canvas missing');

const game = new Game(canvas);
game.setScene(new PlayScene(LEVEL_01, game));
game.start();

document.getElementById('boot')?.classList.add('is-hidden');
setTimeout(() => document.getElementById('boot')?.remove(), 400);

// Keep the viewport from bouncing when the virtual keyboard or URL bar moves.
window.addEventListener('touchmove', (e) => e.preventDefault(), { passive: false });

if (import.meta.hot) {
  import.meta.hot.dispose(() => game.dispose());
}
