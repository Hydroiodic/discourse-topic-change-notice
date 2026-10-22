# frozen_string_literal: true

module ::DiscourseTopicChangeNotice
  module ConsecutiveReplies
    WINDOW_SQL = <<~SQL
      SELECT user_id, action_code
        FROM posts
       WHERE deleted_at IS NULL
         AND NOT hidden
         AND topic_id = :topic_id
         %{without_notices}
       ORDER BY post_number DESC
       LIMIT :max_replies
    SQL

    def self.notice_in_window?(post)
      return false if !SiteSetting.topic_change_notice_enabled || post.id || post.topic_id.nil?
      return false if SiteSetting.max_consecutive_replies == 0
      window(post, without_notices: "").any? { |row| row.action_code == ACTION_CODE }
    end

    def self.user_posts_count(post)
      rows = window(post, without_notices: "AND action_code IS DISTINCT FROM :action_code")
      rows.count { |row| row.user_id == post.acting_user.id }
    end

    def self.last_post(topic)
      topic.ordered_posts.where("posts.action_code IS DISTINCT FROM ?", ACTION_CODE).last
    end

    def self.window(post, without_notices:)
      DB.query(
        format(WINDOW_SQL, without_notices:),
        topic_id: post.topic_id,
        max_replies: SiteSetting.max_consecutive_replies,
        action_code: ACTION_CODE,
      )
    end

    # 窗口里没有公示时结果和 core 完全相同，直接交给 core；否则按 core 的步骤重算，只是窗口和最后一帖都不算公示。
    # optimized-privilege 也覆盖了这个方法，按目录名加载时它包在外层，它豁免的分类和标签照常先返回
    module PostValidatorExtension
      def force_edit_last_validator(post)
        return super if !ConsecutiveReplies.notice_in_window?(post)
        return if private_message?(post)
        return if post.acting_user&.staff?

        topic = post.topic
        return if topic&.ordered_posts&.first&.user == post.user

        guardian = Guardian.new(post.acting_user)
        return if guardian.is_category_group_moderator?(post.topic&.category)

        max = SiteSetting.max_consecutive_replies
        return if ConsecutiveReplies.user_posts_count(post) < max

        if guardian.can_edit?(ConsecutiveReplies.last_post(topic))
          post.errors.add(:base, I18n.t(:max_consecutive_replies, count: max))
        end
      end
    end
  end
end
