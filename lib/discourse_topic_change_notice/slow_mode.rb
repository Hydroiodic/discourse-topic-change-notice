# frozen_string_literal: true

module ::DiscourseTopicChangeNotice
  module SlowMode
    SKIP_CHECK_KEY = :topic_change_notice_skip_slow_mode_topic_id

    def self.last_posted_at(topic, user)
      topic
        .posts
        .where(user_id: user.id)
        .where("posts.action_code IS DISTINCT FROM ?", ACTION_CODE)
        .order(created_at: :desc)
        .pick(:created_at)
    end

    def self.skip_check?(topic)
      topic.present? && Thread.current[SKIP_CHECK_KEY] == topic.id
    end

    def self.skipping_check(topic)
      previous = Thread.current[SKIP_CHECK_KEY]
      Thread.current[SKIP_CHECK_KEY] = topic.id
      yield
    ensure
      Thread.current[SKIP_CHECK_KEY] = previous
    end

    module PostCreatorExtension
      def valid?
        return super if new_topic? || !SiteSetting.topic_change_notice_enabled

        topic = Topic.find_by(id: @opts[:topic_id])
        return super if !guardian.affected_by_slow_mode?(topic)

        last_posted_at = SlowMode.last_posted_at(topic, @user)
        if last_posted_at && Time.zone.now < last_posted_at + topic.slow_mode_seconds.seconds
          return super
        end

        SlowMode.skipping_check(topic) { super }
      end
    end

    module GuardianExtension
      def affected_by_slow_mode?(topic)
        return false if SlowMode.skip_check?(topic)
        super
      end
    end
  end
end
