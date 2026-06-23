import Component from "@glimmer/component";
import { hash } from "@ember/helper";
import { service } from "@ember/service";
import TagsIntersectionChooser from "discourse/select-kit/components/tags-intersection-chooser";
import {
  currentTagFilterState,
  normalizeTagName,
  tagsFromQueryParam,
} from "../../lib/tag-filter-url";

export default class NativeTagFilterChooserConnector extends Component {
  static shouldRender(args, context, owner) {
    const router = owner.lookup("service:router");

    return (
      context.siteSettings.discourse_tag_intersection_navigator_enabled &&
      context.siteSettings.tagging_enabled &&
      args.showTagsSection &&
      !args.editingCategory &&
      router.currentRouteName !== "discovery.categories"
    );
  }

  @service router;
  @service site;

  get tags() {
    const queryTags = tagsFromQueryParam(
      this.router.currentRoute?.queryParams?.tags
    );

    return queryTags.length > 0 ? queryTags : this.outletTags;
  }

  get outletTags() {
    const mainTag = normalizeTagName(this.args.outletArgs.tag);
    const additionalTags = []
      .concat(this.args.outletArgs.additionalTags || [])
      .map(normalizeTagName);

    return [mainTag, ...additionalTags].filter(Boolean);
  }

  get tagLookup() {
    const attributes = this.router.currentRoute?.attributes || {};
    const topicList = attributes.list?.topic_list || {};

    return [
      ...(topicList.tags || []),
      ...(attributes.tags || []),
      ...(this.site?.tags || []),
    ].filter(Boolean);
  }

  tagForName(tagName) {
    const normalized = normalizeTagName(tagName);

    return this.tagLookup.find(
      (tag) =>
        normalizeTagName(tag.name) === normalized ||
        normalizeTagName(tag.slug) === normalized
    );
  }

  get selectedTags() {
    return this.tags.map((tagName) => this.tagForName(tagName) || tagName);
  }

  get mainTag() {
    return this.selectedTags[0] || null;
  }

  get additionalTags() {
    return this.selectedTags.slice(1);
  }

  get state() {
    return currentTagFilterState(this.router);
  }

  get categoryId() {
    return (
      this.args.outletArgs.currentCategory?.id ||
      this.args.outletArgs.currentCategory?.get?.("id") ||
      this.state.categoryId ||
      null
    );
  }

  <template>
    <TagsIntersectionChooser
      @currentCategory={{@outletArgs.currentCategory}}
      @mainTag={{this.mainTag}}
      @additionalTags={{this.additionalTags}}
      @options={{hash categoryId=this.categoryId}}
      class="native-tag-filter-chooser"
    />
  </template>
}
