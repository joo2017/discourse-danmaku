import DanmakuGlobalLayerState, {
  DANMAKU_GLOBAL_CHANNEL,
  DANMAKU_GLOBAL_ITEMS_PATH,
  DANMAKU_ITEM_PATH_PREFIX,
  DANMAKU_SEEN_ITEMS_KEY,
  DANMAKU_USER_SETTINGS_KEY,
  loadViewerSettingsFromStorage,
  normalizeViewerSettings,
  persistViewerSettingsToStorage,
} from "discourse/plugins/discourse-danmaku/discourse/lib/danmaku-global-layer-state";
import {
  openNativeReportByPostNumber,
  sourcePostNumber,
} from "discourse/plugins/discourse-danmaku/discourse/lib/danmaku-native-report";
import {
  buildRenderedDanmakuItems,
  currentRouteTopicId,
  reducedMotionPreferred,
  replyActionForItem,
} from "discourse/plugins/discourse-danmaku/discourse/lib/danmaku-renderer-state";
import { module, test } from "qunit";

function fakeDocument(hidden = false) {
  const listeners = new Map();

  return {
    hidden,
    addEventListener(name, callback) {
      if (!listeners.has(name)) {
        listeners.set(name, new Set());
      }

      listeners.get(name).add(callback);
    },
    removeEventListener(name, callback) {
      listeners.get(name)?.delete(callback);

      if (listeners.get(name)?.size === 0) {
        listeners.delete(name);
      }
    },
    listenerCount(name) {
      if (name) {
        return listeners.get(name)?.size || 0;
      }

      return Array.from(listeners.values()).reduce((count, callbacks) => count + callbacks.size, 0);
    },
    async trigger(name) {
      const callbacks = Array.from(listeners.get(name) || []);

      for (const callback of callbacks) {
        await callback();
      }
    },
  };
}

function fakeMessageBus() {
  const listeners = new Map();

  return {
    subscriptions: [],
    unsubscriptions: [],
    subscribe(channel, callback) {
      this.subscriptions.push({ channel, callback });
      if (!listeners.has(channel)) {
        listeners.set(channel, new Set());
      }

      listeners.get(channel).add(callback);
    },
    unsubscribe(channel, callback) {
      this.unsubscriptions.push({ channel, callback });
      listeners.get(channel)?.delete(callback);
    },
    listenerCount(channel) {
      return listeners.get(channel)?.size || 0;
    },
    async publish(channel, payload) {
      const callbacks = Array.from(listeners.get(channel) || []);

      for (const callback of callbacks) {
        await callback(payload);
      }
    },
  };
}

function fakeLocalStorage(value, extraValues = {}) {
  const values = new Map(Object.entries(extraValues));

  if (value !== undefined) {
    values.set(DANMAKU_USER_SETTINGS_KEY, value);
  }

  return {
    getItem(key) {
      return values.has(key) ? values.get(key) : null;
    },
    setItem(key, nextValue) {
      values.set(key, nextValue);
    },
    storedValue(key = DANMAKU_USER_SETTINGS_KEY) {
      return values.get(key);
    },
  };
}

function enabledSettings(overrides = {}) {
  return {
    danmaku_enabled: true,
    danmaku_mobile_enabled: true,
    danmaku_initial_fetch_limit: 3,
    danmaku_initial_replay_count: 3,
    danmaku_max_visible_items: 3,
    ...overrides,
  };
}

