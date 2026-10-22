# frozen_string_literal: true

RSpec.describe DiscourseTopicChangeNotice::ConsecutiveReplies do
  fab!(:admin)
  fab!(:author, :user)
  fab!(:editor) { Fabricate(:user, trust_level: TrustLevel[4], refresh_auto_groups: true) }
  fab!(:topic) { Fabricate(:topic, user: author) }
  fab!(:first_post) { Fabricate(:post, topic: topic, user: author) }

  before do
    enable_current_plugin
    SiteSetting.topic_change_notice_enabled = true
    SiteSetting.max_consecutive_replies = 3
  end

  def notices
    Post.where(topic_id: topic.id, action_code: "topic_change_notice")
  end

  def edit_title(user = editor)
    @title_count = (@title_count || 0) + 1
    expect {
      PostRevisor.new(first_post, topic).revise!(
        user,
        title: "A completely different topic title number #{@title_count}",
      )
    }.to change { notices.count }.by(1)
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
    expect(reply(user).errors.full_messages).to contain_exactly(
      I18n.t(:max_consecutive_replies, count: 3),
    )
  end

  it "does not count a notice as one of the editor's replies" do
    expect_reply_allowed
    edit_title
    expect_reply_allowed
    expect_reply_allowed
    expect_reply_rejected
  end

  it "allows the third reply after two replies and a notice" do
    2.times { expect_reply_allowed }
    edit_title
    expect_reply_allowed
  end

  it "still applies the limit when the last post is a notice" do
    3.times { expect_reply_allowed }
    edit_title
    expect_reply_rejected
  end

  it "does not let notices break a streak" do
    expect_reply_allowed
    edit_title
    expect_reply_allowed
    edit_title
    expect_reply_allowed
    expect_reply_rejected
  end

  it "keeps the limit for others' replies as in core" do
    2.times { expect_reply_allowed }
    edit_title
    expect_reply_allowed(Fabricate(:user, refresh_auto_groups: true))
    expect_reply_allowed
  end

  it "does not limit staff or the topic author" do
    3.times { expect_reply_allowed(admin) }
    edit_title(admin)
    expect_reply_allowed(admin)

    author.update!(trust_level: TrustLevel[4])
    Group.refresh_automatic_groups!
    3.times { expect_reply_allowed(author) }
    edit_title(author)
    expect_reply_allowed(author)
  end

  it "behaves as core when the plugin is disabled" do
    expect_reply_allowed
    edit_title
    expect_reply_allowed

    SiteSetting.topic_change_notice_enabled = false
    expect_reply_rejected
  end
end
