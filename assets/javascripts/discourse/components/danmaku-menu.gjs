import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { i18n } from "discourse-i18n";

export default class DanmakuMenu extends Component {
  get item() {
    return this.args.menu.item;
  }

  get menuStyle() {
    return `--danmaku-menu-x:${this.args.menu.x}px;--danmaku-menu-y:${this.args.menu.y}px`;
  }

  get sourceUrl() {
    return this.item.source_post_url || this.item.source_topic_url;
  }

  get hasSourceUrl() {
    return Boolean(this.sourceUrl);
  }

  get likesCount() {
    return this.item.likes_count || 0;
  }

  get likeLabel() {
    return this.item.liked_by_current_user ? i18n("danmaku.menu.unlike") : i18n("danmaku.menu.like");
  }

  get likeClass() {
    const classes = ["danmaku-context-menu__item", "danmaku-context-menu__item--like"];

    if (this.item.liked_by_current_user) {
      classes.push("is-liked");
    }

    if (this.likeDisabled) {
      classes.push("is-disabled");
    }

    return classes.join(" ");
  }

  get likeDisabled() {
    return !this.item.liked_by_current_user && !this.item.can_like_by_current_user;
  }

  get reportHelpId() {
    return "danmaku-menu-report-help";
  }

  @action
  like() {
    if (this.likeDisabled) {
      return;
    }

    this.args.onLike?.(this.item);
  }

  @action
  reply() {
    this.args.onReply?.(this.item);
  }

  @action
  report() {
    this.args.onReport?.(this.item);
  }

  @action
  close() {
    this.args.onClose?.();
  }

  @action
  keepMenuOpen(event) {
    event.stopPropagation();
  }

  <template>
  <div
    class="danmaku-context-menu"
    style={{this.menuStyle}}
    role="menu"
    aria-label={{i18n "danmaku.menu.title"}}
    data-testid="danmaku-context-menu"
    {{on "click" this.keepMenuOpen}}
  >
    <div class="danmaku-context-menu__actions">
      <button
        type="button"
        class={{this.likeClass}}
        role="menuitem"
        disabled={{this.likeDisabled}}
        aria-disabled={{if this.likeDisabled "true" "false"}}
        {{on "click" this.like}}
      >
        <span class="danmaku-context-menu__icon" aria-hidden="true">❤️</span>
        {{this.likeLabel}}
        <span class="danmaku-context-menu__count">{{this.likesCount}}</span>
      </button>

      <button
        type="button"
        class="danmaku-context-menu__item danmaku-context-menu__item--reply"
        role="menuitem"
        {{on "click" this.reply}}
      >
        <span class="danmaku-context-menu__icon" aria-hidden="true">💬</span>
        {{i18n "danmaku.menu.reply"}}
      </button>
    </div>

    {{#if this.hasSourceUrl}}
      <a
        class="danmaku-context-menu__item danmaku-context-menu__item--source"
        role="menuitem"
        href={{this.sourceUrl}}
        data-danmaku-menu-source-link
      >
        {{i18n "danmaku.menu.view_source"}}
      </a>
    {{else}}
      <button
        type="button"
        class="danmaku-context-menu__item danmaku-context-menu__item--source"
        role="menuitem"
        aria-disabled="true"
        title={{i18n "danmaku.menu.view_source_unavailable"}}
      >
        {{i18n "danmaku.menu.view_source_unavailable"}}
      </button>
    {{/if}}

    <button
      type="button"
      class="danmaku-context-menu__item danmaku-context-menu__item--report"
      role="menuitem"
      title={{i18n "danmaku.menu.report_hint"}}
      aria-describedby={{this.reportHelpId}}
      {{on "click" this.report}}
    >
      <span class="danmaku-context-menu__icon" aria-hidden="true">🚨</span>
      {{i18n "danmaku.menu.report"}}
    </button>

    <span id={{this.reportHelpId}} class="danmaku-context-menu__hint">
      {{i18n "danmaku.menu.report_hint"}}
    </span>

    <button
      type="button"
      class="danmaku-context-menu__close"
      aria-label={{i18n "danmaku.menu.close"}}
      {{on "click" this.close}}
    >
      ×
    </button>
  </div>
  </template>
}
