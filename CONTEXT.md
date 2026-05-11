# Discourse Danmaku Context

## Terms

### Lightweight Atmosphere Layer

The plugin's primary product goal is to add a lightweight atmosphere layer on top of Discourse.

Danmaku should make the community feel more lively without replacing Discourse's native reading, replying, moderation, or content-discovery flows. It should be low-distraction, easy to turn off, visually aligned with the active Discourse theme, and traceable back to the source post.

The primary viewing scope is the global site-wide stream, not a topic-local or post-local stream. This intentionally differs from video-site danmaku, where comments are bound to the current video. In this plugin, danmaku acts as a site-wide atmosphere broadcast, so distraction control and source traceability are more important than tight local context.

The default presence should be low. Global danmaku should be noticeable enough to make the site feel active, but it should not compete with reading. Defaults should favor low density, softer opacity, and a limited upper-screen display area rather than a full-screen flood.

Clicking a danmaku should keep a full interaction menu: like, reply, view source, and report. Because the global stream lacks local topic context, view source and report must remain easy to understand, while like and reply provide lightweight participation without making danmaku a replacement comment system.

The UI language should stay highly aligned with native Discourse. Settings, menus, composer controls, modals, buttons, and form fields should look and behave like Discourse UI. Only the flying danmaku item itself should have a slightly special visual treatment, and even that treatment should inherit Discourse theme colors, fonts, shadows, and spacing.

### Normal User

A normal user is a non-premium site user. Normal users should be considered in the product model separately from premium users so the plugin can provide a clear baseline experience without making core reading or viewing feel paywalled.

Normal users can watch danmaku and control their own viewing experience, but they cannot send danmaku. This mirrors the product boundary of video-site danmaku: viewing contributes to atmosphere for everyone, while sending is a higher-participation capability reserved for eligible users.

### Premium User

A premium user is a user who belongs to a configured premium group or is otherwise allowed by staff bypass settings. Premium users can send danmaku and use sender-side options such as display mode or accent color.
