import {
	clearComposerDanmakuSelection,
	composerDanmakuColorBase,
	composerDanmakuColorOpacity,
	composerDanmakuControlsAvailable,
	composerDanmakuEnabled,
	composerDanmakuMode,
	currentUserCanSendBasicDanmaku,
	currentUserCanUseDanmakuPremiumTools,
	DEFAULT_DANMAKU_COLOR,
	DEFAULT_DANMAKU_MODE,
	enableComposerDanmakuSelection,
	resolveDanmakuTargetPostId,
	updateComposerDanmakuColor,
	updateComposerDanmakuColorOpacity,
	updateComposerDanmakuMode,
} from "./danmaku-composer-state";

export const DANMAKU_COMPOSER_SERIALIZED_FIELDS = [
	["danmaku_enabled", "danmakuEnabled"],
	["danmaku_target_post_id", "danmakuTargetPostId"],
	["danmaku_mode", "danmakuMode"],
	["danmaku_color", "danmakuColor"],
];

export function canShowDanmakuEntryPoint(siteSettings) {
	return composerDanmakuControlsAvailable(siteSettings);
}

export function canSendDanmakuDraft(currentUser, siteSettings) {
	return currentUserCanSendBasicDanmaku(currentUser, siteSettings);
}

export function needsDanmakuLogin(siteSettings, currentUser) {
	return canShowDanmakuEntryPoint(siteSettings) && !currentUser;
}

export function isDanmakuDraftLocked(siteSettings, currentUser) {
	return (
		canShowDanmakuEntryPoint(siteSettings) && !canSendDanmakuDraft(currentUser, siteSettings)
	);
}

export function isDanmakuDraftEnabled(
	composerModel,
	siteSettings,
	currentUser,
) {
	return Boolean(
		canShowDanmakuEntryPoint(siteSettings) &&
			canSendDanmakuDraft(currentUser, siteSettings) &&
			composerDanmakuEnabled(composerModel),
	);
}

export function enableDanmakuDraft(composerModel, options = {}) {
	enableComposerDanmakuSelection(composerModel, {
		targetPostId: resolveDanmakuTargetPostId(composerModel),
		mode: options.mode || DEFAULT_DANMAKU_MODE,
		color: options.color || DEFAULT_DANMAKU_COLOR,
	});
}

export function disableDanmakuDraft(composerModel) {
	clearComposerDanmakuSelection(composerModel);
}

export function danmakuDraftToolsVisible(
	composerModel,
	siteSettings,
	currentUser,
) {
	return isDanmakuDraftEnabled(composerModel, siteSettings, currentUser);
}

export function danmakuDraftMode(composerModel) {
	return composerDanmakuMode(composerModel);
}

export function danmakuDraftColor(composerModel) {
	return composerDanmakuColorBase(composerModel);
}

export function danmakuDraftColorOpacity(composerModel) {
	return composerDanmakuColorOpacity(composerModel);
}

export function updateDanmakuDraftMode(composerModel, mode) {
	updateComposerDanmakuMode(composerModel, mode);
}

export function updateDanmakuDraftColor(composerModel, color) {
	updateComposerDanmakuColor(composerModel, color);
}

export function updateDanmakuDraftColorOpacity(composerModel, opacity) {
	updateComposerDanmakuColorOpacity(composerModel, opacity);
}
