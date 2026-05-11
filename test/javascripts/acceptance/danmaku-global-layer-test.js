import { click, settled, triggerKeyEvent, visit } from "@ember/test-helpers";
import {
  acceptance,
  publishToMessageBus,
} from "discourse/tests/helpers/qunit-helpers";
import { test } from "qunit";

acceptance("Danmaku global layer", function (needs) {
  let globalFetches = 0;
  let guardedItemFetches = 0;

  needs.settings({
    danmaku_enabled: true,
    danmaku_mobile_enabled: true,
    danmaku_initial_fetch_limit: 5,
    danmaku_max_visible_items: 5,
  });

  needs.pretender((server, helper) => {
    server.get("/danmaku/items/global", () => {
      globalFetches++;
      return helper.response({
        items: [
          {
            id: 1,
            user_id: 1,
            username: "alice",
            body: "<strong>initial global danmaku</strong>",
            mode: "scroll",
            likes_count: 0,
            source_topic_title: "Welcome topic",
            source_post_url: "/t/welcome/1/2",
          },
        ],
      });
    });

    server.get("/danmaku/items/:id", (request) => {
      guardedItemFetches++;
      return helper.response({
        item: {
          id: Number.parseInt(request.params.id, 10),
          user_id: 2,
          username: "bob",
          body: "guarded refetched danmaku",
          mode: "scroll",
          likes_count: 0,
        },
      });
    });

    server.post("/danmaku/items/:id/like", (request) => {
      return helper.response({
        item: {
          id: Number.parseInt(request.params.id, 10),
          user_id: 1,
          username: "alice",
          body: "<strong>initial global danmaku</strong>",
          mode: "scroll",
          likes_count: 1,
          source_topic_title: "Welcome topic",
          source_post_url: "/t/welcome/1/2",
        },
      });
    });
  });

  test("mounts one site-wide overlay across route changes and fetches global items", async function (assert) {
    await visit("/latest");

    assert.dom(".danmaku-global-layer").exists({ count: 1 }, "latest has exactly one overlay");
    assert.dom(".danmaku-global-layer__body").hasText("<strong>initial global danmaku</strong>");
    assert.dom(".danmaku-global-layer__item[data-danmaku-mode='scroll']").exists("scroll mode is rendered as data");
    assert.dom(".danmaku-global-layer__source-link").doesNotExist("source navigation lives in the context menu, not the pill");

    await visit("/categories");

    assert.dom(".danmaku-global-layer").exists({ count: 1 }, "category route still has one overlay");
    assert.true(globalFetches > 0, "global endpoint is fetched");
  });

  test("MessageBus event refetches item by id instead of trusting event payload", async function (assert) {
    await visit("/latest");

    await publishToMessageBus("/danmaku/global", {
      type: "create",
      topic_id: 10,
      post_id: 20,
      danmaku_id: 2,
      body: "untrusted event body",
    });
    await settled();

    assert.strictEqual(guardedItemFetches, 1, "guarded item endpoint is called once");
    assert.dom(".danmaku-global-layer").exists({ count: 1 }, "MessageBus keeps one overlay");
    assert.dom(".danmaku-global-layer__body").includesText("guarded refetched danmaku");
  });

  test("viewer settings changes and context menu like/report actions render", async function (assert) {
    globalThis.localStorage?.removeItem?.("discourse-danmaku-settings-v1");

    await visit("/latest");

    globalThis.localStorage?.setItem?.(
      "discourse-danmaku-settings-v1",
      JSON.stringify({ enabled: true, opacity: 55, area: "half" })
    );
    globalThis.window?.dispatchEvent?.(new Event("discourse-danmaku-settings-changed"));
    await settled();

    assert.dom(".danmaku-global-layer.danmaku-area-half").exists("area setting updates the shell class");
    assert.ok(
      globalThis.localStorage?.getItem?.("discourse-danmaku-settings-v1")?.includes('"opacity":55'),
      "viewer settings persist to localStorage"
    );
    assert.true(
      globalThis.document
        .querySelector(".danmaku-global-layer")
        ?.getAttribute("style")
        ?.includes("--danmaku-viewer-opacity:0.55"),
      "opacity setting updates the shell style"
    );

    await click(".danmaku-global-layer__trigger");

    assert.dom(".danmaku-context-menu[role='menu']").exists("accessible menu opens on item click");
    assert.dom(".danmaku-context-menu__item--report").hasAttribute("aria-describedby", "danmaku-menu-report-help");
    assert.dom("#danmaku-menu-report-help").exists("report action has helper text for the native flag flow");
    assert.dom(".danmaku-context-menu__item--report[aria-disabled='true']").doesNotExist("report is an enabled native-report action");

    await click(".danmaku-context-menu__item");
    await settled();

    assert.dom(".danmaku-global-layer__likes").includesText("1", "like response updates rendered count");
    assert.dom(".danmaku-global-layer__heart-marker").exists("like shows the +1 heart marker");
    assert.dom(".danmaku-context-menu__item[data-danmaku-menu-source-link]").hasAttribute("href", "/t/welcome/1/2");
  });

  test("reduced motion marks rendered items without disabling the global overlay", async function (assert) {
    const originalMatchMedia = globalThis.window.matchMedia;

    globalThis.window.matchMedia = () => ({ matches: true });

    try {
      await visit("/latest");

      assert.dom(".danmaku-global-layer").exists({ count: 1 }, "overlay still mounts in reduced motion mode");
      assert.dom(".danmaku-global-layer__item.is-reduced-motion").exists("rendered items receive the reduced-motion class");
    } finally {
      globalThis.window.matchMedia = originalMatchMedia;
    }
  });

  test("overlay accessibility policy and keyboard paths are explicit", async function (assert) {
    globalThis.localStorage?.removeItem?.("discourse-danmaku-settings-v1");

    await visit("/latest");

    assert.dom(".danmaku-global-layer").hasAttribute("aria-live", "off", "moving overlay is not announced as live text");
    assert.dom("[data-danmaku-viewport]").hasAttribute("aria-live", "off", "viewport is quiet for screen readers");
    assert.dom(".danmaku-settings__toggle").exists("global overlay renders the viewer settings toggle");
    assert.dom("#danmaku-settings-panel").doesNotExist("settings panel is closed by default");

    await click(".danmaku-settings__toggle");

    assert.dom("#danmaku-settings-panel").exists("settings panel opens from the overlay");
    assert.dom("[data-testid='danmaku-preferences-enabled']").exists("settings panel includes the visibility option");
    assert.dom("[data-testid='danmaku-preferences-opacity']").exists("settings panel includes the opacity option");
    assert.dom("[data-testid='danmaku-preferences-area']").exists("settings panel includes the area option");

    await triggerKeyEvent(globalThis.document, "keydown", "Escape");

    assert.dom("#danmaku-settings-panel").doesNotExist("Escape closes the settings panel");

    assert.dom(".danmaku-global-layer__trigger").hasAttribute("aria-haspopup", "menu");
    assert.dom(".danmaku-global-layer__source-link").doesNotExist("pills keep the lightweight current UI without inline source links");

    await triggerKeyEvent(".danmaku-global-layer__trigger", "keydown", "Enter");
    assert.dom(".danmaku-context-menu").exists("Enter opens item context menu");
    assert.dom(".danmaku-context-menu__item[data-danmaku-menu-source-link]").hasAttribute("href", "/t/welcome/1/2");
    assert.dom(".danmaku-context-menu__item--report[aria-describedby='danmaku-menu-report-help']").exists("report has helper text");
    await triggerKeyEvent(globalThis.document, "keydown", "Escape");
    assert.dom(".danmaku-context-menu").doesNotExist("Escape closes context menu");

    await triggerKeyEvent(".danmaku-global-layer__trigger", "keydown", " ");
    assert.dom(".danmaku-context-menu").exists("Space opens item context menu");
  });
});

acceptance("Danmaku global layer disabled", function (needs) {
  let globalFetches = 0;

  needs.settings({
    danmaku_enabled: false,
    danmaku_mobile_enabled: true,
    danmaku_initial_fetch_limit: 5,
    danmaku_max_visible_items: 5,
  });

  needs.pretender((server, helper) => {
    server.get("/danmaku/items/global", () => {
      globalFetches++;
      return helper.response({ items: [] });
    });
  });

  test("does not render or fetch when disabled", async function (assert) {
    await visit("/latest");

    assert.dom(".danmaku-global-layer").doesNotExist("disabled setting hides the overlay");
    assert.strictEqual(globalFetches, 0, "disabled setting prevents global fetch");
  });
});
