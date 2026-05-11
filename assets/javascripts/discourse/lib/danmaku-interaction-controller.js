import { sourcePostNumber } from "./danmaku-native-report";
import {
	currentRouteTopicId,
	replyActionForItem,
} from "./danmaku-renderer-state";

const PENDING_REPLY_KEY = "discourse_danmaku_pending_reply";
const PENDING_REPORT_KEY = "discourse_danmaku_pending_report";
const PENDING_REPLY_MAX_AGE_MS = 30000;
const PENDING_REPORT_MAX_AGE_MS = 30000;

function readValue(object, propertyName) {
	if (!object) {
		return undefined;
	}

	if (typeof object.get === "function") {
		return object.get(propertyName);
	}

	return object[propertyName];
}

function positiveInteger(value) {
	const parsed = Number.parseInt(value, 10);
	return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function findByPostContext(posts, postId, postNumber) {
	if (!posts) {
		return null;
	}

	const sourcePosts = Array.isArray(posts)
		? posts
		: typeof posts.toArray === "function"
			? posts.toArray()
			: Array.from(posts);

	return (
		sourcePosts.find((post) => {
			const candidateId = positiveInteger(readValue(post, "id"));
			const candidateNumber = positiveInteger(readValue(post, "post_number"));

			return (
				(postId && candidateId === postId) ||
				(postNumber && candidateNumber === postNumber)
			);
		}) || null
	);
}

export default class DanmakuInteractionController {
	constructor(options = {}) {
		this.owner = options.owner;
		this.router = options.router;
		this.composer = options.composer;
		this.composerReplyAction = options.composerReplyAction || "reply";
		this.state = options.state;
		this.currentUser = options.currentUser || (() => null);
		this.closeMenus = options.closeMenus || (() => {});
		this.updateMenuItem = options.updateMenuItem || (() => {});
		this.showHeartMarker = options.showHeartMarker || (() => {});
		this.openNativeReportByPostNumber =
			options.openNativeReportByPostNumber || (() => {});
		this.location = options.location || globalThis.location;
		this.sessionStorage = options.sessionStorage || globalThis.sessionStorage;
		this.now = options.now || (() => Date.now());
	}

	showLogin() {
		const applicationRoute = this.owner?.lookup?.("route:application");

		if (applicationRoute?.send) {
			applicationRoute.send("showLogin");
			return;
		}

		this.router?.transitionTo?.("login");
	}

	ensureLoggedIn() {
		if (this.currentUser()) {
			return true;
		}

		this.closeMenus();
		this.showLogin();
		return false;
	}

	async likeItem(item) {
		if (!this.ensureLoggedIn()) {
			return;
		}

		const wasLiked = Boolean(item?.liked_by_current_user);
		const updatedItem = await this.state?.toggleLikeItem?.(item);

		if (updatedItem) {
			this.updateMenuItem(updatedItem);
		}

		if (!wasLiked) {
			this.showHeartMarker(updatedItem?.id || item.id);
		}
	}

	reportItem(item) {
		if (!this.ensureLoggedIn()) {
			return;
		}

		const topicId = Number(item?.topic_id);
		const currentTopicId = Number(currentRouteTopicId(this.router));
		const url = item?.source_post_url || item?.source_topic_url;
		const postNumber = sourcePostNumber(item);

		if (topicId && topicId !== currentTopicId && url) {
			this.storePendingReport({ topicId, postNumber });
			this.location?.assign?.(url);
			this.closeMenus();
			return;
		}

		this.openNativeReportByPostNumber(postNumber);
		this.closeMenus();
	}

	replyToItem(item) {
		if (!this.ensureLoggedIn()) {
			return;
		}

		const replyAction = replyActionForItem(
			item,
			currentRouteTopicId(this.router),
		);

		if (replyAction.type === "composer") {
			this.openComposerReply(replyAction);
		} else if (replyAction.type === "navigate") {
			this.navigateToReply(replyAction);
		}

		this.closeMenus();
	}

	currentTopicModel(topicId) {
		const topicController = this.owner?.lookup?.("controller:topic");
		const topic = topicController?.model;
		const currentTopicId = readValue(topic, "id");

		return Number(currentTopicId) === Number(topicId) ? topic : null;
	}

	sourcePostModel(topic, replyAction) {
		if (!topic) {
			return null;
		}

		const postId = positiveInteger(replyAction.postId);
		const postNumber = positiveInteger(replyAction.postNumber);
		const postStream = readValue(topic, "postStream");
		const loadedPost = findByPostContext(readValue(postStream, "posts"), postId, postNumber);

		if (loadedPost) {
			return loadedPost;
		}

		if (!postId && !postNumber) {
			return null;
		}

		return {
			id: postId,
			post_number: postNumber,
			topic_id: positiveInteger(replyAction.topicId),
			topic,
		};
	}

	async openComposerReply(replyAction) {
		const topic = this.currentTopicModel(replyAction.topicId);
		const post = this.sourcePostModel(topic, replyAction);
		const draftKey =
			readValue(topic, "draft_key") || `topic_${replyAction.topicId}`;
		const draftSequence = readValue(topic, "draft_sequence") || 0;
		const composerOptions = {
			action: this.composerReplyAction,
			draftKey,
			draftSequence,
		};

		if (topic) {
			composerOptions.topic = topic;
		}

		if (post) {
			composerOptions.post = post;
		}

		await this.composer?.open?.(composerOptions);
		this.composer?.focus?.();
	}

	navigateToReply(replyAction) {
		this.storePendingReply(replyAction);
		this.location?.assign?.(replyAction.url);
	}

	storePendingReply(replyAction) {
		this.sessionStorage?.setItem?.(
			PENDING_REPLY_KEY,
			JSON.stringify({
				createdAt: this.now(),
				postId: replyAction.postId,
				postNumber: replyAction.postNumber,
				topicId: replyAction.topicId,
			}),
		);
	}

	consumePendingReply() {
		const rawPendingReply = this.sessionStorage?.getItem?.(PENDING_REPLY_KEY);

		if (!rawPendingReply) {
			return;
		}

		let pendingReply;

		try {
			pendingReply = JSON.parse(rawPendingReply);
		} catch {
			this.sessionStorage?.removeItem?.(PENDING_REPLY_KEY);
			return;
		}

		if (
			this.now() - Number(pendingReply.createdAt) >
			PENDING_REPLY_MAX_AGE_MS
		) {
			this.sessionStorage?.removeItem?.(PENDING_REPLY_KEY);
			return;
		}

		if (
			Number(pendingReply.topicId) !== Number(currentRouteTopicId(this.router))
		) {
			return;
		}

		this.sessionStorage?.removeItem?.(PENDING_REPLY_KEY);
		this.openComposerReply({
			type: "composer",
			postId: pendingReply.postId,
			postNumber: pendingReply.postNumber,
			topicId: pendingReply.topicId,
		});
	}

	storePendingReport(reportAction) {
		this.sessionStorage?.setItem?.(
			PENDING_REPORT_KEY,
			JSON.stringify({
				createdAt: this.now(),
				postNumber: reportAction.postNumber,
				topicId: reportAction.topicId,
			}),
		);
	}

	consumePendingReport() {
		const rawPendingReport = this.sessionStorage?.getItem?.(PENDING_REPORT_KEY);

		if (!rawPendingReport) {
			return;
		}

		let pendingReport;

		try {
			pendingReport = JSON.parse(rawPendingReport);
		} catch {
			this.sessionStorage?.removeItem?.(PENDING_REPORT_KEY);
			return;
		}

		if (
			this.now() - Number(pendingReport.createdAt) >
			PENDING_REPORT_MAX_AGE_MS
		) {
			this.sessionStorage?.removeItem?.(PENDING_REPORT_KEY);
			return;
		}

		if (
			Number(pendingReport.topicId) !== Number(currentRouteTopicId(this.router))
		) {
			return;
		}

		this.sessionStorage?.removeItem?.(PENDING_REPORT_KEY);
		this.openNativeReportByPostNumber(pendingReport.postNumber);
	}
}
