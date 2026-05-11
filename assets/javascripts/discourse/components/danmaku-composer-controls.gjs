import Component from "@glimmer/component";
import { getOwner } from "@ember/owner";
import { action } from "@ember/object";
import { registerDestructor } from "@ember/destroyable";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import {
  canSendDanmakuDraft,
  canShowDanmakuEntryPoint,
  disableDanmakuDraft,
  enableDanmakuDraft,
  isDanmakuDraftEnabled,
  isDanmakuDraftLocked,
  needsDanmakuLogin,
} from "../lib/danmaku-composer-draft-adapter";
import { i18n } from "discourse-i18n";

export default class DanmakuComposerControls extends Component {
  @service siteSettings;
  @service currentUser;
  @service composer;
  @service router;

  @tracked showSubscriptionCta = false;

  constructor() {
    super(...arguments);
    disableDanmakuDraft(this.composerModel);
    registerDestructor(this, () => disableDanmakuDraft(this.composerModel));
  }

  get composerModel() {
    return this.args.outletArgs?.model || this.composer.model;
  }

  get enabled() {
    return canShowDanmakuEntryPoint(this.siteSettings);
  }

  get canSend() {
    return canSendDanmakuDraft(this.currentUser, this.siteSettings);
  }

  get checked() {
    return isDanmakuDraftEnabled(this.composerModel, this.siteSettings, this.currentUser);
  }

  get locked() {
    return isDanmakuDraftLocked(this.siteSettings, this.currentUser);
  }

  get needsLogin() {
    return needsDanmakuLogin(this.siteSettings, this.currentUser);
  }

  get subscribeUrl() {
    return this.siteSettings.danmaku_subscribe_url;
  }

  get hasSubscribeUrl() {
    return Boolean(this.subscribeUrl);
  }

  @action
  toggleDanmaku(event) {
    if (!this.enabled) {
      disableDanmakuDraft(this.composerModel);
      return;
    }

    if (this.needsLogin) {
      event.preventDefault();
      event.target.checked = false;
      disableDanmakuDraft(this.composerModel);
      this.showLogin();
      return;
    }

    if (!this.canSend) {
      event.preventDefault();
      event.target.checked = false;
      disableDanmakuDraft(this.composerModel);
      this.openSubscriptionCta();
      return;
    }

    if (event.target.checked) {
      enableDanmakuDraft(this.composerModel);
    } else {
      disableDanmakuDraft(this.composerModel);
    }
  }

  openSubscriptionCta() {
    this.showSubscriptionCta = true;
  }

  showLogin() {
    const applicationRoute = getOwner(this).lookup("route:application");

    if (applicationRoute?.send) {
      applicationRoute.send("showLogin");
      return;
    }

    const transition = this.router?.transitionTo?.("login");
    if (transition) {
      transition.wantsTo = true;
    }
  }

  @action
  closeSubscriptionCta() {
    this.showSubscriptionCta = false;
  }

  @action
  closeSubscriptionCtaFromKeyboard(event) {
    if (event.key === "Escape") {
      this.closeSubscriptionCta();
    }
  }

  <template>
  {{#if this.enabled}}
    <div class="danmaku-composer-control" data-testid="danmaku-composer-control">
      <label
        class="danmaku-composer-control__label {{if this.locked 'is-locked'}}"
      >
        <input
          class="danmaku-composer-control__checkbox"
          type="checkbox"
          checked={{this.checked}}
          data-testid="danmaku-composer-checkbox"
          {{on "change" this.toggleDanmaku}}
        />
        <span class="danmaku-composer-control__text">
          {{i18n "danmaku.composer.send_as_danmaku"}}
        </span>
      </label>

      {{#if this.showSubscriptionCta}}
        <div
          class="danmaku-composer-cta"
          data-testid="danmaku-composer-cta"
          {{on "keydown" this.closeSubscriptionCtaFromKeyboard}}
        >
          <div class="danmaku-composer-cta__backdrop" {{on "click" this.closeSubscriptionCta}}></div>
          <section
            class="danmaku-composer-cta__dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="danmaku-composer-cta-title"
            aria-describedby="danmaku-composer-cta-body"
          >
            <div class="danmaku-composer-cta__header">
              <h3 id="danmaku-composer-cta-title" class="danmaku-composer-cta__title">
                {{i18n "danmaku.modal.title"}}
              </h3>
              <button
                type="button"
                class="danmaku-composer-cta__close"
                aria-label={{i18n "danmaku.modal.close"}}
                data-testid="danmaku-composer-cta-close"
                {{on "click" this.closeSubscriptionCta}}
              >
                ×
              </button>
            </div>

            <p id="danmaku-composer-cta-body" class="danmaku-composer-cta__body">
              {{i18n "danmaku.modal.body"}}
            </p>

            {{#if this.hasSubscribeUrl}}
              <a
                class="btn btn-primary danmaku-composer-cta__link"
                href={{this.subscribeUrl}}
                data-testid="danmaku-composer-cta-link"
              >
                {{i18n "danmaku.modal.cta"}}
              </a>
            {{else}}
              <p class="danmaku-composer-cta__fallback" data-testid="danmaku-composer-cta-fallback">
                {{i18n "danmaku.locked.free_user_cta"}}
              </p>
            {{/if}}
          </section>
        </div>
      {{/if}}
    </div>
  {{/if}}
  </template>
}
