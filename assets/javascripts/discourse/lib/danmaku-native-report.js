export function sourcePostNumber(item) {
  const postUrl = item?.source_post_url || "";
  const match = postUrl.match(/\/(\d+)(?:[?#].*)?$/);

  return match ? Number.parseInt(match[1], 10) : null;
}

export function openNativeReportByPostNumber(
  postNumber,
  documentObj = globalThis.document,
  defer = globalThis.setTimeout
) {
  const safePostNumber = Number.parseInt(postNumber, 10);

  if (!Number.isFinite(safePostNumber) || safePostNumber <= 0) {
    return false;
  }

  const postSelector = `.topic-post[data-post-number="${safePostNumber}"]`;
  const postElement = documentObj?.querySelector?.(postSelector);

  if (!postElement) {
    return false;
  }

  const flagButton = postElement.querySelector("button.create-flag");

  if (flagButton) {
    flagButton.click();
    return true;
  }

  postElement.querySelector("button.show-more-actions")?.click();

  const expandedFlagButton = postElement.querySelector("button.create-flag");

  if (expandedFlagButton) {
    expandedFlagButton.click();
    return true;
  }

  if (typeof defer === "function") {
    defer(() => {
      postElement.querySelector("button.create-flag")?.click();
    }, 150);
  }

  return false;
}
