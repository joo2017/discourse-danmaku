import {
	DANMAKU_AREA_BY_PERCENT,
	DANMAKU_AREA_IDS,
	DANMAKU_AREA_OPTIONS,
	DANMAKU_DEFAULT_VIEWER_SETTINGS,
} from "./danmaku-options";

export { DANMAKU_AREA_OPTIONS, DANMAKU_DEFAULT_VIEWER_SETTINGS };

export const DANMAKU_USER_SETTINGS_KEY = "discourse-danmaku-settings-v1";
export const DANMAKU_USER_SETTINGS_CHANGED_EVENT =
	"discourse-danmaku-settings-changed";

function clampedInteger(value, fallback, min, max) {
	const parsed = Number.parseInt(value, 10);
	const safeValue = Number.isFinite(parsed) ? parsed : fallback;

	return Math.min(Math.max(safeValue, min), max);
}

export function normalizeDanmakuArea(
	area,
	fallback = DANMAKU_DEFAULT_VIEWER_SETTINGS.area,
) {
	if (DANMAKU_AREA_IDS.includes(area)) {
		return area;
	}

	const numericArea = Number.parseInt(area, 10);
	if (DANMAKU_AREA_BY_PERCENT.has(numericArea)) {
		return DANMAKU_AREA_BY_PERCENT.get(numericArea);
	}

	return DANMAKU_AREA_IDS.includes(fallback)
		? fallback
		: DANMAKU_DEFAULT_VIEWER_SETTINGS.area;
}

export function normalizeDanmakuOpacity(
	opacity,
	fallback = DANMAKU_DEFAULT_VIEWER_SETTINGS.opacity,
) {
	return clampedInteger(opacity, fallback, 10, 100);
}

export function defaultViewerSettings(siteSettings = {}) {
	return {
		enabled: DANMAKU_DEFAULT_VIEWER_SETTINGS.enabled,
		opacity: normalizeDanmakuOpacity(siteSettings.danmaku_default_opacity),
		area: normalizeDanmakuArea(siteSettings.danmaku_default_area),
	};
}

export function normalizeViewerSettings(rawSettings = {}, siteSettings = {}) {
	const defaults = defaultViewerSettings(siteSettings);
	const readerCanClose = siteSettings.danmaku_allow_reader_close !== false;

	return {
		enabled: readerCanClose && rawSettings.enabled === false ? false : defaults.enabled,
		opacity: normalizeDanmakuOpacity(rawSettings.opacity, defaults.opacity),
		area: normalizeDanmakuArea(rawSettings.area, defaults.area),
	};
}

export function loadViewerSettingsFromStorage(
	siteSettings = {},
	localStorage = globalThis.localStorage,
) {
	if (!localStorage?.getItem) {
		return defaultViewerSettings(siteSettings);
	}

	const settings = JSON.parse(
		localStorage.getItem(DANMAKU_USER_SETTINGS_KEY) || "{}",
	);
	return normalizeViewerSettings(settings, siteSettings);
}

export function persistViewerSettingsToStorage(
	settings,
	localStorage = globalThis.localStorage,
	notify = true,
) {
	if (!localStorage?.setItem) {
		return;
	}

	localStorage.setItem(DANMAKU_USER_SETTINGS_KEY, JSON.stringify(settings));
	if (notify) {
		globalThis.window?.dispatchEvent?.(
			new Event(DANMAKU_USER_SETTINGS_CHANGED_EVENT),
		);
	}
}