module("Unit | Lib | danmaku-global-layer-state", function () {
  test("does not fetch or subscribe when the site setting is disabled", async function (assert) {
    assert.expect(4);

    const documentObj = fakeDocument();
    const messageBus = fakeMessageBus();
    let requestCount = 0;

    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings({ danmaku_enabled: false }),
      messageBus,
      documentObj,
      ajax: async () => requestCount++,
    });

    await state.start();

    assert.false(state.active, "overlay is inactive");
    assert.strictEqual(requestCount, 0, "global fetch is skipped");
    assert.strictEqual(messageBus.subscriptions.length, 0, "MessageBus is not subscribed");
    assert.strictEqual(documentObj.listenerCount(), 1, "visibility cleanup is still registered");
  });

  test("initial global fetch replays only the configured latest items and records a watermark", async function (assert) {
    assert.expect(6);

    const requests = [];
    const messageBus = fakeMessageBus();
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus,
      documentObj: fakeDocument(),
      ajax: async (path) => {
        requests.push(path);
        return { items: [{ id: 1, body: "one" }, { id: 2, body: "two" }] };
      },
    });

    await state.start();
    assert.deepEqual(state.items.map((item) => item.id), [1, 2], "a small latest batch is replayed on load");
    await state.start();

    assert.strictEqual(requests[0], `${DANMAKU_GLOBAL_ITEMS_PATH}?after_id=0&limit=3`);
    assert.strictEqual(requests[1], `${DANMAKU_GLOBAL_ITEMS_PATH}?after_id=2&limit=3`);
    assert.deepEqual(state.items.map((item) => item.id), [1, 2], "items are deduped by id");
    assert.strictEqual(messageBus.subscriptions.length, 1, "start is idempotent for subscriptions");
    assert.strictEqual(messageBus.subscriptions[0].channel, DANMAKU_GLOBAL_CHANNEL);
  });

  test("completed rendered items are removed without rewinding the global watermark", async function (assert) {
    assert.expect(3);

    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus: fakeMessageBus(),
      documentObj: fakeDocument(),
      ajax: async () => ({ items: [{ id: 1, body: "one" }, { id: 2, body: "two" }] }),
    });

    await state.start();
    state.removeItem(1);

    assert.deepEqual(state.items.map((item) => item.id), [2], "finished items leave the active render set");
    assert.strictEqual(state.lastSeenId(), 2, "watermark still blocks old item refetches");
    await state.handleMessage({ type: "like", danmaku_id: 1 });
    assert.deepEqual(state.items.map((item) => item.id), [2], "old MessageBus events do not replay dismissed items");
  });

  test("initial replay count can keep page load silent", async function (assert) {
    assert.expect(2);

    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings({ danmaku_initial_replay_count: 0 }),
      messageBus: fakeMessageBus(),
      documentObj: fakeDocument(),
      ajax: async () => ({ items: [{ id: 1, body: "one" }, { id: 2, body: "two" }] }),
    });

    await state.start();

    assert.deepEqual(state.items, [], "zero replay count suppresses historical rendering");
    assert.strictEqual(state.lastSeenId(), 2, "the latest id is still remembered as the realtime watermark");
  });

  test("initial replay skips items already seen in this browser", async function (assert) {
    assert.expect(3);

    const localStorage = fakeLocalStorage(undefined, { [DANMAKU_SEEN_ITEMS_KEY]: JSON.stringify([1, 2]) });
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings({ danmaku_initial_replay_count: 2 }),
      messageBus: fakeMessageBus(),
      documentObj: fakeDocument(),
      localStorage,
      ajax: async () => ({
        items: [
          { id: 1, body: "one" },
          { id: 2, body: "two" },
          { id: 3, body: "three" },
          { id: 4, body: "four" },
        ],
      }),
    });

    await state.start();

    assert.deepEqual(state.items.map((item) => item.id), [3, 4], "only unseen latest items are replayed");
    assert.strictEqual(state.lastSeenId(), 4, "watermark advances to the latest fetched item");
    assert.deepEqual(
      JSON.parse(localStorage.storedValue(DANMAKU_SEEN_ITEMS_KEY)),
      [1, 2, 3, 4],
      "all fetched historical ids are marked seen so refresh does not rotate older backlog"
    );
  });

  test("global fetch failures are recorded without deactivating the layer", async function (assert) {
    assert.expect(4);

    const fetchError = new Error("network unavailable");
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus: fakeMessageBus(),
      documentObj: fakeDocument(),
      ajax: async () => {
        throw fetchError;
      },
    });

    await state.start();

    assert.true(state.active, "fetch failure does not disable the overlay foundation");
    assert.false(state.fetchingGlobal, "fetching state is cleared after failure");
    assert.strictEqual(state.lastFetchError, fetchError, "the fetch error is retained for inspection");
    assert.deepEqual(state.items, [], "no stale item is fabricated on failure");
  });

  test("MessageBus events refetch the guarded item body by id", async function (assert) {
    assert.expect(4);

    const requests = [];
    const messageBus = fakeMessageBus();
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus,
      documentObj: fakeDocument(),
      ajax: async (path) => {
        requests.push(path);

        if (path === `${DANMAKU_ITEM_PATH_PREFIX}5`) {
          return { item: { id: 5, username: "guarded", body: "from guarded API" } };
        }

        return { items: [] };
      },
    });

    await state.start();
    await messageBus.subscriptions[0].callback({ danmaku_id: 5, body: "untrusted event body" });

    assert.true(requests.includes(`${DANMAKU_ITEM_PATH_PREFIX}5`), "item show endpoint is called");
    assert.strictEqual(state.items.length, 1, "one item is rendered");
    assert.strictEqual(state.items[0].body, "from guarded API", "event body is ignored");
    assert.strictEqual(state.items[0].username, "guarded", "guarded payload is used");
  });

  test("duplicate MessageBus item events are coalesced while a guarded fetch is in flight", async function (assert) {
    assert.expect(4);

    const itemRequests = [];
    const itemResolvers = [];
    const messageBus = fakeMessageBus();
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus,
      documentObj: fakeDocument(),
      ajax: async (path) => {
        if (path === `${DANMAKU_ITEM_PATH_PREFIX}5`) {
          itemRequests.push(path);
          return new Promise((resolve) => itemResolvers.push(resolve));
        }

        return { items: [] };
      },
    });

    await state.start();
    const firstFetch = messageBus.subscriptions[0].callback({ danmaku_id: 5 });
    await messageBus.subscriptions[0].callback({ danmaku_id: 5 });
    await messageBus.subscriptions[0].callback({ danmaku_id: 5 });

    assert.strictEqual(itemRequests.length, 1, "duplicate events reuse the in-flight guarded fetch");
    itemResolvers.shift()({ item: { id: 5, body: "first response" } });
    await Promise.resolve();

    assert.strictEqual(itemRequests.length, 2, "one trailing fetch refreshes after a duplicate burst");
    itemResolvers.shift()({ item: { id: 5, body: "latest response" } });
    await firstFetch;

    assert.strictEqual(itemRequests.length, 2, "the duplicate burst is capped at one trailing fetch");
    assert.strictEqual(state.items[0].body, "latest response", "the trailing guarded response wins");
  });

  test("MessageBus events without a danmaku id do not trigger guarded fetches", async function (assert) {
    assert.expect(3);

    const requests = [];
    const messageBus = fakeMessageBus();
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus,
      documentObj: fakeDocument(),
      ajax: async (path) => {
        requests.push(path);
        return { items: [] };
      },
    });

    await state.start();
    await messageBus.subscriptions[0].callback({ type: "create", body: "ignored event body" });

    assert.deepEqual(requests, [`${DANMAKU_GLOBAL_ITEMS_PATH}?after_id=0&limit=3`], "only the initial global fetch runs");
    assert.deepEqual(state.items, [], "no item is fabricated from the event body");
    assert.strictEqual(state.lastFetchError, null, "missing ids fail closed without fetch errors");
  });

  test("guarded item fetch removes stale items after visibility errors", async function (assert) {
    assert.expect(2);

    const messageBus = fakeMessageBus();
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus,
      documentObj: fakeDocument(),
      ajax: async (path) => {
        if (path === `${DANMAKU_ITEM_PATH_PREFIX}4`) {
          throw { status: 404 };
        }

        return { items: [{ id: 4, body: "initial item" }] };
      },
    });

    await state.start();
    await messageBus.subscriptions[0].callback({ danmaku_id: 4 });

    assert.deepEqual(state.items, [], "stale item is removed when the guarded endpoint hides it");
    assert.strictEqual(state.lastSeenId(), 4, "historical items still advance the replay watermark");
  });

  test("cleanup unsubscribes and removes the visibility listener", async function (assert) {
    assert.expect(4);

    const documentObj = fakeDocument();
    const messageBus = fakeMessageBus();
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus,
      documentObj,
      ajax: async () => ({ items: [] }),
    });

    await state.start();
    state.stop();

    assert.false(state.active, "overlay is inactive after stop");
    assert.strictEqual(documentObj.listenerCount(), 0, "visibility listener is removed");
    assert.strictEqual(messageBus.unsubscriptions.length, 1, "MessageBus unsubscribe is called once");
    assert.strictEqual(messageBus.unsubscriptions[0].channel, DANMAKU_GLOBAL_CHANNEL);
  });

  test("document hidden pauses fetches and unsubscribes until visible again", async function (assert) {
    assert.expect(4);

    const documentObj = fakeDocument(true);
    const messageBus = fakeMessageBus();
    let requestCount = 0;
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus,
      documentObj,
      ajax: async () => {
        requestCount++;
        return { items: [] };
      },
    });

    await state.start();
    assert.strictEqual(requestCount, 0, "hidden documents do not fetch");
    assert.strictEqual(messageBus.subscriptions.length, 0, "hidden documents do not subscribe");

    documentObj.hidden = false;
    await documentObj.trigger("visibilitychange");
    assert.strictEqual(requestCount, 1, "visible document fetches once");

    documentObj.hidden = true;
    await documentObj.trigger("visibilitychange");
    assert.strictEqual(messageBus.unsubscriptions.length, 1, "hidden document unsubscribes");
  });

  test("visibility toggles do not duplicate listeners or active MessageBus subscriptions", async function (assert) {
    assert.expect(5);

    const documentObj = fakeDocument();
    const messageBus = fakeMessageBus();
    let requestCount = 0;
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus,
      documentObj,
      ajax: async () => {
        requestCount++;
        return { items: [] };
      },
    });

    await state.start();
    await state.start();
    assert.strictEqual(documentObj.listenerCount("visibilitychange"), 1, "visibilitychange listener is registered once");
    assert.strictEqual(messageBus.listenerCount(DANMAKU_GLOBAL_CHANNEL), 1, "MessageBus has one active callback");

    for (let index = 0; index < 3; index++) {
      documentObj.hidden = true;
      await documentObj.trigger("visibilitychange");
      documentObj.hidden = false;
      await documentObj.trigger("visibilitychange");
    }

    assert.strictEqual(messageBus.listenerCount(DANMAKU_GLOBAL_CHANNEL), 1, "visibility restore keeps one active callback");
    assert.strictEqual(documentObj.listenerCount("visibilitychange"), 1, "visibility listener remains deduped");
    assert.strictEqual(requestCount, 4, "visible restores refetch once per visible transition");
  });

  test("hidden documents discard in-flight global fetch results", async function (assert) {
    assert.expect(2);

    const documentObj = fakeDocument();
    let resolveFetch;
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus: fakeMessageBus(),
      documentObj,
      ajax: async () => new Promise((resolve) => {
        resolveFetch = resolve;
      }),
    });

    const startPromise = state.start();
    documentObj.hidden = true;
    await documentObj.trigger("visibilitychange");
    resolveFetch({ items: [{ id: 9, body: "late hidden item" }] });
    await startPromise;

    assert.false(state.active, "hidden document deactivates during in-flight work");
    assert.deepEqual(state.items, [], "stale hidden fetch result is not merged");
  });

  test("visible restore queues a fresh global fetch behind stale hidden in-flight work", async function (assert) {
    assert.expect(4);

    const documentObj = fakeDocument();
    const responses = [];
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus: fakeMessageBus(),
      documentObj,
      ajax: async () => new Promise((resolve) => {
        responses.push(resolve);
      }),
    });

    const startPromise = state.start();
    documentObj.hidden = true;
    await documentObj.trigger("visibilitychange");
    documentObj.hidden = false;
    await documentObj.trigger("visibilitychange");

    assert.strictEqual(responses.length, 1, "visible restore is queued while first fetch is in flight");
    responses[0]({ items: [{ id: 11, body: "stale item" }] });
    await Promise.resolve();

    assert.strictEqual(responses.length, 2, "queued restore starts a second fetch");
    responses[1]({ items: [{ id: 12, body: "fresh item" }] });
    await startPromise;

    assert.deepEqual(state.items.map((item) => item.id), [12], "fresh restored fetch replays the configured latest items");
    assert.false(state.fetchingGlobal, "fetch lock clears after queued refresh");
  });

  test("guarded item fetch resolving after deactivation is discarded", async function (assert) {
    assert.expect(2);

    const documentObj = fakeDocument();
    let resolveItemFetch;
    const messageBus = fakeMessageBus();
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus,
      documentObj,
      ajax: async (path) => {
        if (path === `${DANMAKU_ITEM_PATH_PREFIX}15`) {
          return new Promise((resolve) => {
            resolveItemFetch = resolve;
          });
        }

        return { items: [] };
      },
    });

    await state.start();
    const itemPromise = messageBus.publish(DANMAKU_GLOBAL_CHANNEL, { danmaku_id: 15 });
    documentObj.hidden = true;
    await documentObj.trigger("visibilitychange");
    resolveItemFetch({ item: { id: 15, body: "late item" } });
    await itemPromise;

    assert.false(state.active, "hidden document deactivates before item response");
    assert.deepEqual(state.items, [], "late guarded item response is discarded");
  });

  test("mobile-disabled and user-local-disabled states prevent activation", async function (assert) {
    assert.expect(12);

    const mobileMessageBus = fakeMessageBus();
    const localMessageBus = fakeMessageBus();
    let mobileFetches = 0;
    let localFetches = 0;

    const mobileState = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings({ danmaku_mobile_enabled: false }),
      capabilities: { isMobileDevice: true },
      documentObj: fakeDocument(),
      messageBus: mobileMessageBus,
      ajax: async () => {
        mobileFetches++;
        return { items: [] };
      },
    });

    const userDisabledState = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      documentObj: fakeDocument(),
      localStorage: fakeLocalStorage(JSON.stringify({ enabled: false })),
      messageBus: localMessageBus,
      ajax: async () => {
        localFetches++;
        return { items: [] };
      },
    });

    await mobileState.start();
    await userDisabledState.start();

    assert.false(mobileState.active, "mobile overlay respects the mobile setting");
    assert.strictEqual(mobileFetches, 0, "mobile-disabled state skips fetching");
    assert.strictEqual(mobileMessageBus.listenerCount(DANMAKU_GLOBAL_CHANNEL), 0, "mobile-disabled state skips subscription");
    assert.false(userDisabledState.active, "local user preference disables the overlay");
    assert.strictEqual(localFetches, 0, "local disabled state skips fetching");
    assert.strictEqual(localMessageBus.listenerCount(DANMAKU_GLOBAL_CHANNEL), 0, "local disabled state skips subscription");
  });

  test("admin can prevent reader-local close from disabling the default-on overlay", async function (assert) {
    assert.expect(5);

    const localStorage = fakeLocalStorage(JSON.stringify({ enabled: false, opacity: 30, area: "half" }));
    const messageBus = fakeMessageBus();
    let requestCount = 0;
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings({ danmaku_allow_reader_close: false }),
      documentObj: fakeDocument(),
      localStorage,
      messageBus,
      ajax: async () => {
        requestCount++;
        return { items: [] };
      },
    });

    assert.deepEqual(
      loadViewerSettingsFromStorage(enabledSettings({ danmaku_allow_reader_close: false }), localStorage),
      { enabled: true, opacity: 30, area: "half" },
      "stored close preference is ignored while opacity and area are preserved"
    );

    await state.start();

    assert.true(state.active, "overlay remains active");
    assert.strictEqual(requestCount, 1, "global fetch still runs");
    assert.strictEqual(messageBus.listenerCount(DANMAKU_GLOBAL_CHANNEL), 1, "MessageBus subscription remains active");
    assert.deepEqual(normalizeViewerSettings({ enabled: false }, enabledSettings({ danmaku_allow_reader_close: false })).enabled, true);
  });

  test("invalid local settings are recorded and treated as enabled", async function (assert) {
    assert.expect(3);

    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      documentObj: fakeDocument(),
      localStorage: fakeLocalStorage("not-json"),
      ajax: async () => ({ items: [] }),
    });

    await state.start();

    assert.true(state.active, "invalid local settings do not disable danmaku");
    assert.ok(state.lastLocalSettingsError instanceof SyntaxError, "parse failure is retained");
    assert.deepEqual(state.items, [], "invalid settings do not fabricate items");
  });

  test("visible items are capped by the configured max visible setting", async function (assert) {
    assert.expect(1);

    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings({ danmaku_max_visible_items: 2 }),
      documentObj: fakeDocument(),
      ajax: async () => ({
        items: [{ id: 1, body: "one" }, { id: 2, body: "two" }, { id: 3, body: "three" }],
      }),
    });

    await state.start();

    assert.deepEqual(state.items.map((item) => item.id), [2, 3]);
  });

  test("one MessageBus event creates one rendered item without duplicate callbacks", async function (assert) {
    assert.expect(4);

    const messageBus = fakeMessageBus();
    let guardedFetches = 0;
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus,
      documentObj: fakeDocument(),
      ajax: async (path) => {
        if (path === `${DANMAKU_ITEM_PATH_PREFIX}7`) {
          guardedFetches++;
          return { item: { id: 7, body: "single event item" } };
        }

        return { items: [] };
      },
    });

    await state.start();
    await state.start();
    await messageBus.publish(DANMAKU_GLOBAL_CHANNEL, { danmaku_id: 7 });

    assert.strictEqual(messageBus.listenerCount(DANMAKU_GLOBAL_CHANNEL), 1, "duplicate starts keep one callback");
    assert.strictEqual(guardedFetches, 1, "event triggers one guarded fetch");
    assert.strictEqual(state.items.length, 1, "one item is present");
    assert.strictEqual(state.items[0].id, 7, "the expected item is merged once");
  });

  test("viewer re-enable resubscribes once and refetches after local settings disabled the layer", async function (assert) {
    assert.expect(5);

    const messageBus = fakeMessageBus();
    let requestCount = 0;
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      messageBus,
      documentObj: fakeDocument(),
      localStorage: fakeLocalStorage(JSON.stringify({ enabled: false })),
      ajax: async () => {
        requestCount++;
        return { items: [] };
      },
    });

    await state.start();
    assert.false(state.active, "local disabled setting starts inactive");
    assert.strictEqual(messageBus.listenerCount(DANMAKU_GLOBAL_CHANNEL), 0, "no subscription exists while disabled");

    await state.updateSettings({ enabled: true });

    assert.true(state.active, "re-enabling viewer settings activates the layer");
    assert.strictEqual(messageBus.listenerCount(DANMAKU_GLOBAL_CHANNEL), 1, "exactly one subscription is restored");
    assert.strictEqual(requestCount, 1, "re-enabling triggers one guarded refetch");
  });

  test("viewer settings normalize defaults and persist to localStorage", async function (assert) {
    assert.expect(5);

    const localStorage = fakeLocalStorage(JSON.stringify({ opacity: 5, area: "quarter" }));
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings({ danmaku_default_opacity: 70, danmaku_default_area: 50 }),
      documentObj: fakeDocument(),
      localStorage,
      ajax: async () => ({ items: [] }),
    });

    assert.deepEqual(
      normalizeViewerSettings({ opacity: 200, area: "unknown" }, { danmaku_default_opacity: 65, danmaku_default_area: 25 }),
      { enabled: true, opacity: 100, area: "quarter" },
      "settings are clamped and fall back to safe area defaults"
    );
    assert.deepEqual(state.settings, { enabled: true, opacity: 10, area: "quarter" });

    await state.start();
    await state.updateSettings({ enabled: false, opacity: 55, area: "half" });

    assert.false(state.active, "disabling viewer settings deactivates fetching");
    assert.deepEqual(JSON.parse(localStorage.storedValue()), { enabled: false, opacity: 55, area: "half" });
    assert.strictEqual(localStorage.storedValue().includes(DANMAKU_USER_SETTINGS_KEY), false, "only JSON settings are stored");
  });

  test("preference page helpers share the same localStorage format", function (assert) {
    assert.expect(2);

    const localStorage = fakeLocalStorage();

    persistViewerSettingsToStorage({ enabled: false, opacity: 45, area: "half" }, localStorage, false);

    assert.deepEqual(JSON.parse(localStorage.storedValue()), { enabled: false, opacity: 45, area: "half" });
    assert.deepEqual(loadViewerSettingsFromStorage(enabledSettings(), localStorage), {
      enabled: false,
      opacity: 45,
      area: "half",
    });
  });

  test("like and unlike actions merge the returned item state", async function (assert) {
    assert.expect(11);

    const requests = [];
    const state = new DanmakuGlobalLayerState({
      siteSettings: enabledSettings(),
      documentObj: fakeDocument(),
      ajax: async (path, options) => {
        requests.push({ path, options });

        if (path === `${DANMAKU_ITEM_PATH_PREFIX}8/like` && options?.type === "POST") {
          return { item: { id: 8, body: "liked", likes_count: 3, liked_by_current_user: true } };
        }

        if (path === `${DANMAKU_ITEM_PATH_PREFIX}8/like` && options?.type === "DELETE") {
          return { item: { id: 8, body: "liked", likes_count: 2, liked_by_current_user: false } };
        }

        return { items: [{ id: 8, body: "liked", likes_count: 2 }] };
      },
    });

    await state.start();
    const item = await state.likeItem(8);
    const unlikedItem = await state.unlikeItem(8);

    assert.strictEqual(requests[1].path, `${DANMAKU_ITEM_PATH_PREFIX}8/like`);
    assert.strictEqual(requests[1].options.type, "POST");
    assert.strictEqual(item.likes_count, 3, "response item is returned");
    assert.strictEqual(state.items[0].likes_count, 3, "state reflects updated like count");
    assert.strictEqual(requests[2].path, `${DANMAKU_ITEM_PATH_PREFIX}8/like`);
    assert.strictEqual(requests[2].options.type, "DELETE");
    assert.strictEqual(unlikedItem.liked_by_current_user, false, "unlike response item is returned");
    assert.strictEqual(state.items[0].likes_count, 2, "state reflects updated unlike count");
  });

  test("renderer assigns random free tracks per visible item", function (assert) {
    assert.expect(12);

    const renderedItems = buildRenderedDanmakuItems(
      [
        { id: 1, user_id: 1, username: "alice-long", body: "one long body", mode: "scroll", color: "#FFEB3B" },
        { id: 2, user_id: 2, username: "bob", body: "two", mode: "scroll" },
        { id: 3, user_id: 3, mode: "top" },
        { id: 4, user_id: 4, mode: "bottom" },
      ],
      {
        area: "full",
        viewportHeight: 256,
        currentUserId: 1,
        maxVisibleItems: 4,
        maxTextLength: 5,
        maxUsernameLength: 6,
        random: () => 0.5,
      }
    );

    assert.deepEqual(renderedItems.map((item) => item.mode), ["scroll", "scroll", "top", "bottom"]);
    assert.deepEqual(renderedItems.map((item) => item.track), [2, 3, 0, 2], "new items pick random free lanes within their mode group");
    assert.strictEqual(renderedItems[0].trackCount, 4, "full area derives available rows from viewport height");
    assert.strictEqual(renderedItems[2].trackPosition, 0, "track position is a pixel row in the visible viewport");
    assert.strictEqual(renderedItems[0].color, "#ffeb3b", "safe color is normalized");
    assert.strictEqual(renderedItems[0].displayBody, "one …", "body display obeys configured max text length");
    assert.strictEqual(renderedItems[0].displayUsername, "alice…", "username display obeys configured max username length");
    assert.strictEqual(renderedItems[1].displayUsername, "bob", "short usernames are not changed");
    assert.notStrictEqual(
      renderedItems[0].scrollDuration,
      renderedItems[1].scrollDuration,
      "scroll speed varies per item"
    );
    assert.strictEqual(
      renderedItems[0].scrollDuration,
      buildRenderedDanmakuItems([{ id: 1, mode: "scroll" }])[0].scrollDuration,
      "per-item speed is stable for the same id"
    );
    assert.true(renderedItems[0].ownsItem, "current user item is marked");
    assert.false(renderedItems[1].ownsItem, "other user item is not marked");
  });

  test("renderer probes for free tracks instead of stacking random collisions", function (assert) {
    assert.expect(4);

    const trackAssignments = new Map();
    const firstRender = buildRenderedDanmakuItems(
      [
        { id: 1, mode: "scroll" },
        { id: 5, mode: "scroll" },
        { id: 9, mode: "scroll" },
      ],
      { area: "full", viewportHeight: 256, maxVisibleItems: 3, trackAssignments, random: () => 0.25 }
    );
    const afterFirstItemDisappears = buildRenderedDanmakuItems(
      [
        { id: 5, mode: "scroll" },
        { id: 9, mode: "scroll" },
      ],
      { area: "full", viewportHeight: 256, maxVisibleItems: 3, trackAssignments, random: () => 0.75 }
    );

    assert.deepEqual(firstRender.map((item) => item.track), [1, 2, 3], "colliding scroll items are placed into free lanes");
    assert.strictEqual(new Set(firstRender.map((item) => item.track)).size, 3, "visible collisions do not stack onto one lane");
    assert.strictEqual(afterFirstItemDisappears.find((item) => item.id === 5).track, 2, "existing item keeps its assigned lane");
    assert.strictEqual(afterFirstItemDisappears.find((item) => item.id === 9).track, 3, "later existing item also keeps its assigned lane");
  });

  test("renderer keeps item tracks stable when another item disappears", function (assert) {
    assert.expect(2);

    const sourceItems = [
      { id: 1, mode: "scroll" },
      { id: 2, mode: "top" },
      { id: 3, mode: "scroll" },
      { id: 4, mode: "bottom" },
    ];
    const trackAssignments = new Map();
    const firstRender = buildRenderedDanmakuItems(sourceItems, {
      area: "full",
      viewportHeight: 256,
      maxVisibleItems: 4,
      trackAssignments,
      random: () => 0.75,
    });
    const afterFixedItemDisappears = buildRenderedDanmakuItems(
      sourceItems.filter((item) => item.id !== 2),
      { area: "full", viewportHeight: 256, maxVisibleItems: 4, trackAssignments, random: () => 0 }
    );

    const trackBefore = firstRender.find((item) => item.id === 3).track;
    const trackAfter = afterFixedItemDisappears.find((item) => item.id === 3).track;

    assert.strictEqual(trackBefore, 1, "scrolling item starts on a probed random track");
    assert.strictEqual(trackAfter, trackBefore, "scrolling item keeps its track after a fixed item is removed");
  });

  test("renderer derives track capacity from the current viewport height", function (assert) {
    assert.expect(3);

    const items = [
      { id: 1, mode: "scroll" },
      { id: 2, mode: "scroll" },
      { id: 3, mode: "scroll" },
      { id: 4, mode: "scroll" },
    ];
    const shortViewport = buildRenderedDanmakuItems(items, { area: "full", viewportHeight: 256, maxVisibleItems: 10, random: () => 0.5 });
    const tallViewport = buildRenderedDanmakuItems(items, { area: "full", viewportHeight: 720, maxVisibleItems: 10, random: () => 0.5 });

    assert.strictEqual(shortViewport[0].trackCount, 4, "short screens expose fewer rows");
    assert.strictEqual(tallViewport[0].trackCount, 17, "tall screens expose more rows");
    assert.notStrictEqual(shortViewport[2].trackPosition, tallViewport[2].trackPosition, "row positions are recalculated for the viewport");
  });

  test("renderer caps output to available track capacity and configured maximum", function (assert) {
    assert.expect(3);

    const renderedItems = buildRenderedDanmakuItems(
      [
        { id: 1, mode: "scroll" },
        { id: 2, mode: "scroll" },
        { id: 3, mode: "top" },
        { id: 4, mode: "bottom" },
        { id: 5, mode: "scroll" },
      ],
      { area: "quarter", viewportHeight: 240, maxVisibleItems: 10 }
    );

    assert.strictEqual(renderedItems.length, 1, "quarter area on a short viewport supports one visible row");
    assert.deepEqual(renderedItems.map((item) => item.id), [5], "latest capped items are retained");
    assert.deepEqual(renderedItems.map((item) => item.trackCount), [1], "track count reflects available rows");
  });

  test("reply actions open same-topic composer and navigate before cross-topic composer", function (assert) {
    assert.expect(4);

    assert.deepEqual(
      replyActionForItem({ topic_id: 10, username: "alice", source_post_url: "/t/source/10/2" }, 10),
      { type: "composer", mention: "@alice ", topicId: 10 },
      "same-topic replies can open the composer with a mention"
    );
    assert.deepEqual(
      replyActionForItem({ topic_id: 11, username: "bob", source_post_url: "/t/source/11/3" }, 10),
      { type: "navigate", mention: "@bob ", topicId: 11, url: "/t/source/11/3" },
      "other-topic replies navigate to the source before composing"
    );
    assert.deepEqual(replyActionForItem({ topic_id: 12 }, 10), { type: "composer", mention: "", topicId: 12 });
    assert.deepEqual(replyActionForItem({}, 10), { type: "none", mention: "" });
  });

  test("native report helpers find source posts and defer to Discourse flag controls", (assert) => {
    assert.expect(9);

    assert.strictEqual(sourcePostNumber({ source_post_url: "/t/source-topic/10/3?u=1" }), 3);
    assert.strictEqual(sourcePostNumber({ source_topic_url: "/t/source-topic/10" }), null);

    let flagClicks = 0;
    const directPost = {
      querySelector(selector) {
        return selector === "button.create-flag" ? { click: () => flagClicks++ } : null;
      },
    };

    assert.true(
      openNativeReportByPostNumber(3, { querySelector: () => directPost }),
      "an exposed flag button opens immediately"
    );
    assert.strictEqual(flagClicks, 1, "the flag button is clicked once");

    let moreActionsClicks = 0;
    let flagLookups = 0;
    const expandablePost = {
      querySelector(selector) {
        if (selector === "button.show-more-actions") {
          return { click: () => moreActionsClicks++ };
        }

        if (selector === "button.create-flag") {
          flagLookups++;
          return flagLookups > 1 ? { click: () => flagClicks++ } : null;
        }

        return null;
      },
    };

    assert.true(
      openNativeReportByPostNumber("4", { querySelector: () => expandablePost }),
      "hidden flag controls are opened through the more-actions button"
    );
    assert.strictEqual(moreActionsClicks, 1, "more actions is expanded once");
    assert.strictEqual(flagClicks, 2, "the expanded flag button is clicked");

    let deferredDelay;
    const deferredPost = {
      querySelector(selector) {
        return selector === "button.show-more-actions" ? { click() {} } : null;
      },
    };

    assert.false(
      openNativeReportByPostNumber(5, { querySelector: () => deferredPost }, (_callback, delay) => {
        deferredDelay = delay;
      }),
      "async menu expansion reports that the flag button is not open yet"
    );
    assert.strictEqual(deferredDelay, 150, "a short deferred lookup preserves the current native-menu behavior");
  });

  test("current route topic id falls back to Discourse topic URLs", function (assert) {
    assert.expect(2);

    const originalLocation = globalThis.location;

    try {
      Object.defineProperty(globalThis, "location", {
        configurable: true,
        value: { pathname: "/t/topic/3858" },
      });

      assert.strictEqual(currentRouteTopicId({ currentRoute: {} }), 3858);

      Object.defineProperty(globalThis, "location", {
        configurable: true,
        value: { pathname: "/latest" },
      });

      assert.strictEqual(currentRouteTopicId({ currentRoute: {} }), null);
    } finally {
      Object.defineProperty(globalThis, "location", {
        configurable: true,
        value: originalLocation,
      });
    }
  });

  test("reduced motion detection follows prefers-reduced-motion", function (assert) {
    assert.expect(2);

    assert.true(
      reducedMotionPreferred({ matchMedia: () => ({ matches: true }) }),
      "reduced motion media query disables scroll movement"
    );
    assert.false(reducedMotionPreferred({ matchMedia: () => ({ matches: false }) }));
  });

  test("reduced motion detection remains one-time and safe when matchMedia is unavailable", function (assert) {
    assert.expect(2);

    assert.false(reducedMotionPreferred({}), "missing matchMedia falls back to normal motion");
    assert.false(
      reducedMotionPreferred({
        matchMedia() {
          throw new Error("media query unavailable");
        },
      }),
      "matchMedia failures do not break overlay construction"
    );
  });
});
