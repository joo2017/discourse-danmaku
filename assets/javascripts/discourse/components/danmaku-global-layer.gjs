import Component from "@glimmer/component";
import { getOwner } from "@ember/owner";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { registerDestructor } from "@ember/destroyable";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import Composer from "discourse/models/composer";
import { i18n } from "discourse-i18n";
import DanmakuInteractionController from "../lib/danmaku-interaction-controller";
import DanmakuGlobalLayerState from "../lib/danmaku-global-layer-state";
import {
  buildRenderedDanmakuItems,
  reducedMotionPreferred,
} from "../lib/danmaku-renderer-state";
import { openNativeReportByPostNumber as openNativeReportByPostNumberFromDocument } from "../lib/danmaku-native-report";
import DanmakuItem from "./danmaku-item";
import DanmakuMenu from "./danmaku-menu";
import DanmakuPreferenceSettings from "./danmaku-preference-settings";

export default class DanmakuGlobalLayer extends Component {
  @service siteSettings;
  @service messageBus;
  @service capabilities;
  @service currentUser;
  @service router;
  @service composer;

  @tracked active = false;
  @tracked items = [];
  @tracked settings;
  @tracked viewportHeight = globalThis.window?.innerHeight || 720;
  @tracked menu = null;
  @tracked settingsPanelOpen = false;
  @tracked likedItemId = null;
  @tracked reducedMotion = reducedMotionPreferred();
  @tracked layerTop = globalThis.window?.scrollY || 0;
  isDanmakuDestroying = false;
  trackAssignments = new Map();
  renderedItemsCacheKey = null;
  renderedItemsCache = [];
  resizeFrame = null;

  constructor() {
    super(...arguments);

    this.handleResize = this.handleResize.bind(this);
    this.flushResize = this.flushResize.bind(this);
    this.handleDocumentClick = this.handleDocumentClick.bind(this);
    this.handleDocumentKeydown = this.handleDocumentKeydown.bind(this);
    this.handleReducedMotionChange = this.handleReducedMotionChange.bind(this);
    this.reducedMotionQuery = this.reducedMotionMediaQuery();

    this.state = new DanmakuGlobalLayerState({
      siteSettings: this.siteSettings,
      messageBus: this.messageBus,
      capabilities: this.capabilities,
      onChange: ({ active, items, settings }) => {
        if (this.isDanmakuDestroying) {
          return;
        }

        const previousMaxItemId = this.maxItemId(this.items);
        const nextMaxItemId = this.maxItemId(items);

        if (nextMaxItemId > previousMaxItemId) {
          this.layerTop = this.currentScrollY();
        }

        this.active = active;
        this.items = items;
        this.settings = settings;
      },
    });
    this.settings = this.state.settings;
    this.interactions = new DanmakuInteractionController({
      owner: getOwner(this),
      router: this.router,
      composer: this.composer,
      composerReplyAction: Composer.REPLY,
      state: this.state,
      currentUser: () => this.currentUser,
      closeMenus: () => this.closeMenus(),
      updateMenuItem: (item) => {
        this.menu = { ...this.menu, item };
      },
      showHeartMarker: (itemId) => this.showHeartMarker(itemId),
      openNativeReportByPostNumber: (postNumber) => this.openNativeReportByPostNumber(postNumber),
    });

    this.state.start();
    globalThis.window?.addEventListener?.("resize", this.handleResize);
    this.addReducedMotionListener();
    globalThis.document?.addEventListener?.("click", this.handleDocumentClick);
    globalThis.document?.addEventListener?.("keydown", this.handleDocumentKeydown);
    this.pendingReplyTimer = globalThis.setTimeout?.(() => this.interactions.consumePendingReply(), 700);
    this.pendingReportTimer = globalThis.setTimeout?.(() => this.interactions.consumePendingReport(), 900);

    registerDestructor(this, () => {
      this.isDanmakuDestroying = true;
      this.state.stop();
      globalThis.window?.removeEventListener?.("resize", this.handleResize);
      this.removeReducedMotionListener();
      globalThis.document?.removeEventListener?.("click", this.handleDocumentClick);
      globalThis.document?.removeEventListener?.("keydown", this.handleDocumentKeydown);
      if (this.resizeFrame !== null) {
        globalThis.window?.cancelAnimationFrame?.(this.resizeFrame);
        this.resizeFrame = null;
      }
      if (this.pendingReplyTimer) {
        globalThis.clearTimeout(this.pendingReplyTimer);
      }
      if (this.pendingReportTimer) {
        globalThis.clearTimeout(this.pendingReportTimer);
      }
      this.clearHeartTimer();
    });
  }

