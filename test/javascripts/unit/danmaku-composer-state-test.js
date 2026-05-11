import {
	canSendDanmakuDraft,
	canShowDanmakuEntryPoint,
	DANMAKU_COMPOSER_SERIALIZED_FIELDS,
	danmakuDraftToolsVisible,
	disableDanmakuDraft,
	enableDanmakuDraft,
	isDanmakuDraftEnabled,
	isDanmakuDraftLocked,
	needsDanmakuLogin,
} from "discourse/plugins/discourse-danmaku/discourse/lib/danmaku-composer-draft-adapter";
import {
	clearComposerDanmakuSelection,
	composerDanmakuColor,
	composerDanmakuColorBase,
	composerDanmakuColorOpacity,
	composerDanmakuControlsAvailable,
	composerDanmakuEnabled,
	composerDanmakuMode,
	currentUserCanUseDanmakuPremiumTools,
	DEFAULT_DANMAKU_COLOR,
	DEFAULT_DANMAKU_MODE,
	enableComposerDanmakuSelection,
	resolveDanmakuTargetPostId,
	updateComposerDanmakuColor,
	updateComposerDanmakuColorOpacity,
	updateComposerDanmakuMode,
} from "discourse/plugins/discourse-danmaku/discourse/lib/danmaku-composer-state";
import { module, test } from "qunit";

function serializeCreateFields(composerModel) {
	const payload = {};

	DANMAKU_COMPOSER_SERIALIZED_FIELDS.forEach(([payloadField, modelField]) => {
		const value = composerModel[modelField];

		if (typeof value !== "undefined") {
			payload[payloadField] = value;
		}
	});

	return payload;
}

