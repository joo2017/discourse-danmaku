import {
  DANMAKU_HEX_COLOR_REGEXP,
  DANMAKU_MODE_IDS,
  DANMAKU_MODE_OPTIONS,
  DEFAULT_DANMAKU_COLOR,
  DEFAULT_DANMAKU_COLOR_OPACITY,
  DEFAULT_DANMAKU_MODE,
} from "./danmaku-options";

export { DANMAKU_MODE_OPTIONS, DEFAULT_DANMAKU_COLOR, DEFAULT_DANMAKU_COLOR_OPACITY, DEFAULT_DANMAKU_MODE };

function writeComposerProperties(composerModel, properties) {
  if (!composerModel) {
    return;
  }

  if (typeof composerModel.setProperties === "function") {
    composerModel.setProperties(properties);
    return;
  }

  Object.assign(composerModel, properties);
}

function readComposerProperty(composerModel, propertyName) {
  if (!composerModel) {
    return undefined;
  }

  if (typeof composerModel.get === "function") {
    return composerModel.get(propertyName);
  }

  return composerModel[propertyName];
}

function positiveInteger(value) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
}

export function normalizeDanmakuMode(mode) {
  return DANMAKU_MODE_IDS.includes(mode) ? mode : DEFAULT_DANMAKU_MODE;
}

export function normalizeDanmakuColor(color) {
  return DANMAKU_HEX_COLOR_REGEXP.test(color || "") ? color.toLowerCase() : DEFAULT_DANMAKU_COLOR;
}

export function normalizeDanmakuColorOpacity(opacity) {
  const parsed = Number.parseInt(opacity, 10);

  return Number.isFinite(parsed) ? Math.min(Math.max(parsed, 10), 100) : DEFAULT_DANMAKU_COLOR_OPACITY;
}

export function danmakuColorBase(color) {
  return normalizeDanmakuColor(color).slice(0, 7);
}

export function danmakuColorOpacity(color) {
  const normalizedColor = normalizeDanmakuColor(color);

  if (normalizedColor.length !== 9) {
    return DEFAULT_DANMAKU_COLOR_OPACITY;
  }

  return normalizeDanmakuColorOpacity(Math.round((Number.parseInt(normalizedColor.slice(7, 9), 16) / 255) * 100));
}

export function composeDanmakuColor(baseColor, opacity = DEFAULT_DANMAKU_COLOR_OPACITY) {
  const normalizedBaseColor = danmakuColorBase(baseColor);
  const normalizedOpacity = normalizeDanmakuColorOpacity(opacity);

  if (normalizedOpacity >= 100) {
    return normalizedBaseColor;
  }

  const alpha = Math.round((normalizedOpacity / 100) * 255)
    .toString(16)
    .padStart(2, "0");

  return `${normalizedBaseColor}${alpha}`;
}


export function currentUserCanSendBasicDanmaku(currentUser, siteSettings) {
  if (!currentUser) {
    return false;
  }

  return Boolean(
    siteSettings?.danmaku_allow_basic_users ||
      currentUserCanUseDanmakuPremiumTools(currentUser),
  );
}

export function currentUserCanUseDanmakuPremiumTools(currentUser) {
  if (!currentUser) {
    return false;
  }

  if (typeof currentUser.can_use_danmaku_premium_tools !== "undefined") {
    return currentUser.can_use_danmaku_premium_tools === true;
  }

  if (typeof currentUser.canUseDanmakuPremiumTools !== "undefined") {
    return currentUser.canUseDanmakuPremiumTools === true;
  }

  return false;
}

export function composerDanmakuControlsAvailable(siteSettings) {
  return Boolean(siteSettings?.danmaku_enabled);
}

export function resolveDanmakuTargetPostId(composerModel) {
	// v1 only accepts an explicit transient composer field. It deliberately does
	// not probe reply state, post-stream DOM, or other private composer internals.
  return positiveInteger(readComposerProperty(composerModel, "danmakuTargetPostId"));
}

export function clearComposerDanmakuSelection(composerModel) {
  writeComposerProperties(composerModel, {
    danmakuEnabled: undefined,
    danmakuTargetPostId: undefined,
    danmakuMode: undefined,
    danmakuColor: undefined,
  });
}

export function enableComposerDanmakuSelection(composerModel, options = {}) {
  writeComposerProperties(composerModel, {
    danmakuEnabled: true,
    danmakuTargetPostId: positiveInteger(options.targetPostId),
    danmakuMode: normalizeDanmakuMode(options.mode),
    danmakuColor: normalizeDanmakuColor(options.color),
  });
}

export function updateComposerDanmakuMode(composerModel, mode) {
  if (readComposerProperty(composerModel, "danmakuEnabled") !== true) {
    return;
  }

  writeComposerProperties(composerModel, {
    danmakuMode: normalizeDanmakuMode(mode),
  });
}

export function updateComposerDanmakuColor(composerModel, color) {
  if (readComposerProperty(composerModel, "danmakuEnabled") !== true) {
    return;
  }

  writeComposerProperties(composerModel, {
    danmakuColor: composeDanmakuColor(color, composerDanmakuColorOpacity(composerModel)),
  });
}

export function updateComposerDanmakuColorOpacity(composerModel, opacity) {
  if (readComposerProperty(composerModel, "danmakuEnabled") !== true) {
    return;
  }

  writeComposerProperties(composerModel, {
    danmakuColor: composeDanmakuColor(composerDanmakuColorBase(composerModel), opacity),
  });
}

export function composerDanmakuEnabled(composerModel) {
  return readComposerProperty(composerModel, "danmakuEnabled") === true;
}

export function composerDanmakuMode(composerModel) {
  return normalizeDanmakuMode(readComposerProperty(composerModel, "danmakuMode"));
}

export function composerDanmakuColor(composerModel) {
  return normalizeDanmakuColor(readComposerProperty(composerModel, "danmakuColor"));
}

export function composerDanmakuColorBase(composerModel) {
  return danmakuColorBase(readComposerProperty(composerModel, "danmakuColor"));
}

export function composerDanmakuColorOpacity(composerModel) {
  return danmakuColorOpacity(readComposerProperty(composerModel, "danmakuColor"));
}
