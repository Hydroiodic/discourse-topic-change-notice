# frozen_string_literal: true

module ::DiscourseTopicChangeNotice
  class NoticeCreator
    def initialize(post, revisor)
      @topic = post.topic
      @editor = post.last_editor
      @diff = revisor.topic_diff
    end

    def call
      return if skip?

      changes = collect_changes
      FIELD_GROUPS.each do |fields|
        group_changes = changes.slice(*fields)
        next if group_changes.empty?

        notice = mergeable_notice(fields)
        notice ? merge_into(notice, group_changes) : create(group_changes)
      end
    end

    private

    def skip?
      return true if @editor.nil? || @topic.nil? || @topic.private_message?
      return true if @diff.key?(:archetype)
      return true if @topic.is_category_topic?
      return true if SharedDraft.exists?(topic_id: @topic.id)
      return true if SiteSetting.topic_change_notice_skip_bots && @editor.bot?
      return true if BulkAction.silent?(@editor)
      @editor.in_any_groups?(SiteSetting.topic_change_notice_excluded_groups_map)
    end

    def collect_changes
      changes = {}

      if @diff.key?(:title) && DiscourseTopicChangeNotice.field_enabled?("title")
        changes["title"] = { "from" => @diff[:title][0], "to" => @topic.title }
      end

      if @diff.key?(:category_id) && DiscourseTopicChangeNotice.field_enabled?("category") &&
           @diff[:category_id][0]
        changes["category"] = { "from" => @diff[:category_id][0], "to" => @topic.category_id }
      end

      if @diff.key?(:tags) && DiscourseTopicChangeNotice.field_enabled?("tags")
        hidden = DiscourseTagging.hidden_tag_names
        changes["tags"] = {
          "from" => @diff[:tags][0] - hidden,
          "to" => @topic.tags.reload.map(&:name).sort - hidden,
        }
      end

      changes.reject { |_, change| unchanged?(change) }
    end

    def unchanged?(change)
      from, to = change.values_at("from", "to")
      from.is_a?(Array) ? from.sort == to.sort : from == to
    end

    def mergeable_notice(fields)
      window = SiteSetting.editing_grace_period
      return if window <= 0

      notice =
        @topic
          .posts
          .where(action_code: ACTION_CODE, user_id: @editor.id)
          .where("created_at > ?", window.seconds.ago)
          .order(:post_number)
          .reverse_each
          .find { |post| same_group?(post, fields) }
      return if notice.nil?

      replied_since =
        @topic
          .posts
          .where("post_number > ?", notice.post_number)
          .where.not(post_type: Post.types[:whisper])
          .where(
            "posts.action_code IS DISTINCT FROM ? OR posts.user_id IS DISTINCT FROM ?",
            ACTION_CODE,
            @editor.id,
          )
          .exists?
      notice if !replied_since
    end

    def same_group?(notice, fields)
      data = notice.custom_fields[CUSTOM_FIELD]
      data.present? && (data.keys - fields).empty?
    end

    def merge_into(notice, changes)
      merged = (notice.custom_fields[CUSTOM_FIELD] || {}).deep_dup
      changes.each do |field, change|
        from = merged.key?(field) ? merged[field]["from"] : change["from"]
        merged[field] = { "from" => from, "to" => change["to"] }
      end
      merged.reject! { |_, change| unchanged?(change) }

      if merged.empty?
        destroy(notice)
      else
        notice.custom_fields[CUSTOM_FIELD] = merged
        notice.save_custom_fields(true)
        notice.publish_change_to_clients!(:revised)
      end
    end

    def destroy(notice)
      bumped_at = @topic.reload.bumped_at
      PostDestroyer.new(Discourse.system_user, notice).destroy
      @topic.update_columns(bumped_at:) if @topic.reload.bumped_at != bumped_at
    end

    def create(changes)
      creator =
        PostCreator.new(
          @editor,
          topic_id: @topic.id,
          post_type: Post.types[:small_action],
          action_code: ACTION_CODE,
          raw: "",
          custom_fields: {
            CUSTOM_FIELD => changes,
          },
          guardian: Guardian.new(Discourse.system_user),
          skip_guardian: true,
          skip_validations: true,
          no_bump: true,
          silent: true,
          auto_track: false,
          skip_events: true,
        )
      creator.create
      return if creator.errors.blank?

      Rails.logger.warn(
        "[#{PLUGIN_NAME}] failed to create notice for topic #{@topic.id}: #{creator.errors.full_messages.join(", ")}",
      )
    end
  end
end
