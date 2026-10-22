# frozen_string_literal: true

module ::DiscourseTopicChangeNotice
  module BulkAction
    ACTOR_KEY = :topic_change_notice_bulk_actor_id

    def self.silent_actor?(user)
      user.present? && (user.staff? || user.trust_level >= TrustLevel[4])
    end

    def self.silent?(editor)
      editor.present? && Thread.current[ACTOR_KEY] == editor.id
    end

    def self.silencing(user)
      previous = Thread.current[ACTOR_KEY]
      Thread.current[ACTOR_KEY] = user.id
      yield
    ensure
      Thread.current[ACTOR_KEY] = previous
    end

    module TopicsBulkActionExtension
      def perform!
        return super if !BulkAction.silent_actor?(@user)
        BulkAction.silencing(@user) { super }
      end
    end
  end
end
