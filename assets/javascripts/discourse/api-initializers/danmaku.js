import { apiInitializer } from "discourse/lib/api";
import DanmakuComposerControls from "../components/danmaku-composer-controls";
import DanmakuComposerTools from "../components/danmaku-composer-tools";
import DanmakuGlobalLayer from "../components/danmaku-global-layer";
import DanmakuPreferenceSettings from "../components/danmaku-preference-settings";
import { DANMAKU_COMPOSER_SERIALIZED_FIELDS } from "../lib/danmaku-composer-draft-adapter";

export default apiInitializer("0.8", (api) => {
  api.renderInOutlet("above-site-header", DanmakuGlobalLayer);
  api.renderInOutlet("before-composer-toggles", DanmakuComposerControls);
  api.renderInOutlet("composer-fields-below", DanmakuComposerTools);
  api.renderInOutlet("user-preferences-interface", DanmakuPreferenceSettings);

  for (const [payloadField, modelField] of DANMAKU_COMPOSER_SERIALIZED_FIELDS) {
    api.serializeOnCreate(payloadField, modelField);
  }
});
