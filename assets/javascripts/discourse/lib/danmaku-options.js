export const DEFAULT_DANMAKU_MODE = "scroll";
export const DEFAULT_DANMAKU_COLOR = "#ffeb3b";
export const DEFAULT_DANMAKU_COLOR_OPACITY = 100;

export const DANMAKU_MODE_OPTIONS = [
  { id: "scroll", labelKey: "danmaku.composer.modes.scroll" },
  { id: "top", labelKey: "danmaku.composer.modes.top" },
  { id: "bottom", labelKey: "danmaku.composer.modes.bottom" },
];

export const DANMAKU_AREA_OPTIONS = [
  { id: "full", labelKey: "danmaku.viewer.area_options.full", factor: 1 },
  { id: "half", labelKey: "danmaku.viewer.area_options.half", factor: 0.5 },
  { id: "quarter", labelKey: "danmaku.viewer.area_options.quarter", factor: 0.25 },
];

export const DANMAKU_DEFAULT_VIEWER_SETTINGS = Object.freeze({
	enabled: true,
	opacity: 45,
	area: "quarter",
});

export const DANMAKU_MODE_IDS = DANMAKU_MODE_OPTIONS.map((mode) => mode.id);
export const DANMAKU_AREA_IDS = DANMAKU_AREA_OPTIONS.map((area) => area.id);
export const DANMAKU_AREA_FACTORS = new Map(DANMAKU_AREA_OPTIONS.map((area) => [area.id, area.factor]));
export const DANMAKU_AREA_BY_PERCENT = new Map([
  [100, "full"],
  [50, "half"],
  [25, "quarter"],
]);

export const DANMAKU_HEX_COLOR_REGEXP = /^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i;
