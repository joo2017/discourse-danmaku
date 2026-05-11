import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import {
  DANMAKU_AREA_OPTIONS,
  defaultViewerSettings,
  loadViewerSettingsFromStorage,
  normalizeViewerSettings,
  persistViewerSettingsToStorage,
} from "../lib/danmaku-global-layer-state";
import { i18n } from "discourse-i18n";

export default class DanmakuPreferenceSettings extends Component {
  @service siteSettings;

  @tracked settings = this.loadSettings();
  @tracked loadError = null;

  get areaOptions() {
    return DANMAKU_AREA_OPTIONS.map((area) => ({
      ...area,
      selected: area.id === this.settings.area,
    }));
  }

  get enabled() {
    return Boolean(this.siteSettings.danmaku_enabled);
  }

  get canToggleEnabled() {
    return this.siteSettings.danmaku_allow_reader_close !== false;
  }

  loadSettings() {
    try {
      return loadViewerSettingsFromStorage(this.siteSettings);
    } catch (error) {
      this.loadError = error;
      return defaultViewerSettings(this.siteSettings);
    }
  }

  saveSettings(changes) {
    this.settings = normalizeViewerSettings({ ...this.settings, ...changes }, this.siteSettings);
    persistViewerSettingsToStorage(this.settings);
  }

  @action
  updateEnabled(event) {
    this.saveSettings({ enabled: event.target.checked });
  }

  @action
  updateOpacity(event) {
    this.saveSettings({ opacity: event.target.value });
  }

  @action
  updateArea(event) {
    this.saveSettings({ area: event.target.value });
  }

  <template>
    {{#if this.enabled}}
      <section class="control-group danmaku-preferences" data-testid="danmaku-preferences">
        <h3>{{i18n "danmaku.viewer.settings_title"}}</h3>

        {{#if this.canToggleEnabled}}
          <label class="checkbox-label danmaku-preferences__row">
            <input
              type="checkbox"
              checked={{this.settings.enabled}}
              data-testid="danmaku-preferences-enabled"
              {{on "change" this.updateEnabled}}
            />
            {{i18n "danmaku.viewer.enabled"}}
          </label>
        {{else}}
          <p class="danmaku-preferences__row" data-testid="danmaku-preferences-close-disabled">
            {{i18n "danmaku.viewer.close_disabled"}}
          </p>
        {{/if}}

        <label class="danmaku-preferences__row danmaku-preferences__row--stacked">
          <span>{{i18n "danmaku.viewer.opacity"}}: {{this.settings.opacity}}%</span>
          <input
            class="danmaku-preferences__range"
            type="range"
            min="10"
            max="100"
            step="5"
            value={{this.settings.opacity}}
            data-testid="danmaku-preferences-opacity"
            {{on "input" this.updateOpacity}}
          />
        </label>

        <label class="danmaku-preferences__row danmaku-preferences__row--stacked">
          <span>{{i18n "danmaku.viewer.area"}}</span>
          <select
            class="danmaku-preferences__select"
            value={{this.settings.area}}
            data-testid="danmaku-preferences-area"
            {{on "change" this.updateArea}}
          >
            {{#each this.areaOptions as |area|}}
              <option value={{area.id}} selected={{area.selected}}>{{i18n area.labelKey}}</option>
            {{/each}}
          </select>
        </label>
      </section>
    {{/if}}
  </template>
}
