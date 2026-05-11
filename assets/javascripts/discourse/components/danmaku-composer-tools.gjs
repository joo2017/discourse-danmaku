import Component from "@glimmer/component";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import {
  DANMAKU_MODE_OPTIONS,
} from "../lib/danmaku-composer-state";
import {
  danmakuDraftColor,
  danmakuDraftColorOpacity,
  danmakuDraftMode,
  danmakuDraftToolsVisible,
  updateDanmakuDraftColor,
  updateDanmakuDraftColorOpacity,
  updateDanmakuDraftMode,
} from "../lib/danmaku-composer-draft-adapter";
import { i18n } from "discourse-i18n";

export default class DanmakuComposerTools extends Component {
  @service siteSettings;
  @service currentUser;
  @service composer;

  @tracked showPremiumCta = false;

  get modeOptions() {
    return DANMAKU_MODE_OPTIONS.map((mode) => ({
      ...mode,
      selected: mode.id === this.mode,
    }));
  }

  get composerModel() {
    return this.args.outletArgs?.model || this.composer.model;
  }

  get visible() {
    return danmakuDraftToolsVisible(this.composerModel, this.siteSettings, this.currentUser);
  }

  get canCustomize() {
    return this.currentUser?.can_use_danmaku_premium_tools === true;
  }

  get subscribeUrl() {
    return this.siteSettings.danmaku_subscribe_url;
  }

  get hasSubscribeUrl() {
    return Boolean(this.subscribeUrl);
  }

  get mode() {
    return danmakuDraftMode(this.composerModel);
  }

  get color() {
    return danmakuDraftColor(this.composerModel);
  }

  get colorOpacity() {
    return danmakuDraftColorOpacity(this.composerModel);
  }

  @action
  updateMode(event) {
    if (!this.canCustomize) {
      event.preventDefault();
      event.target.value = this.mode;
      this.openPremiumCta();
      return;
    }

    updateDanmakuDraftMode(this.composerModel, event.target.value);
  }

  @action
  updateColor(event) {
    if (!this.canCustomize) {
      event.preventDefault();
      event.target.value = this.color;
      this.openPremiumCta();
      return;
    }

    updateDanmakuDraftColor(this.composerModel, event.target.value);
  }

  @action
  updateColorOpacity(event) {
    if (!this.canCustomize) {
      event.preventDefault();
      event.target.value = this.colorOpacity;
      this.openPremiumCta();
      return;
    }

    updateDanmakuDraftColorOpacity(this.composerModel, event.target.value);
  }

  @action
  openPremiumCta() {
    this.showPremiumCta = true;
  }

  @action
  closePremiumCta() {
    this.showPremiumCta = false;
  }

  @action
  closePremiumCtaFromKeyboard(event) {
    if (event.key === "Escape") {
      this.closePremiumCta();
    }
  }

  <template>
  {{#if this.visible}}
    <section class="danmaku-composer-tools" data-testid="danmaku-composer-tools">
      <div class="danmaku-composer-tools__header">
        <span class="danmaku-composer-tools__eyebrow">
          {{i18n "danmaku.composer.premium_tools"}}
        </span>
        <span class="danmaku-composer-tools__hint">
          {{#if this.canCustomize}}
            {{i18n "danmaku.composer.tools_hint"}}
          {{else}}
            {{i18n "danmaku.composer.premium_required_hint"}}
          {{/if}}
        </span>
      </div>

      <label class="danmaku-composer-tools__field">
        <span>{{i18n "danmaku.composer.mode_label"}}</span>
        <select
          class="danmaku-composer-tools__select"
          value={{this.mode}}
          data-testid="danmaku-composer-mode"
          {{on "change" this.updateMode}}
        >
          {{#each this.modeOptions as |mode|}}
            <option value={{mode.id}} selected={{mode.selected}}>
              {{i18n mode.labelKey}}
            </option>
          {{/each}}
        </select>
      </label>

      <label class="danmaku-composer-tools__field danmaku-composer-tools__field--color">
        <span>{{i18n "danmaku.composer.color_label"}}</span>
        <input
          class="danmaku-composer-tools__color"
          type="color"
          value={{this.color}}
          data-testid="danmaku-composer-color"
          {{on "input" this.updateColor}}
        />
      </label>

      <label class="danmaku-composer-tools__field danmaku-composer-tools__field--opacity">
        <span>{{i18n "danmaku.composer.color_opacity_label"}}</span>
        <input
          class="danmaku-composer-tools__range"
          type="range"
          min="10"
          max="100"
          step="5"
          value={{this.colorOpacity}}
          data-testid="danmaku-composer-color-opacity"
          {{on "input" this.updateColorOpacity}}
        />
        <output class="danmaku-composer-tools__output">{{this.colorOpacity}}%</output>
      </label>

      {{#unless this.canCustomize}}
        <button
          type="button"
          class="btn btn-default danmaku-composer-tools__upgrade"
          data-testid="danmaku-composer-premium-required"
          {{on "click" this.openPremiumCta}}
        >
          {{i18n "danmaku.modal.cta"}}
        </button>
      {{/unless}}

      {{#if this.showPremiumCta}}
        <div
          class="danmaku-composer-cta"
          data-testid="danmaku-composer-tools-cta"
          {{on "keydown" this.closePremiumCtaFromKeyboard}}
        >
          <div class="danmaku-composer-cta__backdrop" {{on "click" this.closePremiumCta}}></div>
          <section
            class="danmaku-composer-cta__dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="danmaku-composer-tools-cta-title"
            aria-describedby="danmaku-composer-tools-cta-body"
          >
            <div class="danmaku-composer-cta__header">
              <h3 id="danmaku-composer-tools-cta-title" class="danmaku-composer-cta__title">
                {{i18n "danmaku.modal.title"}}
              </h3>
              <button
                type="button"
                class="danmaku-composer-cta__close"
                aria-label={{i18n "danmaku.modal.close"}}
                {{on "click" this.closePremiumCta}}
              >
                ×
              </button>
            </div>

            <p id="danmaku-composer-tools-cta-body" class="danmaku-composer-cta__body">
              {{i18n "danmaku.modal.body"}}
            </p>

            {{#if this.hasSubscribeUrl}}
              <a
                class="btn btn-primary danmaku-composer-cta__link"
                href={{this.subscribeUrl}}
              >
                {{i18n "danmaku.modal.cta"}}
              </a>
            {{else}}
              <p class="danmaku-composer-cta__fallback">
                {{i18n "danmaku.locked.free_user_cta"}}
              </p>
            {{/if}}
          </section>
        </div>
      {{/if}}
    </section>
  {{/if}}
  </template>
}
