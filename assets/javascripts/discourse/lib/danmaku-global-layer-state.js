import { ajax } from "discourse/lib/ajax";
import { danmakuLayerCanRun } from "./danmaku-activation-policy";
import {
	DANMAKU_AREA_OPTIONS,
	DANMAKU_DEFAULT_VIEWER_SETTINGS,
	DANMAKU_USER_SETTINGS_CHANGED_EVENT,
	DANMAKU_USER_SETTINGS_KEY,
	defaultViewerSettings,
	loadViewerSettingsFromStorage,
	normalizeDanmakuArea,
	normalizeDanmakuOpacity,
	normalizeViewerSettings,
	persistViewerSettingsToStorage,
} from "./danmaku-viewer-settings-store";

export {
	DANMAKU_AREA_OPTIONS,
	DANMAKU_DEFAULT_VIEWER_SETTINGS,
	DANMAKU_USER_SETTINGS_CHANGED_EVENT,
	DANMAKU_USER_SETTINGS_KEY,
	defaultViewerSettings,
	loadViewerSettingsFromStorage,
	normalizeDanmakuArea,
	normalizeDanmakuOpacity,
	normalizeViewerSettings,
	persistViewerSettingsToStorage,
};

export const DANMAKU_GLOBAL_CHANNEL = "/danmaku/global";
export const DANMAKU_GLOBAL_ITEMS_PATH = "/danmaku/items/global";
export const DANMAKU_ITEM_PATH_PREFIX = "/danmaku/items/";
export const DANMAKU_SEEN_ITEMS_KEY = "discourse-danmaku-seen-items-v1";

const DANMAKU_SEEN_ITEM_LIMIT = 500;

