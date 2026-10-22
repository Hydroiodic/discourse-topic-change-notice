# frozen_string_literal: true
# name: discourse-topic-change-notice
# about: 话题的标题、分类或标签变更时，在帖子流中公示修改内容
# version: 0.1.0
# authors: Hydroiodic
# url: https://github.com/ShuiyuanSJTU/discourse-topic-change-notice

enabled_site_setting :topic_change_notice_enabled

register_asset "stylesheets/common/topic-change-notice.scss"
register_svg_icon "pen-to-square" if respond_to?(:register_svg_icon)

module ::DiscourseTopicChangeNotice
  PLUGIN_NAME = "discourse-topic-change-notice"
  ACTION_CODE = "topic_change_notice"
  CUSTOM_FIELD = "topic_change_notice"
  FIELDS = %w[title category tags].freeze
  # 标题单独发一条公示，分类和标签合成一条
  FIELD_GROUPS = [%w[title], %w[category tags]].freeze

  def self.field_enabled?(field)
    SiteSetting.topic_change_notice_enabled &&
      SiteSetting.get("topic_change_notice_#{field}_enabled")
  end

  def self.notice?(post)
    post&.action_code == ACTION_CODE
  end
end

require_relative "lib/discourse_topic_change_notice/notice_creator"
require_relative "lib/discourse_topic_change_notice/notice_presenter"
require_relative "lib/discourse_topic_change_notice/slow_mode"
require_relative "lib/discourse_topic_change_notice/bulk_action"
require_relative "lib/discourse_topic_change_notice/consecutive_replies"

after_initialize do
  Post.register_custom_field_type(DiscourseTopicChangeNotice::CUSTOM_FIELD, :json)
  topic_view_post_custom_fields_allowlister { [DiscourseTopicChangeNotice::CUSTOM_FIELD] }

  # 编辑器、话题标题栏、单独改标签、批量操作最终都走 PostRevisor#revise!，修改成功后触发这个事件
  on(:post_edited) do |post, topic_changed, revisor|
    next if !topic_changed || !post.is_first_post?
    DiscourseTopicChangeNotice::NoticeCreator.new(post, revisor).call
  end

  add_to_serializer(
    :post,
    :topic_change_notice,
    include_condition: -> { DiscourseTopicChangeNotice.notice?(object) },
  ) do
    DiscourseTopicChangeNotice::NoticePresenter.new(
      post_custom_fields[DiscourseTopicChangeNotice::CUSTOM_FIELD],
      scope,
    ).as_json
  end

  # core 的 create_post_for_category_and_tag_changes 会为同一次修改再发一条密语
  module OverrideCoreChangeWhispers
    def create_small_action_for_category_change(**kwargs)
      return if suppress_core_whisper?("category")
      super
    end

    def create_small_action_for_tag_changes(**kwargs)
      return if suppress_core_whisper?("tags")
      super
    end

    private

    def suppress_core_whisper?(field)
      SiteSetting.topic_change_notice_suppress_core_whispers &&
        DiscourseTopicChangeNotice.field_enabled?(field)
    end
  end

  # 公示只允许 staff 编辑或删除，否则修改者可以自己抹掉记录
  module OverrideNoticeGuardian
    def can_edit_post?(post)
      return false if protected_notice?(post)
      super
    end

    def can_delete_post?(post)
      return false if protected_notice?(post)
      super
    end

    private

    def protected_notice?(post)
      SiteSetting.topic_change_notice_enabled && !is_staff? &&
        DiscourseTopicChangeNotice.notice?(post)
    end
  end

  ::PostRevisor.singleton_class.prepend OverrideCoreChangeWhispers
  ::Guardian.prepend OverrideNoticeGuardian
  ::PostCreator.prepend DiscourseTopicChangeNotice::SlowMode::PostCreatorExtension
  ::Guardian.prepend DiscourseTopicChangeNotice::SlowMode::GuardianExtension
  ::TopicsBulkAction.prepend DiscourseTopicChangeNotice::BulkAction::TopicsBulkActionExtension
  ::PostValidator.prepend DiscourseTopicChangeNotice::ConsecutiveReplies::PostValidatorExtension
end
