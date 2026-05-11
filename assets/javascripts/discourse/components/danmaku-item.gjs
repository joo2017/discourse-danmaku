import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { tracked } from "@glimmer/tracking";
import { i18n } from "discourse-i18n";

export default class DanmakuItem extends Component {
  @tracked paused = false;

  get renderedItem() {
    return this.args.renderedItem;
  }

  get item() {
    return this.renderedItem.item;
  }

  get itemStyle() {
    const styleParts = [
      `--danmaku-track-index:${this.renderedItem.track}`,
      `--danmaku-track-count:${this.renderedItem.trackCount}`,
      `--danmaku-track-position:${this.renderedItem.trackPosition}px`,
      `--danmaku-scroll-duration:${this.renderedItem.scrollDuration}s`,
      `--danmaku-fixed-duration:${this.renderedItem.fixedDuration}s`,
    ];

    if (this.renderedItem.color) {
      styleParts.push(`--danmaku-item-color:${this.renderedItem.color}`);
    }

    return styleParts.join(";");
  }

  get itemClass() {
    const classes = ["danmaku-global-layer__item"];

    if (this.renderedItem.ownsItem) {
      classes.push("is-own-item");
    }

    if (this.item.liked_by_current_user) {
      classes.push("is-liked");
    }

    if (this.renderedItem.reducedMotion) {
      classes.push("is-reduced-motion");
    }

    if (this.paused) {
      classes.push("is-paused");
    }

    if (this.isActive) {
      classes.push("is-active");
    }

    return classes.join(" ");
  }

  get ariaLabel() {
    return i18n("danmaku.viewer.item_label", {
      username: this.displayUsername || i18n("danmaku.viewer.unknown_user"),
      body: this.displayBody,
    });
  }

  get showHeartMarker() {
    return this.args.likedItemId === this.item.id;
  }

  get isActive() {
    return this.args.activeItemId === this.item.id;
  }

  get likesCount() {
    return this.item.likes_count || 0;
  }

  get displayBody() {
    return this.renderedItem.displayBody || "";
  }

  get displayUsername() {
    return this.renderedItem.displayUsername || this.item.username;
  }

  get showLikesCount() {
    return this.likesCount > 0;
  }

  @action
  openMenu(event) {
    event.stopPropagation();
    this.args.onOpen?.(this.item, event);
  }

  @action
  openMenuFromKeyboard(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.args.onOpen?.(this.item, event);
  }

  @action
  keepSourceClickInsideItem(event) {
    event.stopPropagation();
  }

  @action
  pauseMotion() {
    this.paused = true;
  }

  @action
  resumeMotion() {
    this.paused = false;
  }

  @action
  completeMotion(event) {
    if (event.target !== event.currentTarget) {
      return;
    }

    this.args.onComplete?.(this.item);
  }

  <template>
  <span
    class={{this.itemClass}}
    style={{this.itemStyle}}
    data-danmaku-id={{this.item.id}}
    data-danmaku-mode={{this.renderedItem.mode}}
    data-danmaku-track={{this.renderedItem.track}}
    dir="auto"
    {{on "pointerenter" this.pauseMotion}}
    {{on "pointerleave" this.resumeMotion}}
    {{on "focusin" this.pauseMotion}}
    {{on "focusout" this.resumeMotion}}
    {{on "animationend" this.completeMotion}}
  >
    <button
      type="button"
      class="danmaku-global-layer__trigger"
      aria-label={{this.ariaLabel}}
      aria-haspopup="menu"
      dir="auto"
      {{on "click" this.openMenu}}
      {{on "keydown" this.openMenuFromKeyboard}}
    >
      {{#if this.displayUsername}}
        <span class="danmaku-global-layer__username" dir="auto">@{{this.displayUsername}}</span>
      {{/if}}

      <span class="danmaku-global-layer__body" dir="auto">{{this.displayBody}}</span>

      {{#if this.showLikesCount}}
        <span class="danmaku-global-layer__meta" aria-hidden="true">
          <span class="danmaku-global-layer__likes">♥ {{this.likesCount}}</span>
        </span>
      {{/if}}
    </button>

    {{#if this.showHeartMarker}}
      <span class="danmaku-global-layer__heart-marker" aria-hidden="true">+1 ♥</span>
    {{/if}}
  </span>
  </template>
}
