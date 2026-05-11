# Discourse Danmaku

Discourse Danmaku adds floating danmaku overlays to a Discourse site. The plugin is designed for normal Discourse plugin installation and uses admin settings for access, safety, display, and rate limits.

## Install in Discourse

Install this repository inside a Discourse checkout as `plugins/discourse-danmaku`.

```sh
cd /path/to/discourse
git clone <this repository url> plugins/discourse-danmaku
```

For local plugin development, a symlink is also fine when you control both paths.

```sh
cd /path/to/discourse
ln -s /path/to/discourse-danmaku plugins/discourse-danmaku
```

Run migrations from the host Discourse checkout with plugins loaded.

```sh
RAILS_ENV=test LOAD_PLUGINS=1 bin/rake db:create
RAILS_ENV=test LOAD_PLUGINS=1 script/silence_successful_output bin/rake db:migrate
RAILS_ENV=test LOAD_PLUGINS=1 bin/rake parallel:create
RAILS_ENV=test LOAD_PLUGINS=1 script/silence_successful_output bin/rake parallel:migrate
```

This repository can run local syntax and policy checks on its own. Full RSpec and QUnit runs require a host Discourse checkout because this is a standalone plugin workspace.

## Enable and configure access

1. In Discourse admin settings, enable `danmaku_enabled`.
2. Create a Discourse group named `danmaku_premium`.
3. Add premium users to that group, or configure another premium group name.
4. Set `danmaku_premium_group_names` to the group or groups that can create danmaku. The default is `danmaku_premium`.
5. Set `danmaku_subscribe_url` to the page free users should visit from the composer call to action.

Staff can create danmaku when `danmaku_staff_bypass` is enabled, even if they are not in a premium group.

## Discourse Subscriptions integration

Use Discourse Subscriptions only as a group grant mapping. Configure a Subscriptions plan so successful subscription purchase grants the same group listed in `danmaku_premium_group_names`, usually `danmaku_premium`.

The plugin checks Discourse group membership. It does not read Subscriptions or Stripe internals, store payment identifiers, or depend on payment records. There are no direct payments in v1.

## Public stream safety

`danmaku_global_public_only` controls whether the global stream is restricted to danmaku whose source topic and post are visible to anonymous users. Keep it enabled for the safest default. That prevents private, restricted, or members-only topic content from being copied into the global public danmaku stream.

The plugin also checks normal Discourse permissions before returning danmaku items. Users can only view danmaku linked to source posts they can already see. That local/topic-scoped permission path is separate from the anonymous global-stream filter, so authorized viewers are not blocked from topic-local read, show, or like actions just because anonymous users cannot see the source.

## Composer behavior, v1 A方案

When a user checks the danmaku composer option, Discourse creates the normal reply first. After the reply exists, the plugin creates a linked danmaku copy from that post if the user, topic, source post, text, cooldown, and daily cap checks all pass.

There is no standalone send endpoint in v1. Danmaku creation is tied to normal reply creation so the source post remains the canonical record.

`danmaku_target_post_id` remains optional context in v1. The frontend only serializes it when the Discourse composer model already exposes an explicit transient `danmakuTargetPostId` value; the plugin does not probe private post-stream DOM or infer reply targets from unstable internal fields.

## Admin-tunable settings

All limits below are admin-tunable settings. Treat the defaults as starting points, not immutable product rules.

## Localization

The plugin uses Discourse locale files for all user-facing and admin-facing copy. English (`en`) is the default fallback, and Simplified Chinese (`zh_CN`) is included for Chinese sites. Additional languages can be added by copying `config/locales/client.en.yml` and `config/locales/server.en.yml` to the target locale code and translating the same keys.

| Setting | Purpose |
| --- | --- |
| `danmaku_enabled` | Enables or disables the plugin. |
| `danmaku_premium_group_names` | Groups allowed to create danmaku. Defaults to `danmaku_premium`. |
| `danmaku_subscribe_url` | URL used by the free-user composer CTA. |
| `danmaku_global_public_only` | Keeps the global stream limited to anonymously visible source content. |
| `danmaku_excluded_category_ids` | Categories where danmaku sending is disabled. |
| `danmaku_max_text_length` | Maximum source post text length allowed for danmaku copy creation. |
| `danmaku_send_rate_limit_seconds` | Per-user cooldown between danmaku creations. |
| `danmaku_daily_limit_per_user` | Per-user daily danmaku creation cap. |
| `danmaku_global_broadcast_limit_per_minute` | Per-process broadcast cap used to reduce abuse and event pressure. |
| `danmaku_initial_fetch_limit` | Maximum number of danmaku items returned by initial fetch requests. |
| `danmaku_max_visible_items` | Client render limit for visible danmaku items. |
| `danmaku_default_opacity` | Default overlay opacity percentage. |
| `danmaku_default_area` | Default vertical screen area percentage used for rendering. |
| `danmaku_mobile_enabled` | Enables danmaku rendering on mobile web when true. |
| `danmaku_staff_bypass` | Allows staff to create danmaku without premium group membership. |

Broadcast limiting uses the configured Discourse cache backend. Cache backends that support atomic `increment` provide the strongest multi-process cap behavior; backends without `increment` fall back to read/write counting and should be treated as best-effort only.

## Test commands for latest-stable Discourse

Run these from the host Discourse checkout after installing the plugin at `plugins/discourse-danmaku`.

```sh
RAILS_ENV=test LOAD_PLUGINS=1 bin/rake db:create
RAILS_ENV=test LOAD_PLUGINS=1 script/silence_successful_output bin/rake db:migrate
RAILS_ENV=test LOAD_PLUGINS=1 bin/rake parallel:create
RAILS_ENV=test LOAD_PLUGINS=1 script/silence_successful_output bin/rake parallel:migrate
```

Backend specs:

```sh
RAILS_ENV=test bin/rake "plugin:turbo_spec[discourse-danmaku,--verbose --format=progress --use-runtime-info --profile=50]"
```

Frontend tests:

```sh
RAILS_ENV=test bin/rake "plugin:qunit[discourse-danmaku]"
```

## Local QA helper

From this plugin repository, run:

```sh
script/danmaku-qa
```

The helper checks required files, Ruby syntax, JavaScript syntax where local tooling can parse files, YAML settings and locales, required setting keys, forbidden payment internals, and common frontend/test slop. It also prints the integrated Discourse commands above.

Set `DISCOURSE_DEV_PATH=/path/to/discourse` to have the helper inspect a host checkout and print safe guidance. It will not create or replace `plugins/discourse-danmaku` unless you explicitly opt in with `DANMAKU_QA_SYMLINK=1`.

## Known v1 exclusions

V1 does not include direct payments, a custom moderation or report queue, native mobile app UI, an analytics dashboard, or per-category admin UI. Use Discourse groups, existing staff moderation tools, mobile web settings, and the admin settings listed above.
