/**
 * Persistent progress. Wrapped in try/catch because private browsing and
 * WKWebView can both make localStorage throw rather than return null.
 */

const KEY = 'swordknights.save.v1';

export interface SaveData {
  levelId: string;
  deaths: number;
  relics: Record<string, number>;
  bestTimes: Record<string, number>;
  muted: boolean;
}

const DEFAULT_SAVE: SaveData = {
  levelId: 'level-01',
  deaths: 0,
  relics: {},
  bestTimes: {},
  muted: false,
};

export function loadSave(): SaveData {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return { ...DEFAULT_SAVE };
    const parsed = JSON.parse(raw) as Partial<SaveData>;
    return { ...DEFAULT_SAVE, ...parsed, relics: { ...parsed.relics }, bestTimes: { ...parsed.bestTimes } };
  } catch {
    return { ...DEFAULT_SAVE };
  }
}

export function writeSave(data: SaveData): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(data));
  } catch {
    /* storage unavailable — progress is simply not persisted */
  }
}
