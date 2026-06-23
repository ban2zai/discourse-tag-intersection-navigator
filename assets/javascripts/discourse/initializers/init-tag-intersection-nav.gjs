import { action } from "@ember/object";
import { addDiscoveryQueryParam } from "discourse/controllers/discovery/list";
import { withPluginApi } from "discourse/lib/plugin-api";
import DiscourseURL from "discourse/lib/url";
import Category from "discourse/models/category";
import {
  buildNativeTagFilterUrl,
  currentTagFilterState,
  nativeUrlForCategoryLink,
  TAG_FILTERS,
} from "../lib/tag-filter-url";

const NO_CATEGORIES_ID = "no-categories";
const ALL_CATEGORIES_ID = "all-categories";
let preserveCategoryClickHandler = null;

function registerNativeTagQueryParams() {
  addDiscoveryQueryParam("tags", {
    replace: true,
    refreshModel: true,
    default: null,
    as: "tags",
  });

  addDiscoveryQueryParam("match_all_tags", {
    replace: true,
    refreshModel: true,
    default: null,
    as: "match_all_tags",
  });
}

function shouldHandleClick(event) {
  return (
    !event.defaultPrevented &&
    event.button === 0 &&
    !event.metaKey &&
    !event.ctrlKey &&
    !event.shiftKey &&
    !event.altKey
  );
}

function preserveCategoryLinkClick(event, router) {
  if (!shouldHandleClick(event)) {
    return;
  }

  const state = currentTagFilterState(router);

  if (state.tags.length === 0) {
    return;
  }

  const link = event.target?.closest?.("a[href]");

  if (!link) {
    return;
  }

  const url = new URL(link.href, window.location.origin);

  if (url.origin !== window.location.origin) {
    return;
  }

  const nextUrl = nativeUrlForCategoryLink(link, state);

  if (!nextUrl) {
    return;
  }

  event.preventDefault();
  DiscourseURL.routeToUrl(nextUrl);
}

function rewriteCoreNavigationLinks(router) {
  const state = currentTagFilterState(router);
  let rewritten = 0;

  if (state.tags.length === 0 && !state.categoryId) {
    return rewritten;
  }

  TAG_FILTERS.forEach((filter) => {
    document
      .querySelectorAll(`#navigation-bar li.nav-item_${filter} a`)
      .forEach((link) => {
        link.href = buildNativeTagFilterUrl({
          filter,
          tags: state.tags,
          category: state.category || state.categoryId,
          categoryPath: state.categoryPath,
          queryParams: state.queryParams,
        });
        rewritten += 1;
      });
  });

  return rewritten;
}

function scheduleRewriteCoreNavigationLinks(router, attempts = 4) {
  requestAnimationFrame(() => {
    const rewritten = rewriteCoreNavigationLinks(router);

    if (rewritten === 0 && attempts > 1) {
      setTimeout(
        () => scheduleRewriteCoreNavigationLinks(router, attempts - 1),
        50
      );
    }
  });
}

function legacyIntersectionState(router, allWord) {
  if (!router.currentRouteName?.startsWith("tags.intersection")) {
    return null;
  }

  const params = router.currentRoute?.params || {};
  const queryParams = router.currentRoute?.queryParams || {};
  const rawTags = [
    params.tag_id || params.tag_name || params.tag,
    ...(params.additional_tags ? String(params.additional_tags).split("/") : []),
  ].filter(Boolean);
  const tags = rawTags.filter((tag) => tag !== allWord && tag !== "none");
  const filter = TAG_FILTERS.has(queryParams.int_filter)
    ? queryParams.int_filter
    : "latest";

  return { tags, filter, queryParams };
}

function redirectLegacyIntersectionRoute(router, allWord) {
  const state = legacyIntersectionState(router, allWord);

  if (!state) {
    return false;
  }

  const category =
    state.queryParams.category &&
    Category.findById(parseInt(state.queryParams.category, 10));

  DiscourseURL.routeToUrl(
    buildNativeTagFilterUrl({
      filter: state.filter,
      tags: state.tags,
      category: category || state.queryParams.category,
      queryParams: state.queryParams,
    })
  );

  return true;
}

export default {
  name: "tag-intersection-navigator",

  initialize(container) {
    const router = container.lookup("service:router");
    const siteSettings = container.lookup("service:site-settings");
    const allWord =
      siteSettings.discourse_tag_intersection_navigator_all_word ||
      "everything";

    registerNativeTagQueryParams();

    withPluginApi((api) => {
      if (preserveCategoryClickHandler) {
        document.removeEventListener("click", preserveCategoryClickHandler);
      }

      preserveCategoryClickHandler = (event) => {
        preserveCategoryLinkClick(event, router);
      };
      document.addEventListener("click", preserveCategoryClickHandler);

      api.modifyClass(
        "component:category-drop",
        (Superclass) =>
          class extends Superclass {
            @action
            onChange(categoryId) {
              const state = currentTagFilterState(router);

              if (state.tags.length === 0) {
                return super.onChange(categoryId);
              }

              const category =
                categoryId === ALL_CATEGORIES_ID ||
                categoryId === NO_CATEGORIES_ID
                  ? null
                  : Category.findById(parseInt(categoryId, 10));

              DiscourseURL.routeToUrl(
                buildNativeTagFilterUrl({
                  filter: state.filter,
                  tags: state.tags,
                  category,
                  queryParams: category
                    ? state.queryParams
                    : { ...state.queryParams, category: null },
                })
              );
            }
          }
      );

      api.onPageChange(() => {
        if (redirectLegacyIntersectionRoute(router, allWord)) {
          return;
        }

        scheduleRewriteCoreNavigationLinks(router);
      });
    });
  },
};
