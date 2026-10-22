# frozen_string_literal: true

RSpec.describe DiscourseTopicChangeNotice::SlowMode do
  fab!(:admin)
  fab!(:author, :user)
  fab!(:editor) { Fabricate(:user, trust_level: TrustLevel[4], refresh_auto_groups: true) }
  fab!(:topic) { Fabricate(:topic, user: author) }
  fab!(:first_post) { Fabricate(:post, topic: topic, user: author) }

  before do
    enable_current_plugin
    SiteSetting.topic_change_notice_enabled = true
    SiteSetting.slow_mode_prevents_editing = false

    freeze_time
    topic.update!(slow_mode_seconds: 1.hour.to_i)
    first_post.update_columns(created_at: 1.day.ago, last_version_at: 1.day.ago)
  end

  def notices
    Post.where(topic_id: topic.id, action_code: "topic_change_notice")
  end

  def edit_title(user = editor)
    PostRevisor.new(first_post, topic).revise!(user, title: "A completely different topic title")
  end

  def reply(user = editor)
    @reply_count = (@reply_count || 0) + 1
    creator =
      PostCreator.new(
        user,
        topic_id: topic.id,
        raw: "This is reply number #{@reply_count}, long enough to be posted.",
      )
    creator.create
    creator
  end

  def expect_reply_allowed(user = editor)
    expect(reply(user).errors).to be_blank
  end

  def expect_reply_rejected(user = editor)
    expect(reply(user).errors.full_messages).to contain_exactly(I18n.t(:slow_mode_enabled))
  end

  it "lets the editor reply right after the notice when the last reply is old enough" do
    Fabricate(:post, topic: topic, user: editor, created_at: 2.hours.ago)

    expect { edit_title }.to change { notices.count }.by(1)
    expect_reply_allowed
  end

  it "still posts the notice right after a reply and counts the wait from that reply" do
    Fabricate(:post, topic: topic, user: editor, created_at: 10.minutes.ago)

    expect { edit_title }.to change { notices.count }.by(1)
    expect_reply_rejected

    freeze_time(49.minutes.from_now)
    expect_reply_rejected

    # 距那条回复满一小时，距公示才 50 分钟
    freeze_time(1.minute.from_now)
    expect_reply_allowed
  end

  it "lets an editor who has only a notice in the topic reply" do
    expect { edit_title }.to change { notices.count }.by(1)
    expect_reply_allowed
  end

  it "blocks consecutive replies as before" do
    expect_reply_allowed
    expect_reply_rejected
  end

  it "keeps the notice in the count when the plugin is disabled" do
    edit_title
    SiteSetting.topic_change_notice_enabled = false
    expect_reply_rejected
  end

  it "does not change slow_mode_prevents_editing" do
    edit_title
    expect_reply_allowed
    expect(Guardian.new(editor).affected_by_slow_mode?(topic)).to eq(true)

    SiteSetting.slow_mode_prevents_editing = true
    first_post.update_columns(last_version_at: 1.day.ago)
    revisor = PostRevisor.new(first_post, topic)

    expect(revisor.revise!(editor, title: "Another completely different topic title")).to eq(false)
    expect(first_post.errors.full_messages).to include(I18n.t("cannot_edit_on_slow_mode"))
  end

  it "does not affect staff" do
    edit_title(admin)
    expect_reply_allowed(admin)
    expect_reply_allowed(admin)
  end
end
