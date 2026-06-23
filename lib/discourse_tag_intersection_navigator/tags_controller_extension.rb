# frozen_string_literal: true

require "cgi"

module DiscourseTagIntersectionNavigator
  module TagsControllerExtension
    SUPPORTED_FILTERS = %w[latest top hot new unread unseen posted bookmarks].freeze
    QUERY_PARAMS_TO_KEEP = %i[order ascending period].freeze
    CATEGORY_QUERY_FILTERS = %w[bookmarks posted].freeze

    def show
      return super unless legacy_intersection_request?

      redirect_to legacy_intersection_redirect_url, status: :moved_permanently
    end

    private

    def legacy_intersection_request?
      request.path.start_with?("/tags/intersection/")
    end

    def legacy_intersection_redirect_url
      filter = legacy_intersection_filter
      category = legacy_intersection_category
      query = legacy_intersection_query(filter, category)
      path = legacy_intersection_path(filter, category)

      query.present? ? "#{path}?#{query.to_query}" : path
    end

    def legacy_intersection_path(filter, category)
      if category.present? && !CATEGORY_QUERY_FILTERS.include?(filter)
        "#{category.url}/l/#{filter}"
      else
        "/#{filter}"
      end
    end

    def legacy_intersection_query(filter, category)
      query = {}
      tags = legacy_intersection_tags

      if tags.present?
        query[:tags] = tags.join(" ")
        query[:match_all_tags] = true
      end

      if params[:category].present? &&
           (category.blank? || CATEGORY_QUERY_FILTERS.include?(filter))
        query[:category] = params[:category]
      end

      QUERY_PARAMS_TO_KEEP.each do |key|
        query[key] = params[key] if params[key].present?
      end

      query
    end

    def legacy_intersection_filter
      filter = params[:int_filter].presence.to_s

      SUPPORTED_FILTERS.include?(filter) ? filter : "latest"
    end

    def legacy_intersection_category
      return if params[:category].blank?

      Category.find_by(id: params[:category].to_i)
    end

    def legacy_intersection_tags
      all_word = SiteSetting.discourse_tag_intersection_navigator_all_word

      request.path
        .delete_prefix("/tags/intersection/")
        .split("/")
        .map { |segment| decode_legacy_tag_segment(segment) }
        .reject { |tag| tag.blank? || tag == all_word || tag == "none" }
    end

    def decode_legacy_tag_segment(segment)
      decoded = segment.to_s

      3.times do
        break unless decoded.match?(/%[0-9a-f]{2}/i)

        next_decoded = CGI.unescape(decoded)
        break if next_decoded == decoded

        decoded = next_decoded
      rescue ArgumentError
        break
      end

      decoded
    end
  end
end