  get shellVisible() {
    return Boolean(
      this.siteSettings.danmaku_enabled &&
        this.settings &&
        (!this.state.isMobileDevice() || this.siteSettings.danmaku_mobile_enabled)
    );
  }

  get layerClass() {
    return `danmaku-global-layer danmaku-area-${this.settings.area}`;
  }

  get layerStyle() {
    return `--danmaku-viewer-opacity:${this.settings.opacity / 100};--danmaku-layer-top:${this.layerTop}px`;
  }

  get currentUserId() {
    return this.currentUser?.id;
  }

  get activeItemId() {
    return this.menu?.item?.id;
  }

  get renderedItems() {
    if (!this.active || !this.settings) {
      return [];
    }

    const visibleItems = this.visibleItems;
    const cacheKey = this.renderedItemsKey(visibleItems);
    if (cacheKey === this.renderedItemsCacheKey) {
      return this.renderedItemsCache;
    }

    this.pruneTrackAssignments(visibleItems);
    this.renderedItemsCacheKey = cacheKey;
    this.renderedItemsCache = buildRenderedDanmakuItems(visibleItems, {
      area: this.settings.area,
      viewportHeight: this.viewportHeight,
      maxVisibleItems: this.state.maxVisibleItems(),
      maxTextLength: this.siteSettings.danmaku_max_text_length,
      maxUsernameLength: this.siteSettings.danmaku_max_username_length,
      currentUserId: this.currentUserId,
      reducedMotion: this.reducedMotion,
      trackAssignments: this.trackAssignments,
    });

    return this.renderedItemsCache;
  }

  get visibleItems() {
    return this.items.slice(-this.state.maxVisibleItems());
  }

  handleResize() {
    if (this.resizeFrame !== null) {
      return;
    }

    const requestFrame = globalThis.window?.requestAnimationFrame;
    if (!requestFrame) {
      this.flushResize();
      return;
    }

    this.resizeFrame = globalThis.window.requestAnimationFrame(this.flushResize);
  }

  flushResize() {
    this.resizeFrame = null;
    const nextViewportHeight = globalThis.window?.innerHeight || this.viewportHeight;
    if (nextViewportHeight !== this.viewportHeight) {
      this.viewportHeight = nextViewportHeight;
    }
  }

  reducedMotionMediaQuery() {
    try {
      return globalThis.window?.matchMedia?.("(prefers-reduced-motion: reduce)");
    } catch {
      return null;
    }
  }

  addReducedMotionListener() {
    if (!this.reducedMotionQuery) {
      return;
    }

    if (this.reducedMotionQuery.addEventListener) {
      this.reducedMotionQuery.addEventListener("change", this.handleReducedMotionChange);
    } else {
      this.reducedMotionQuery.addListener?.(this.handleReducedMotionChange);
    }
  }

  removeReducedMotionListener() {
    if (!this.reducedMotionQuery) {
      return;
    }

    if (this.reducedMotionQuery.removeEventListener) {
      this.reducedMotionQuery.removeEventListener("change", this.handleReducedMotionChange);
    } else {
      this.reducedMotionQuery.removeListener?.(this.handleReducedMotionChange);
    }
  }

  handleReducedMotionChange(event) {
    this.reducedMotion = Boolean(event?.matches ?? this.reducedMotionQuery?.matches);
  }

  currentScrollY() {
    return globalThis.window?.scrollY || globalThis.document?.documentElement?.scrollTop || 0;
  }

  currentScrollX() {
    return globalThis.window?.scrollX || globalThis.document?.documentElement?.scrollLeft || 0;
  }

  maxItemId(items) {
    return items.reduce((maxId, item) => Math.max(maxId, Number(item?.id) || 0), 0);
  }

  pruneTrackAssignments(items) {
    const visibleIds = new Set(items.map((item) => `${item?.id}`).filter(Boolean));

    for (const itemId of this.trackAssignments.keys()) {
      if (!visibleIds.has(itemId)) {
        this.trackAssignments.delete(itemId);
      }
    }
  }