module("Unit | Lib | danmaku-composer-state", () => {
	test("premium composer opt-in serializes danmaku create fields", (assert) => {
		const composerModel = {};

		enableComposerDanmakuSelection(composerModel, {
			targetPostId: 42,
			mode: "bottom",
			color: "#FFEB3B",
		});

		assert.true(composerDanmakuEnabled(composerModel), "composer is opted in");
		assert.deepEqual(
			serializeCreateFields(composerModel),
			{
				danmaku_enabled: true,
				danmaku_target_post_id: 42,
				danmaku_mode: "bottom",
				danmaku_color: "#ffeb3b",
			},
			"Discourse create serialization sees all danmaku fields",
		);
	});

	test("unchecked and cleared composer omits danmaku create fields", (assert) => {
		const composerModel = {
			danmakuEnabled: true,
			danmakuTargetPostId: 9,
			danmakuMode: "top",
			danmakuColor: "#ffffff",
		};

		clearComposerDanmakuSelection(composerModel);

		assert.false(
			composerDanmakuEnabled(composerModel),
			"composer is not opted in",
		);
		assert.deepEqual(
			serializeCreateFields(composerModel),
			{},
			"undefined fields are omitted from create payload",
		);
	});

	test("new or restored composers default unchecked with safe tool defaults", (assert) => {
		const composerModel = {};

		assert.false(
			composerDanmakuEnabled(composerModel),
			"fresh composer is unchecked",
		);
		assert.strictEqual(
			composerDanmakuMode(composerModel),
			DEFAULT_DANMAKU_MODE,
			"mode defaults to scroll",
		);
		assert.strictEqual(
			composerDanmakuColor(composerModel),
			DEFAULT_DANMAKU_COLOR,
			"color defaults to yellow",
		);
		assert.deepEqual(
			serializeCreateFields(composerModel),
			{},
			"fresh composer has no danmaku payload fields",
		);
	});

	test("free users are not treated as premium until they opt into basic danmaku", (assert) => {
		const composerModel = {};

		assert.false(
			currentUserCanUseDanmakuPremiumTools({ username: "free" }),
			"plain users are locked",
		);
		clearComposerDanmakuSelection(composerModel);

		assert.deepEqual(
			serializeCreateFields(composerModel),
			{},
			"locked users keep payload clean",
		);
	});

	test("disabled plugin state keeps composer controls unavailable and unserialized", (assert) => {
		const composerModel = {};

		assert.false(
			composerDanmakuControlsAvailable(
				{ danmaku_enabled: false },
				{ username: "premium" },
			),
			"disabled setting hides composer controls",
		);
		clearComposerDanmakuSelection(composerModel);

		assert.deepEqual(
			serializeCreateFields(composerModel),
			{},
			"disabled state has no danmaku payload fields",
		);
	});

	test("enabled plugin state shows the composer control even before login", (assert) => {
		assert.true(
			composerDanmakuControlsAvailable({ danmaku_enabled: true }),
			"enabled setting exposes a locked/login-aware entry point",
		);
		assert.true(
			canShowDanmakuEntryPoint({ danmaku_enabled: true }),
			"draft adapter exposes the same entry point rule",
		);
	});

	test("composer draft adapter centralizes login, basic send, and premium decisions", (assert) => {
		const siteSettings = { danmaku_enabled: true, danmaku_allow_basic_users: true };
		const composerModel = { danmakuTargetPostId: "42" };
		const normalUser = { username: "normal" };
		const premiumUser = {
			username: "premium",
			can_use_danmaku_premium_tools: true,
		};

		assert.true(
			needsDanmakuLogin(siteSettings, null),
			"anonymous viewers need login to send",
		);
		assert.false(
			isDanmakuDraftLocked(siteSettings, normalUser),
			"normal logged-in users can send basic danmaku",
		);
		assert.true(canSendDanmakuDraft(normalUser, siteSettings), "normal users can send basic danmaku");
		assert.true(canSendDanmakuDraft(premiumUser), "premium users can send");

		enableDanmakuDraft(composerModel);

		assert.true(
			isDanmakuDraftEnabled(composerModel, siteSettings, premiumUser),
			"premium enabled drafts are active",
		);
		assert.false(
			isDanmakuDraftLocked(siteSettings, premiumUser),
			"premium users are not locked",
		);
		assert.true(
			isDanmakuDraftEnabled(composerModel, siteSettings, normalUser),
			"normal users get an active basic send draft",
		);
		assert.true(
			danmakuDraftToolsVisible(composerModel, siteSettings, normalUser),
			"normal enabled drafts show tools so premium actions can explain the permission boundary",
		);
		assert.true(
			danmakuDraftToolsVisible(composerModel, siteSettings, premiumUser),
			"premium enabled drafts show tools",
		);
		assert.deepEqual(
			serializeCreateFields(composerModel),
			{
				danmaku_enabled: true,
				danmaku_target_post_id: 42,
				danmaku_mode: DEFAULT_DANMAKU_MODE,
				danmaku_color: DEFAULT_DANMAKU_COLOR,
			},
			"adapter enables the same serialized payload shape",
		);

		disableDanmakuDraft(composerModel);

		assert.deepEqual(
			serializeCreateFields(composerModel),
			{},
			"adapter clears all serialized fields",
		);
	});

	test("only server-provided premium flags unlock the composer tools", (assert) => {
		assert.false(
			currentUserCanUseDanmakuPremiumTools({ staff: true }),
			"staff fallback is not used when the serializer flag is absent",
		);
		assert.true(
			currentUserCanUseDanmakuPremiumTools({
				can_use_danmaku_premium_tools: true,
			}),
			"server-provided premium flag is honored",
		);
		assert.false(
			currentUserCanUseDanmakuPremiumTools({
				can_use_danmaku_premium_tools: false,
				staff: true,
			}),
			"explicit server-provided denial keeps staff locked in the UX",
		);
	});

	test("mode and color updates only apply after opt-in and normalize invalid values", (assert) => {
		const composerModel = {};

		updateComposerDanmakuMode(composerModel, "bottom");
		updateComposerDanmakuColor(composerModel, "#123456");
		assert.deepEqual(
			serializeCreateFields(composerModel),
			{},
			"locked or unchecked state ignores tool updates",
		);

		enableComposerDanmakuSelection(composerModel, {
			mode: "middle",
			color: "red",
		});

		assert.strictEqual(
			composerModel.danmakuMode,
			DEFAULT_DANMAKU_MODE,
			"invalid mode falls back to scroll",
		);
		assert.strictEqual(
			composerModel.danmakuColor,
			DEFAULT_DANMAKU_COLOR,
			"invalid color falls back to default",
		);

		updateComposerDanmakuMode(composerModel, "top");
		updateComposerDanmakuColor(composerModel, "#123456");

		assert.strictEqual(
			composerModel.danmakuMode,
			"top",
			"valid mode update is stored",
		);
		assert.strictEqual(
			composerModel.danmakuColor,
			"#123456",
			"valid color update is stored",
		);
	});

	test("composer color opacity is encoded into eight-digit hex colors", (assert) => {
		const composerModel = {};

		enableComposerDanmakuSelection(composerModel, {
			color: "#ffeb3b",
		});

		updateComposerDanmakuColorOpacity(composerModel, 50);

		assert.strictEqual(
			composerModel.danmakuColor,
			"#ffeb3b80",
			"50 percent opacity is serialized as hex alpha",
		);
		assert.strictEqual(
			composerDanmakuColorBase(composerModel),
			"#ffeb3b",
			"color picker receives the RGB base color",
		);
		assert.strictEqual(
			composerDanmakuColorOpacity(composerModel),
			50,
			"opacity slider receives the stored alpha as a percentage",
		);

		updateComposerDanmakuColor(composerModel, "#123456");

		assert.strictEqual(
			composerModel.danmakuColor,
			"#12345680",
			"changing the color preserves the current opacity",
		);

		updateComposerDanmakuColorOpacity(composerModel, 100);

		assert.strictEqual(
			composerModel.danmakuColor,
			"#123456",
			"full opacity stores a standard six-digit color",
		);
	});

	test("target post ids are normalized from composer models and omitted when invalid", (assert) => {
		const getterComposer = {
			get(propertyName) {
				return propertyName === "danmakuTargetPostId" ? "42" : undefined;
			},
		};

		assert.strictEqual(
			resolveDanmakuTargetPostId(getterComposer),
			42,
			"positive string ids are normalized for backend serialization",
		);
		assert.strictEqual(
			resolveDanmakuTargetPostId({ danmakuTargetPostId: "0" }),
			undefined,
			"non-positive ids are dropped from the payload",
		);
		assert.strictEqual(
			resolveDanmakuTargetPostId({ danmakuTargetPostId: "not-a-number" }),
			undefined,
			"invalid ids are omitted instead of serialized",
		);
		assert.strictEqual(
			resolveDanmakuTargetPostId({
				replyToPostNumber: 11,
				reply_to_post_number: 12,
			}),
			undefined,
			"v1 does not probe private reply metadata or DOM-derived state",
		);
	});

	test("composer helpers support Ember-style setProperties and keep cleared payloads empty", (assert) => {
		const composerModel = {
			state: {},
			setProperties(properties) {
				Object.assign(this.state, properties);
			},
			get(propertyName) {
				return this.state[propertyName];
			},
		};

		enableComposerDanmakuSelection(composerModel, {
			targetPostId: 17,
			mode: "top",
			color: "#ABCDEF",
		});

		assert.deepEqual(
			serializeCreateFields(composerModel.state),
			{
				danmaku_enabled: true,
				danmaku_target_post_id: 17,
				danmaku_mode: "top",
				danmaku_color: "#abcdef",
			},
			"premium opt-in still serializes cleanly through Ember setters",
		);

		clearComposerDanmakuSelection(composerModel);

		assert.deepEqual(
			serializeCreateFields(composerModel.state),
			{},
			"clearing via Ember setters removes all danmaku payload fields",
		);
	});
});
