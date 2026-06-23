# frozen_string_literal: true

require "uri"

require_relative "../plugin_helper"

RSpec.describe "Tag Intersection Navigator" do
  let(:discovery) { PageObjects::Pages::Discovery.new }
  let(:tag_filter_chooser) do
    PageObjects::Components::SelectKit.new(".native-tag-filter-chooser")
  end

  fab!(:user)
  fab!(:tag_1) { Fabricate(:tag, name: "test-tag1") }
  fab!(:tag_2) { Fabricate(:tag, name: "test-tag2") }
  fab!(:tag_3) { Fabricate(:tag, name: "test-tag3") }
  fab!(:category)
  fab!(:topic)
  fab!(:topic_1) { Fabricate(:topic, tags: [tag_1]) }
  fab!(:topic_2) { Fabricate(:topic, tags: [tag_1, tag_2], category: category) }
  fab!(:topic_3) { Fabricate(:topic, tags: [tag_1, tag_2, tag_3]) }

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.discourse_tag_intersection_navigator_enabled = true
    SiteSetting.discourse_tag_intersection_navigator_all_word = "bananas"
  end

  def category_filter_path(filter = "latest")
    "/c/#{category.slug}/#{category.id}/l/#{filter}"
  end

  def tags_query(*tags)
    Rack::Utils.build_query(tags: tags.join(" "), match_all_tags: true)
  end

  def current_uri
    URI.parse(page.current_url)
  end

  def current_query
    Rack::Utils.parse_nested_query(current_uri.query.to_s)
  end

  def expect_tag_query(*tags)
    expect(current_query["tags"]).to eq(tags.join(" "))
    expect(current_query["match_all_tags"]).to eq("true")
  end

  def publish_new_topic(tags:, category: nil)
    new_topic = Fabricate(:topic, tags: tags, category: category)
    Fabricate(:post, topic: new_topic)
    TopicTrackingState.publish_new(new_topic)
    new_topic
  end

  describe "native tag filters" do
    it "allows selecting multiple tags from the native filter chooser" do
      visit("/latest")

      expect(tag_filter_chooser).to be_visible
      expect(page).to have_no_css(
        ".category-breadcrumb .tag-drop",
        visible: :visible,
      )

      tag_filter_chooser.expand
      tag_filter_chooser.select_row_by_name("test-tag1")

      expect(current_uri.path).to eq("/latest")
      expect_tag_query("test-tag1")

      tag_filter_chooser.expand if tag_filter_chooser.is_collapsed?
      tag_filter_chooser.select_row_by_name("test-tag2")

      expect(current_uri.path).to eq("/latest")
      expect_tag_query("test-tag1", "test-tag2")
      expect(discovery.topic_list).to have_topic(topic_2)
      expect(discovery.topic_list).to have_topic(topic_3)
      expect(discovery.topic_list).to have_no_topic(topic_1)

      tag_filter_chooser.expand if tag_filter_chooser.is_collapsed?
      tag_filter_chooser.unselect_by_name("test-tag1")

      expect(current_uri.path).to eq("/latest")
      expect_tag_query("test-tag2")
    end

    it "preserves the category route when selecting tags from the chooser" do
      visit(category_filter_path)

      tag_filter_chooser.expand
      tag_filter_chooser.select_row_by_name("test-tag1")

      tag_filter_chooser.expand if tag_filter_chooser.is_collapsed?
      tag_filter_chooser.select_row_by_name("test-tag2")

      expect(current_uri.path).to eq(category_filter_path)
      expect_tag_query("test-tag1", "test-tag2")
      expect(discovery.topic_list).to have_topic(topic_2)
      expect(discovery.topic_list).to have_no_topic(topic_3)
    end

    it "filters latest topics through native tags query params" do
      visit("/latest?#{tags_query("test-tag1", "test-tag2")}")

      expect(discovery.topic_list).to have_topic(topic_2)
      expect(discovery.topic_list).to have_topic(topic_3)
      expect(discovery.topic_list).to have_no_topic(topic)
      expect(discovery.topic_list).to have_no_topic(topic_1)
      expect(discovery.topic_list).to have_topics(count: 2)
    end

    it "filters category topics through native tags query params" do
      visit("#{category_filter_path}?#{tags_query("test-tag1", "test-tag2")}")

      expect(discovery.topic_list).to have_topic(topic_2)
      expect(discovery.topic_list).to have_no_topic(topic_3)
      expect(discovery.topic_list).to have_topics(count: 1)
    end

    it "preserves tag query params when switching core discovery filters" do
      SiteSetting.top_menu = "latest|top"

      visit("/latest?#{tags_query("test-tag1", "test-tag2")}&order=created")

      expect(page).to have_css(
        "#navigation-bar li.nav-item_top a[href*='tags=test-tag1+test-tag2']",
      )

      find("#navigation-bar li.nav-item_top a").click

      expect(current_uri.path).to eq("/top")
      expect_tag_query("test-tag1", "test-tag2")
      expect(current_query["order"]).to eq("created")
    end

    it "preserves tag query params when following category links" do
      visit("/latest?#{tags_query("test-tag1", "test-tag2")}")

      find(".topic-list-item .badge-category__wrapper[href*='/c/']").click

      expect(current_uri.path).to eq(category_filter_path)
      expect_tag_query("test-tag1", "test-tag2")
    end

    it "opens native bookmarks with tag and category filters instead of 404" do
      sign_in(user)

      visit(
        "/bookmarks?#{tags_query("test-tag1", "test-tag2")}&category=#{category.id}",
      )

      expect(page).to have_no_content("Oops")
      expect(current_uri.path).to eq("/bookmarks")
      expect_tag_query("test-tag1", "test-tag2")
      expect(current_query["category"]).to eq(category.id.to_s)
    end

    it "redirects legacy intersection URLs to native URLs" do
      visit(
        "/tags/intersection/test-tag1/test-tag2?category=#{category.id}&int_filter=top&order=created",
      )

      expect(current_uri.path).to eq(category_filter_path("top"))
      expect_tag_query("test-tag1", "test-tag2")
      expect(current_query["order"]).to eq("created")
      expect(page.current_url).not_to include("int_filter")
      expect(page.current_url).not_to include("bananas")
    end

    it "shows incoming count only for topics in the current native tag scope" do
      sign_in(user)
      visit("#{category_filter_path}?#{tags_query("test-tag1", "test-tag2")}")

      expect(discovery.topic_list).to have_topics(count: 1)

      out_of_scope_tag_topic = publish_new_topic(tags: [tag_1], category: category)
      out_of_scope_category_topic = publish_new_topic(tags: [tag_1, tag_2])
      in_scope_topic = publish_new_topic(tags: [tag_1, tag_2], category: category)

      try_until_success(reason: "relies on MessageBus updates") do
        expect(page).to have_css(".show-more", text: /1.*new/)
      end

      find(".show-more").click

      expect(discovery.topic_list).to have_topic(in_scope_topic)
      expect(discovery.topic_list).to have_no_topic(out_of_scope_tag_topic)
      expect(discovery.topic_list).to have_no_topic(out_of_scope_category_topic)
    end
  end
end