function positiveInteger(value) {
	const parsed = Number.parseInt(value, 10);
	return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function pathWithQuery(path, params) {
	const query = Object.entries(params)
		.map(
			([key, value]) =>
				`${encodeURIComponent(key)}=${encodeURIComponent(value)}`,
		)
		.join("&");

	return `${path}?${query}`;
}

function itemId(item) {
	return positiveInteger(item?.id);
}

function isVisibilityError(error) {
	const status = error?.jqXHR?.status || error?.status;
	return status === 403 || status === 404;
}

export default class DanmakuGlobalLayerState {
	constructor(options = {}) {
		this.ajax = options.ajax || ajax;
		this.messageBus = options.messageBus;
		this.siteSettings = options.siteSettings || {};
		this.capabilities = options.capabilities || {};
		this.document = options.documentObj || globalThis.document;
		this.localStorage = options.localStorage || globalThis.localStorage;
		this.onChange = options.onChange || (() => {});

		this.itemsById = new Map();
		this.items = [];
		this.active = false;
		this.started = false;
		this.subscribed = false;
		this.visibilityListening = false;
		this.fetchingGlobal = false;
		this.pendingGlobalFetch = false;
		this.fetchingItemIds = new Set();
		this.pendingItemFetchIds = new Set();
		this.activationRevision = 0;
		this.loadedInitialGlobalItems = false;
		this.lastKnownGlobalItemId = 0;
		this.lastFetchError = null;
		this.lastLocalSettingsError = null;
		this.settings = this.loadViewerSettings();

		this.handleMessage = this.handleMessage.bind(this);
		this.handleVisibilityChange = this.handleVisibilityChange.bind(this);
		this.handleViewerSettingsChanged =
			this.handleViewerSettingsChanged.bind(this);
	}

	start() {
		if (this.started) {
			return this.refreshActivation();
		}

		this.started = true;
		this.addVisibilityListener();
		this.addViewerSettingsListener();

		return this.refreshActivation();
	}

	stop() {
		this.started = false;
		this.activationRevision += 1;
		this.unsubscribe();
		this.removeVisibilityListener();
		this.removeViewerSettingsListener();
		this.setActive(false);
	}

	addVisibilityListener() {
		if (this.visibilityListening || !this.document?.addEventListener) {
			return;
		}

		this.document.addEventListener(
			"visibilitychange",
			this.handleVisibilityChange,
		);
		this.visibilityListening = true;
	}

	removeVisibilityListener() {
		if (!this.visibilityListening || !this.document?.removeEventListener) {
			this.visibilityListening = false;
			return;
		}

		this.document.removeEventListener(
			"visibilitychange",
			this.handleVisibilityChange,
		);
		this.visibilityListening = false;
	}

	addViewerSettingsListener() {
		globalThis.window?.addEventListener?.(
			DANMAKU_USER_SETTINGS_CHANGED_EVENT,
			this.handleViewerSettingsChanged,
		);
	}

	removeViewerSettingsListener() {
		globalThis.window?.removeEventListener?.(
			DANMAKU_USER_SETTINGS_CHANGED_EVENT,
			this.handleViewerSettingsChanged,
		);
	}

	handleViewerSettingsChanged() {
		try {
			this.settings = loadViewerSettingsFromStorage(
				this.siteSettings,
				this.localStorage,
			);
		} catch (error) {
			this.handleLocalSettingsError(error);
			this.settings = defaultViewerSettings(this.siteSettings);
		}

		this.emitChange();
		this.refreshActivation();
	}

	refreshActivation() {
		if (!this.started || !this.canRun()) {
			this.unsubscribe();
			this.setActive(false);
			return Promise.resolve();
		}

		this.setActive(true);
		this.subscribe();
		return this.fetchGlobal();
	}

	canRun() {
		return danmakuLayerCanRun({
			siteSettings: this.siteSettings,
			capabilities: this.capabilities,
			documentObj: this.document,
			settings: this.settings,
		});
	}

	subscribe() {
		if (this.subscribed || !this.messageBus?.subscribe) {
			return;
		}

		this.messageBus.subscribe(DANMAKU_GLOBAL_CHANNEL, this.handleMessage);
		this.subscribed = true;
	}

	unsubscribe() {
		if (!this.subscribed || !this.messageBus?.unsubscribe) {
			this.subscribed = false;
			return;
		}

		this.messageBus.unsubscribe(DANMAKU_GLOBAL_CHANNEL, this.handleMessage);
		this.subscribed = false;
	}

	async fetchGlobal() {
		if (!this.active || !this.canRun()) {
			return;
		}

		if (this.fetchingGlobal) {
			this.pendingGlobalFetch = true;
			return;
		}

		this.pendingGlobalFetch = false;
		const fetchRevision = this.activationRevision;
		this.fetchingGlobal = true;

		try {
			const payload = await this.ajax(
				pathWithQuery(DANMAKU_GLOBAL_ITEMS_PATH, {
					after_id: this.lastSeenId(),
					limit: this.fetchLimit(),
				}),
			);

			if (
				this.active &&
				this.canRun() &&
				fetchRevision === this.activationRevision
			) {
				this.mergeFetchedGlobalItems(payload?.items || []);
			}
		} catch (error) {
			this.handleFetchError(error);
		} finally {
			this.fetchingGlobal = false;

			if (this.pendingGlobalFetch && this.active && this.canRun()) {
				this.pendingGlobalFetch = false;
				await this.fetchGlobal();
			} else {
				this.pendingGlobalFetch = false;
			}
		}
	}

	handleFetchError(error) {
		this.lastFetchError = error;
	}

	mergeFetchedGlobalItems(items) {
		this.rememberLatestItemId(items);

		if (!this.loadedInitialGlobalItems) {
			this.loadedInitialGlobalItems = true;
			this.mergeItems(this.initialReplayItems(items));
			this.rememberSeenItems(items);
			return;
		}

		this.mergeItems(items);
	}

	async fetchItem(id) {
		const danmakuId = positiveInteger(id);
		if (!this.active || !this.canRun() || !danmakuId) {
			return;
		}

		if (this.fetchingItemIds.has(danmakuId)) {
			this.pendingItemFetchIds.add(danmakuId);
			return;
		}

		const fetchRevision = this.activationRevision;
		this.fetchingItemIds.add(danmakuId);

		try {
			const payload = await this.ajax(
				`${DANMAKU_ITEM_PATH_PREFIX}${danmakuId}`,
			);
			const item = payload?.item;

			if (
				this.active &&
				this.canRun() &&
				fetchRevision === this.activationRevision &&
				itemId(item)
			) {
				this.rememberLatestItemId([item]);
				this.mergeItems([item]);
			}
		} catch (error) {
			if (
				this.active &&
				this.canRun() &&
				fetchRevision === this.activationRevision &&
				isVisibilityError(error)
			) {
				this.removeItem(danmakuId);
			}
		} finally {
			this.fetchingItemIds.delete(danmakuId);

			if (
				this.pendingItemFetchIds.delete(danmakuId) &&
				this.active &&
				this.canRun()
			) {
				await this.fetchItem(danmakuId);
			}
		}
	}

	async likeItem(id) {
		const danmakuId = positiveInteger(id);
		if (!danmakuId) {
			return null;
		}

		const payload = await this.ajax(
			`${DANMAKU_ITEM_PATH_PREFIX}${danmakuId}/like`,
			{
				type: "POST",
				method: "POST",
			},
		);
		const item = payload?.item || payload;

		if (itemId(item)) {
			this.rememberLatestItemId([item]);
			this.mergeItems([item]);
			return item;
		}

		return null;
	}

	async unlikeItem(id) {
		const danmakuId = positiveInteger(id);
		if (!danmakuId) {
			return null;
		}

		const payload = await this.ajax(
			`${DANMAKU_ITEM_PATH_PREFIX}${danmakuId}/like`,
			{
				type: "DELETE",
				method: "DELETE",
			},
		);
		const item = payload?.item || payload;

		if (itemId(item)) {
			this.rememberLatestItemId([item]);
			this.mergeItems([item]);
			return item;
		}

		return null;
	}

	toggleLikeItem(item) {
		if (item?.liked_by_current_user) {
			return this.unlikeItem(item.id);
		}

		return this.likeItem(item?.id);
	}

	handleMessage(payload) {
		const danmakuId = positiveInteger(payload?.danmaku_id);

		if (
			!danmakuId ||
			(danmakuId <= this.lastKnownGlobalItemId &&
				!this.itemsById.has(danmakuId))
		) {
			return;
		}

		return this.fetchItem(danmakuId);
	}

	handleVisibilityChange() {
		return this.refreshActivation();
	}

	mergeItems(items) {
		this.rememberLatestItemId(items);
		this.rememberSeenItems(items);

		for (const item of items) {
			const id = itemId(item);
			if (id) {
				this.itemsById.set(id, item);
			}
		}

		this.trimItems();
	}

	removeItem(id) {
		this.itemsById.delete(id);
		this.trimItems();
	}

	trimItems() {
		const sortedItems = Array.from(this.itemsById.values()).sort(
			(left, right) => left.id - right.id,
		);
		const visibleItems = sortedItems.slice(-this.maxVisibleItems());

		this.itemsById = new Map(visibleItems.map((item) => [item.id, item]));
		this.items = visibleItems;
		this.emitChange();
	}

	setActive(active) {
		if (this.active === active) {
			return;
		}

		this.active = active;
		this.activationRevision += 1;
		this.emitChange();
	}

	updateSettings(settings) {
		this.settings = normalizeViewerSettings(
			{ ...this.settings, ...settings },
			this.siteSettings,
		);
		this.persistViewerSettings();
		this.emitChange();

		return this.refreshActivation();
	}

	emitChange() {
		this.onChange({
			active: this.active,
			items: this.items,
			settings: this.settings,
		});
	}

	lastSeenId() {
		return this.lastKnownGlobalItemId;
	}

	rememberLatestItemId(items) {
		for (const item of items) {
			const id = itemId(item);

			if (id) {
				this.lastKnownGlobalItemId = Math.max(this.lastKnownGlobalItemId, id);
			}
		}
	}

	initialReplayItems(items) {
		const replayCount = this.initialReplayCount();

		if (replayCount === 0) {
			return [];
		}

		const seenItemIds = this.loadSeenItemIds();

		return items
			.filter((item) => !seenItemIds.has(itemId(item)))
			.slice(-replayCount);
	}

	loadSeenItemIds() {
		if (!this.localStorage?.getItem) {
			return new Set();
		}

		try {
			const rawIds = JSON.parse(
				this.localStorage.getItem(DANMAKU_SEEN_ITEMS_KEY) || "[]",
			);

			return new Set(
				Array.isArray(rawIds)
					? rawIds.map((id) => positiveInteger(id)).filter(Boolean)
					: [],
			);
		} catch (error) {
			this.handleLocalSettingsError(error);
			return new Set();
		}
	}

	rememberSeenItems(items) {
		if (!this.localStorage?.setItem || !items.length) {
			return;
		}

		const seenItemIds = this.loadSeenItemIds();

		for (const item of items) {
			const id = itemId(item);

			if (id) {
				seenItemIds.add(id);
			}
		}

		const ids = Array.from(seenItemIds)
			.sort((left, right) => left - right)
			.slice(-DANMAKU_SEEN_ITEM_LIMIT);

		this.localStorage.setItem(DANMAKU_SEEN_ITEMS_KEY, JSON.stringify(ids));
	}

	fetchLimit() {
		return this.settingLimit(
			"danmaku_initial_fetch_limit",
			this.maxVisibleItems(),
		);
	}

	initialReplayCount() {
		const parsed = Number.parseInt(
			this.siteSettings.danmaku_initial_replay_count,
			10,
		);

		if (!Number.isFinite(parsed)) {
			return 3;
		}

		return Math.min(Math.max(parsed, 0), this.maxVisibleItems());
	}

	maxVisibleItems() {
		return this.settingLimit(
			"danmaku_max_visible_items",
			this.siteSettings.danmaku_initial_fetch_limit,
		);
	}

	settingLimit(settingName, fallback) {
		return (
			positiveInteger(this.siteSettings[settingName]) ||
			positiveInteger(fallback) ||
			1
		);
	}

	isMobileDevice() {
		return Boolean(
			this.capabilities.isMobileDevice || this.capabilities.isMobile,
		);
	}

	loadViewerSettings() {
		try {
			return loadViewerSettingsFromStorage(
				this.siteSettings,
				this.localStorage,
			);
		} catch (error) {
			this.handleLocalSettingsError(error);
			return defaultViewerSettings(this.siteSettings);
		}
	}

	persistViewerSettings() {
		persistViewerSettingsToStorage(this.settings, this.localStorage, false);
	}

	handleLocalSettingsError(error) {
		this.lastLocalSettingsError = error;
	}
}
