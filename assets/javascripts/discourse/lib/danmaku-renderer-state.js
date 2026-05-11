import { DANMAKU_AREA_FACTORS, DANMAKU_HEX_COLOR_REGEXP, DANMAKU_MODE_IDS } from "./danmaku-options";
import { sourcePostNumber } from "./danmaku-native-report";

const DANMAKU_DEFAULT_VIEWPORT_HEIGHT = 720;
const DANMAKU_MIN_TRACK_COUNT = 1;
const DANMAKU_TRACK_ROW_HEIGHT = 36;
const DANMAKU_SAFE_BLOCK_START = 72;
const DANMAKU_SAFE_BLOCK_END = 16;
const DANMAKU_SCROLL_DURATION_RANGE = [6, 10];
const DANMAKU_FIXED_DURATION = 4;

function positiveInteger(value) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function nonNegativeInteger(value) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

function normalizeMode(mode) {
  return DANMAKU_MODE_IDS.includes(mode) ? mode : "scroll";
}

function normalizeColor(color) {
  return DANMAKU_HEX_COLOR_REGEXP.test(color || "") ? color.toLowerCase() : null;
}

function availableTracks(area, viewportHeight) {
  const areaFactor = DANMAKU_AREA_FACTORS.get(area) || DANMAKU_AREA_FACTORS.get("full");
  const viewportBlockSize = positiveInteger(viewportHeight) || DANMAKU_DEFAULT_VIEWPORT_HEIGHT;
  const availableBlockSize = Math.max(
    DANMAKU_TRACK_ROW_HEIGHT,
    Math.floor(viewportBlockSize * areaFactor) - DANMAKU_SAFE_BLOCK_START - DANMAKU_SAFE_BLOCK_END
  );

  return Math.max(DANMAKU_MIN_TRACK_COUNT, Math.floor(availableBlockSize / DANMAKU_TRACK_ROW_HEIGHT));
}

function itemSourceUrl(item) {
  return item?.source_post_url || item?.source_topic_url || null;
}

function itemSourceLabel(item) {
  return item?.source_topic_title || item?.source_hint || null;
}

function stableItemRatio(item) {
  const id = positiveInteger(item?.id);

  if (!id) {
    return 0.5;
  }

  const hash = Math.imul(id, 2654435761) >>> 0;

  return (hash % 1000) / 999;
}

function durationInRange([minimum, maximum], ratio) {
  return Math.round((minimum + (maximum - minimum) * ratio) * 100) / 100;
}

function trackPosition(track) {
  return track * DANMAKU_TRACK_ROW_HEIGHT;
}

function randomTrack(tracks, random = Math.random) {
  const safeTracks = positiveInteger(tracks) || 1;
  const value = typeof random === "function" ? random() : Math.random();

  return Math.max(0, Math.min(safeTracks - 1, Math.floor(value * safeTracks)));
}

function trackGroup(mode) {
  return mode === "bottom" ? "bottom" : "top";
}

function itemAssignmentKey(item) {
  const id = positiveInteger(item?.id);

  return id ? `${id}` : null;
}

function assignedTrackForItem(item, mode, tracks, occupiedTracks, trackAssignments, random) {
  const key = itemAssignmentKey(item);
  const group = trackGroup(mode);
  const assigned = key ? trackAssignments?.get?.(key) : null;

  if (
    assigned?.group === group &&
    Number.isInteger(assigned.track) &&
    assigned.track >= 0 &&
    assigned.track < tracks &&
    !occupiedTracks.has(assigned.track)
  ) {
    occupiedTracks.add(assigned.track);

    return assigned.track;
  }

  const preferredTrack = randomTrack(tracks, random);

  for (let offset = 0; offset < tracks; offset++) {
    const track = (preferredTrack + offset) % tracks;

    if (!occupiedTracks.has(track)) {
      occupiedTracks.add(track);
      if (key) {
        trackAssignments?.set?.(key, { group, track });
      }

      return track;
    }
  }

  if (key) {
    trackAssignments?.set?.(key, { group, track: preferredTrack });
  }

  return preferredTrack;
}

function truncateDisplayText(value, maxLength) {
  const text = value?.toString?.() || "";
  const limit = nonNegativeInteger(maxLength);

  if (!limit || text.length <= limit) {
    return text;
  }

  if (limit === 1) {
    return "…";
  }

  return `${text.slice(0, limit - 1)}…`;
}

export function currentRouteTopicId(router) {
  const route = router?.currentRoute;
  const topic = route?.attributes?.topic || route?.parent?.attributes?.topic;
  const routeTopicId = positiveInteger(topic?.id || route?.attributes?.id || route?.params?.topic_id);

  if (routeTopicId) {
    return routeTopicId;
  }

  const pathTopicId = globalThis.location?.pathname?.match?.(/^\/t\/(?:[^/]+\/)?(\d+)(?:\/|$)/)?.[1];

  return positiveInteger(pathTopicId);
}

export function replyActionForItem(item, currentTopicId) {
  const topicId = positiveInteger(item?.topic_id);
  const sourceUrl = itemSourceUrl(item);
  const postId = positiveInteger(item?.source_post_id);
  const postNumber = sourcePostNumber(item);

  if (topicId && topicId === positiveInteger(currentTopicId)) {
    return { type: "composer", postId, postNumber, topicId };
  }

  if (topicId && sourceUrl) {
    return { type: "navigate", postId, postNumber, topicId, url: sourceUrl };
  }

  if (topicId) {
    return { type: "composer", postId, postNumber, topicId };
  }

  return { type: "none" };
}

export function reducedMotionPreferred(windowObj = globalThis.window) {
  try {
    return Boolean(windowObj?.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches);
  } catch {
    return false;
  }
}

export function buildRenderedDanmakuItems(items, options = {}) {
  const sourceItems = Array.isArray(items) ? items : [];
  const tracks = availableTracks(options.area, options.viewportHeight);
  const maxVisibleItems = positiveInteger(options.maxVisibleItems) || sourceItems.length || 1;
  const renderedItemLimit = Math.min(sourceItems.length, maxVisibleItems, tracks);
  const currentUserId = positiveInteger(options.currentUserId);
  const occupiedTracksByGroup = new Map();

  return sourceItems.slice(-renderedItemLimit).map((item) => {
    const mode = normalizeMode(item?.mode);
    const group = trackGroup(mode);
    let occupiedTracks = occupiedTracksByGroup.get(group);

    if (!occupiedTracks) {
      occupiedTracks = new Set();
      occupiedTracksByGroup.set(group, occupiedTracks);
    }

    const track = assignedTrackForItem(item, mode, tracks, occupiedTracks, options.trackAssignments, options.random);
    const usernameDisplayLimit = nonNegativeInteger(options.maxUsernameLength);

    return {
      id: item.id,
      item,
      mode,
      track,
      trackPosition: trackPosition(track),
      trackCount: tracks,
      scrollDuration: durationInRange(DANMAKU_SCROLL_DURATION_RANGE, stableItemRatio(item)),
      fixedDuration: DANMAKU_FIXED_DURATION,
      displayBody: truncateDisplayText(item?.body, options.maxTextLength),
      displayUsername: truncateDisplayText(item?.username, usernameDisplayLimit),
      color: normalizeColor(item.color),
      sourceUrl: itemSourceUrl(item),
      sourceLabel: itemSourceLabel(item),
      ownsItem: currentUserId && positiveInteger(item.user_id) === currentUserId,
      reducedMotion: Boolean(options.reducedMotion),
    };
  });
}
