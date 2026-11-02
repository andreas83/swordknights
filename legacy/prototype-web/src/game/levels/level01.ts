import type { LevelDefinition } from '../world';

/**
 * Level 01 - "The Sun Terrace".
 *
 * Authored as ASCII so the geometry stays readable and editable; see
 * `src/game/tiles.ts` for the legend. The vertical spacing is not arbitrary:
 * a 2-tile rise is a plain hop, a 3-tile rise needs a one-way platform step,
 * and a 4-tile rise is only clearable with a ledge grab. Those distances fall
 * straight out of the jump arc defined in `src/game/tuning.ts`, and
 * `tests/level01.test.ts` asserts they stay reachable if the tuning changes.
 *
 * Beat sheet, left to right:
 *   1. open terrace            - run and jump
 *   2. cistern with a ladder   - a safe failure that teaches climbing
 *   3. one-way step            - optional relic off the main path
 *   4. spike gap + 4-tile wall - the ledge-grab lesson
 *   5. upper terrace + guard   - the sword
 *   6. water basin             - a committed running jump
 *   7. platform stair          - second ledge grab, up to the exit
 */
export const LEVEL_01: LevelDefinition = {
  id: 'level-01',
  name: 'The Sun Terrace',
  mood: 0,
  rows: [
    '',
    '',
    '',
    '',
    '',
    '',
    '                                                                     t    D',
    '                                                               ################',
    '                                                               ################',
    '                                                               ################',
    '                                                               ################',
    '                                  t   p  *                  == ################',
    '  ::::                         ##############                  ################',
    '  ::::                  *      ##############            ==    ################',
    '  ::::                 ===     ##############        p *       ################',
    '  :@:: t      H                ###################~~###########################',
    ' ############ H  ############  ###################~~###########################',
    ' ############ H  ############  ###################~~###########################',
    ' ############ H  ############  ################################################',
    ' ############ H  ############^^################################################',
    ' ##############################################################################',
    ' ##############################################################################',
  ],
};
