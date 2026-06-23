import { withPluginApi } from "discourse/lib/plugin-api";
import Category from "discourse/models/category";
import TopicTrackingState from "discourse/models/topic-tracking-state";
import {
  filterFromRouteName,
  normalizeTagName,
  tagsFromQueryParam,
} from "../lib/tag-filter-url";

function currentCategory(router) {
  const attributes = router.currentRoute?.attributes || {};
  const queryParams = router.currentRoute?.queryParams || {};

  return (
    attributes.category ||
    (queryParams.category &&
      Category.findById(parseInt(queryParams.category, 10))) ||
    null
  );
}

function tagLookupFromRoute(router, site) {
  const attributes = router.currentRoute?.attributes || {};
  const topicList = attributes.list?.topic_list || {};

  return [
    ...(topicList.tags || []),
    ...(attributes.tags || []),
    ...(site?.tags || []),
  ].filter(Boolean);
}

function tagIdsForNames(tagNames, tagLookup) {
  return tagNames
    .map((tagName) => {
      const normalized = normalizeTagName(tagName);

      return tagLookup.find(
        (tag) =>
          normalizeTagName(tag.name) === normalized ||
          normalizeTagName(tag.slug) === normalized
      )?.id;
    })
    .filter(Boolean);
}

export default {
  name: "native-tag-topic-tracking",
  before: "inject-discourse-objects",

  initialize(container) {
    TopicTrackingState.reopen({
      filterTagIds: null,
      filterTagNames: null,

      trackIncoming(filter, opts = {}) {
        this.setProperties({ filterTagIds: null, filterTagNames: null });
        return this._super(filter, opts);
      },

      trackIncomingTagFilters({
        filter,
        category = null,
        tagIds = [],
        tagNames = [],
      }) {
        this.trackIncoming(filter);
        this.setProperties({
          filterCategory: category,
          filterTagName: null,
          filterTagId: null,
          filterTagIds: tagIds,
          filterTagNames: tagNames,
        });
      },

      notifyIncoming(data) {
        if (!this.filterTagIds && !this.filterTagNames) {
          return this._super(data);
        }

        if (!this.newIncoming) {
          return;
        }

        const filter = this.filter;
        const filterCategory = this.filterCategory;
        const categoryId = data.payload?.category_id;

        if (filterCategory && filterCategory.get("id") !== categoryId) {
          const category = categoryId && Category.findById(categoryId);
          if (
            !category ||
            category.get("parentCategory.id") !== filterCategory.get("id")
          ) {
            return;
          }
        }

        const payloadTags = data.payload?.tags || [];
        const payloadTagIds = payloadTags
          .map((tag) => tag.id)
          .filter(Boolean);
        const payloadTagNames = payloadTags
          .flatMap((tag) => [tag.name, tag.slug])
          .map(normalizeTagName)
          .filter(Boolean);
        const knownTagIdsMatched =
          this.filterTagIds?.length > 0 &&
          this.filterTagIds.every((tagId) => payloadTagIds.includes(tagId));

        if (this.filterTagIds?.length > 0 && !knownTagIdsMatched) {
          return;
        }

        if (
          this.filterTagNames?.length > 0 &&
          this.filterTagIds?.length !== this.filterTagNames.length &&
          !this.filterTagNames.every((tagName) =>
            payloadTagNames.includes(normalizeTagName(tagName))
          )
        ) {
          return;
        }

        if (
          ["all", "latest", "new", "unseen"].includes(filter) &&
          data.message_type === "new_topic"
        ) {
          this._addIncoming(data.topic_id);
        }

        const unreadRecipients = ["all", "unread", "unseen"];
        if (this.currentUser?.new_new_view_enabled) {
          unreadRecipients.push("new");
        }

        if (
          unreadRecipients.includes(filter) &&
          data.message_type === "unread"
        ) {
          const old = this.findState(data);

          if (!old || old.highest_post_number === old.last_read_post_number) {
            this._addIncoming(data.topic_id);
          }
        }

        if (filter === "latest" && data.message_type === "latest") {
          this._addIncoming(data.topic_id);
        }

        this.incomingCount = this.newIncoming.length;
      },
    });

    withPluginApi((api) => {
      const router = container.lookup("service:router");
      const site = container.lookup("service:site");

      api.onPageChange(() => {
        const tagNames = tagsFromQueryParam(
          router.currentRoute?.queryParams?.tags
        );

        if (tagNames.length === 0) {
          return;
        }

        const tracking = container.lookup("service:topic-tracking-state");
        const tagLookup = tagLookupFromRoute(router, site);

        tracking.trackIncomingTagFilters({
          filter: filterFromRouteName(router.currentRouteName),
          category: currentCategory(router),
          tagIds: tagIdsForNames(tagNames, tagLookup),
          tagNames,
        });
      });
    });
  },
};
