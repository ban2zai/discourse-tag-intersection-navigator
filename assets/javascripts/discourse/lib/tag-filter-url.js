import getURL from "discourse/lib/get-url";
import { makeArray } from "discourse/lib/helpers";

export const TAG_FILTERS = new Set([
  "latest",
  "top",
  "hot",
  "new",
  "unread",
  "unseen",
  "posted",
  "bookmarks",
]);

const FILTER_PATHS = {
  latest: "/latest",
  top: "/top",
  hot: "/hot",
  new: "/new",
  unread: "/unread",
  unseen: "/unseen",
  posted: "/posted",
  bookmarks: "/bookmarks",
};

const CATEGORY_QUERY_FILTERS = new Set(["bookmarks", "posted"]);
const PRESERVED_QUERY_PARAMS = ["order", "ascending", "period"];

export function decodeTagName(value) {
  let decoded = String(value);

  for (let i = 0; i < 3; i++) {
    if (!/%[0-9a-f]{2}/i.test(decoded)) {
      break;
    }

    try {
      const next = decodeURIComponent(decoded);

      if (next === decoded) {
        break;
      }

      decoded = next;
    } catch {
      break;
    }
  }

  return decoded;
}

export function normalizeTagName(tag) {
  const tagName = tag?.name || tag?.slug || tag;

  return typeof tagName === "string" ? decodeTagName(tagName) : tagName;
}

export function tagsFromQueryParam(value) {
  return makeArray(value)
    .flatMap((entry) => {
      const tagName = normalizeTagName(entry);

      return typeof tagName === "string" ? tagName.split(/\s+/) : tagName;
    })
    .map(normalizeTagName)
    .filter(Boolean);
}

export function normalizeTags(tags) {
  return [...new Set(makeArray(tags).map(normalizeTagName).filter(Boolean))];
}

function present(value) {
  return value !== undefined && value !== null && value !== "";
}

function safeFilter(filter) {
  return TAG_FILTERS.has(filter) ? filter : "latest";
}

function categoryId(category) {
  return category?.id || category?.get?.("id") || category;
}

function categoryUrl(category) {
  const url = category?.url || category?.get?.("url");

  if (url) {
    return url;
  }

  const id = categoryId(category);
  const slug = category?.slug || category?.get?.("slug");

  return id && slug ? `/c/${slug}/${id}` : null;
}

export function categoryPathFromUrl(pathname) {
  const path = pathname.replace(/\/l\/[^/]+\/?$/, "").replace(/\/$/, "");

  return /^\/c\/.+\/\d+$/.test(path) ? path : null;
}

export function categoryIdFromPath(pathname) {
  return categoryPathFromUrl(pathname)?.match(/\/(\d+)$/)?.[1] || null;
}

export function filterFromRouteName(routeName) {
  const segments = String(routeName || "").split(".");
  const lastSegment = segments[segments.length - 1];

  if (TAG_FILTERS.has(lastSegment)) {
    return lastSegment;
  }

  if (String(routeName || "").includes("bookmarks")) {
    return "bookmarks";
  }

  if (String(routeName || "").includes("posted")) {
    return "posted";
  }

  return "latest";
}

export function currentTagFilterState(router) {
  const currentRoute = router.currentRoute || {};
  const queryParams = currentRoute.queryParams || {};
  const attributes = currentRoute.attributes || {};
  const category = attributes.category || null;

  return {
    tags: tagsFromQueryParam(queryParams.tags),
    category,
    categoryId: categoryId(category) || queryParams.category,
    categoryPath: categoryUrl(category),
    filter: filterFromRouteName(router.currentRouteName),
    queryParams,
  };
}

export function buildNativeTagFilterUrl({
  filter = "latest",
  tags = null,
  category = null,
  categoryPath = null,
  queryParams = {},
} = {}) {
  const normalizedFilter = safeFilter(filter);
  const selectedTags = normalizeTags(
    tags === null ? tagsFromQueryParam(queryParams.tags) : tags
  );
  const params = new URLSearchParams();
  const pathCategoryUrl = categoryPath || categoryUrl(category);
  const currentCategoryId = categoryId(category) || queryParams.category;
  let path = FILTER_PATHS[normalizedFilter] || FILTER_PATHS.latest;

  if (pathCategoryUrl && !CATEGORY_QUERY_FILTERS.has(normalizedFilter)) {
    path = `${pathCategoryUrl}/l/${normalizedFilter}`;
  } else if (present(currentCategoryId)) {
    params.set("category", currentCategoryId);
  }

  if (selectedTags.length > 0) {
    params.set("tags", selectedTags.join(" "));
    params.set("match_all_tags", "true");
  }

  PRESERVED_QUERY_PARAMS.forEach((key) => {
    if (present(queryParams[key])) {
      params.set(key, queryParams[key]);
    }
  });

  const query = params.toString();

  return getURL(query ? `${path}?${query}` : path);
}

export function nativeUrlForCategoryLink(link, state) {
  const url = new URL(link.href, window.location.origin);
  const categoryPath = categoryPathFromUrl(url.pathname);

  if (!categoryPath) {
    return null;
  }

  const queryParams = {
    ...state.queryParams,
    ...Object.fromEntries(url.searchParams.entries()),
  };

  return buildNativeTagFilterUrl({
    filter: state.filter,
    tags: state.tags,
    category: categoryIdFromPath(categoryPath),
    categoryPath,
    queryParams,
  });
}