  renderedItemsKey(items) {
    return JSON.stringify([
      items.map((item) => [
        item?.id,
        item?.body,
        item?.username,
        item?.mode,
        item?.color,
        item?.likes_count,
        item?.liked_by_current_user,
        item?.user_id,
      ]),
      this.settings.area,
      this.viewportHeight,
      this.state.maxVisibleItems(),
      this.siteSettings.danmaku_max_text_length,
      this.siteSettings.danmaku_max_username_length,
      this.currentUserId,
      this.reducedMotion,
    ]);
  }

  handleDocumentClick() {
    this.closeMenus();
  }

  handleDocumentKeydown(event) {
    if (event.key === "Escape") {
      this.closeMenus();
    }
  }

  closeMenus() {
    this.menu = null;
    this.settingsPanelOpen = false;
  }

  clearHeartTimer() {
    if (this.heartTimer) {
      globalThis.clearTimeout(this.heartTimer);
      this.heartTimer = null;
    }
  }

  showHeartMarker(itemId) {
    this.clearHeartTimer();
    this.likedItemId = itemId;
    this.heartTimer = globalThis.setTimeout(() => {
      this.likedItemId = null;
      this.heartTimer = null;
    }, 900);
  }

  @action
  openMenu(item, event) {
    const rect = event.currentTarget?.getBoundingClientRect?.();
    const x = rect ? rect.left + rect.width / 2 : event.clientX || 16;
    const y = rect ? rect.bottom + 8 : event.clientY || 16;

    this.menu = { item, x, y };
  }

  @action
  closeMenu() {
    this.menu = null;
  }

  @action
  toggleSettingsPanel(event) {
    event.stopPropagation();
    this.menu = null;
    this.settingsPanelOpen = !this.settingsPanelOpen;
  }

  @action
  keepSettingsPanelOpen(event) {
    event.stopPropagation();
  }

  @action
  dismissRenderedItem(item) {
    this.state.removeItem(item?.id);
  }

  @action
  async likeItem(item) {
    await this.interactions.likeItem(item);
  }

  @action
  reportItem(item) {
    this.interactions.reportItem(item);
  }

  @action
  replyToItem(item) {
    this.interactions.replyToItem(item);
  }

  openNativeReportByPostNumber(postNumber) {
    return openNativeReportByPostNumberFromDocument(postNumber);
  }

  <template>
  {{#if this.shellVisible}}
    <div
      class={{this.layerClass}}
      style={{this.layerStyle}}
      data-testid="danmaku-global-layer"
      aria-live="off"
      {{on "click" this.closeMenu}}
    >
      <div class="danmaku-settings" {{on "click" this.keepSettingsPanelOpen}}>
        <button
          type="button"
          class="danmaku-settings__toggle"
          aria-expanded={{if this.settingsPanelOpen "true" "false"}}
          aria-controls="danmaku-settings-panel"
          data-testid="danmaku-settings-toggle"
          {{on "click" this.toggleSettingsPanel}}
        >
          {{i18n "danmaku.viewer.settings_button"}}
        </button>

        {{#if this.settingsPanelOpen}}
          <div
            id="danmaku-settings-panel"
            class="danmaku-settings__panel"
            role="dialog"
            aria-label={{i18n "danmaku.viewer.settings_title"}}
            data-testid="danmaku-settings-panel"
          >
            <DanmakuPreferenceSettings />
          </div>
        {{/if}}
      </div>

      {{#if this.active}}
        <div
          class="danmaku-global-layer__viewport"
          data-danmaku-viewport
          role="presentation"
          aria-live="off"
          aria-atomic="false"
        >
          {{#each this.renderedItems key="id" as |renderedItem|}}
            <DanmakuItem
              @renderedItem={{renderedItem}}
              @likedItemId={{this.likedItemId}}
              @activeItemId={{this.activeItemId}}
              @onOpen={{this.openMenu}}
              @onComplete={{this.dismissRenderedItem}}
            />
          {{/each}}
        </div>
      {{/if}}

      {{#if this.menu}}
        <DanmakuMenu
          @menu={{this.menu}}
          @onLike={{this.likeItem}}
          @onReply={{this.replyToItem}}
          @onReport={{this.reportItem}}
          @onClose={{this.closeMenu}}
        />
      {{/if}}
    </div>
  {{/if}}
  </template>
}
