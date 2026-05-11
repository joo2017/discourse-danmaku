export function danmakuLayerCanRun({
	siteSettings,
	capabilities,
	documentObj,
	settings,
} = {}) {
	if (!siteSettings?.danmaku_enabled) {
		return false;
	}

	if (
		(capabilities?.isMobileDevice || capabilities?.isMobile) &&
		!siteSettings.danmaku_mobile_enabled
	) {
		return false;
	}

	if (
		siteSettings?.danmaku_allow_reader_close !== false &&
		settings?.enabled === false
	) {
		return false;
	}

	return !documentObj?.hidden;
}
