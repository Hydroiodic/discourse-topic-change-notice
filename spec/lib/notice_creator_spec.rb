# frozen_string_literal: true

RSpec.describe DiscourseTopicChangeNotice::NoticeCreator do
  fab!(:admin)
  fab!(:author, :user)
  fab!(:category)
  fab!(:other_category, :category)
  fab!(:tag_foo) { Fabricate(:tag, name: "foo") }
  fab!(:tag_bar) { Fabricate(:tag, name: "bar") }
  fab!(:topic) { Fabricate(:topic, user: author, category: category, tags: [tag_foo]) }
  fab!(:first_post) { Fabricate(:post, topic: topic, user: author) }

  let(:old_title) { topic.title }

  before do
    enable_current_plugin
    SiteSetting.topic_change_notice_enabled = true
    SiteSetting.tagging_enabled = true
  end

  def notices
    Post.where(topic_id: topic.id, action_code: "topic_change_notice").order(:post_number)
  end

  def notice_data(notice = notices.last)
    notice.custom_fields["topic_change_notice"]
  end

  def revise(editor = admin, **fields)
    PostRevisor.new(first_post, topic).revise!(editor, fields)
  end

  it "posts a small action by the editor when the title changes" do
    title = old_title

    expect { revise(title: "A completely different topic title") }.to change { notices.count }.by(1)

    notice = notices.last
    expect(notice.post_type).to eq(Post.types[:small_action])
    expect(notice.user_id).to eq(admin.id)
    expect(notice.raw).to eq("")
    expect(notice_data).to eq(
      "title" => {
        "from" => title,
        "to" => "A completely different topic title",
      },
    )
  end

  it "posts the title on its own and the category and tags together" do
    title = old_title

    revise(
      title: "A completely different topic title",
      category_id: other_category.id,
      tags: %w[foo bar],
    )

    expect(notices.count).to eq(2)
    expect(notice_data(notices.first)).to eq(
      "title" => {
        "from" => title,
        "to" => "A completely different topic title",
      },
    )
    expect(notice_data(notices.last)).to eq(
      "category" => {
        "from" => category.id,
        "to" => other_category.id,
      },
      "tags" => {
        "from" => ["foo"],
        "to" => %w[bar foo],
      },
    )
  end

  it "posts notices for edits by the topic author too" do
    revise(author, title: "A completely different topic title")
    expect(notices.last.user_id).to eq(author.id)
  end

  it "does not bump the topic, track it for the editor or change the last poster" do
    freeze_time
    topic.update_columns(bumped_at: 1.day.ago, last_post_user_id: author.id)

    revise(title: "A completely different topic title")
    topic.reload

    expect(topic.bumped_at).to eq_time(1.day.ago)
    expect(topic.last_post_user_id).to eq(author.id)
    expect(TopicUser.find_by(topic: topic, user: admin)&.posted).to be_falsey
  end

  it "still posts the notice when slow mode would block the editor from posting" do
    SiteSetting.slow_mode_prevents_editing = false
    topic.update!(slow_mode_seconds: 600)
    Fabricate(:post, topic: topic, user: author)

    expect { revise(author, title: "A completely different topic title") }.to change {
      notices.count
    }.by(1)
  end

  describe "merging within the editing grace period" do
    before { SiteSetting.editing_grace_period = 300 }

    it "updates the previous notice and keeps the original value" do
      title = old_title
      revise(title: "The first new title for this topic")
      revise(title: "The second new title for this topic")

      expect(notices.count).to eq(1)
      expect(notice_data["title"]).to eq(
        "from" => title,
        "to" => "The second new title for this topic",
      )
    end

    it "adds a newly changed tag list to the previous category notice" do
      revise(category_id: other_category.id)
      revise(tags: %w[foo bar])

      expect(notices.count).to eq(1)
      expect(notice_data.keys).to contain_exactly("category", "tags")
    end

    it "merges the title and the category notices separately" do
      title = old_title
      revise(title: "The first new title for this topic", category_id: other_category.id)
      title_notice, category_notice = notices.to_a

      revise(title: "The second new title for this topic")
      expect(notices.count).to eq(2)
      expect(notice_data(title_notice.reload)["title"]).to eq(
        "from" => title,
        "to" => "The second new title for this topic",
      )

      revise(category_id: category.id)
      expect(notices.pluck(:id)).to eq([title_notice.id])
      expect(Post.with_deleted.find(category_notice.id).deleted_at).to be_present
    end

    it "soft deletes the notice and keeps bumped_at when the change is reverted" do
      freeze_time
      topic.update_columns(bumped_at: 1.day.ago)
      title = old_title

      revise(title: "The first new title for this topic")
      notice = notices.last
      revise(title: title)

      expect(notices.count).to eq(0)
      expect(Post.with_deleted.find(notice.id).deleted_at).to be_present
      expect(topic.reload.bumped_at).to eq_time(1.day.ago)
    end

    it "does not merge once someone has replied" do
      revise(title: "The first new title for this topic")
      Fabricate(:post, topic: topic)
      revise(title: "The second new title for this topic")

      expect(notices.count).to eq(2)
    end

    it "does not merge once the editor has replied" do
      revise(title: "The first new title for this topic")
      Fabricate(:post, topic: topic, user: admin)
      revise(title: "The second new title for this topic")

      expect(notices.count).to eq(2)
    end

    it "does not merge across a notice by another editor" do
      revise(title: "The first new title for this topic")
      revise(Fabricate(:moderator), category_id: other_category.id)
      revise(title: "The second new title for this topic")

      expect(notices.count).to eq(3)
    end

    it "does not merge edits from a different editor" do
      revise(title: "The first new title for this topic")
      revise(Fabricate(:moderator), title: "The second new title for this topic")

      expect(notices.count).to eq(2)
    end

    it "does not merge after the grace period" do
      freeze_time
      revise(title: "The first new title for this topic")
      freeze_time 301.seconds.from_now
      revise(title: "The second new title for this topic")

      expect(notices.count).to eq(2)
    end
  end

  describe "tags" do
    it "leaves hidden tags out of the notice" do
      create_hidden_tags(["secret"])

      expect { revise(tags: %w[foo secret]) }.not_to change { notices.count }

      revise(tags: %w[foo bar secret])
      expect(notice_data["tags"]).to eq("from" => ["foo"], "to" => %w[bar foo])
    end
  end

  describe "bulk actions" do
    fab!(:moderator)
    fab!(:leader) { Fabricate(:user, trust_level: TrustLevel[4], refresh_auto_groups: true) }

    def bulk(user, type, **operation)
      TopicsBulkAction.new(user, [topic.id], type: type, **operation).perform!
    end

    it "posts no notice for bulk category and tag changes by an admin" do
      expect {
        expect(bulk(admin, "change_category", category_id: other_category.id)).to eq([topic.id])
        expect(bulk(admin, "change_tags", tag_ids: [tag_bar.id])).to eq([topic.id])
        expect(bulk(admin, "append_tags", tag_ids: [tag_foo.id])).to eq([topic.id])
        expect(bulk(admin, "manage_tags", remove_tag_ids: [tag_bar.id])).to eq([topic.id])
        expect(bulk(admin, "remove_tags")).to eq([topic.id])
      }.not_to change { notices.count }

      expect(topic.reload.category_id).to eq(other_category.id)
      expect(topic.tags).to be_empty
    end

    it "posts no notice for bulk changes by a moderator or a TL4 user" do
      expect {
        bulk(moderator, "change_category", category_id: other_category.id)
        bulk(leader, "change_tags", tag_ids: [tag_bar.id])
      }.not_to change { notices.count }

      expect(topic.reload.category_id).to eq(other_category.id)
      expect(topic.tags.map(&:name)).to eq(["bar"])
    end

    it "sends no core whisper for a bulk category change either" do
      SiteSetting.create_post_for_category_and_tag_changes = true
      SiteSetting.whispers_allowed_groups = Group::AUTO_GROUPS[:staff].to_s

      bulk(admin, "change_category", category_id: other_category.id)

      expect(topic.posts.where(action_code: %w[category_changed topic_change_notice])).to be_empty
    end

    it "posts notices for bulk changes by other users" do
      author.update!(trust_level: TrustLevel[2])
      Group.refresh_automatic_groups!

      bulk(author, "change_tags", tag_ids: [tag_bar.id])
      expect(notice_data).to eq("tags" => { "from" => ["foo"], "to" => ["bar"] })

      bulk(author, "change_category", category_id: other_category.id)
      expect(notice_data).to eq(
        "category" => {
          "from" => category.id,
          "to" => other_category.id,
        },
        "tags" => {
          "from" => ["foo"],
          "to" => ["bar"],
        },
      )
    end

    it "posts notices again for edits after a bulk action" do
      bulk(admin, "change_tags", tag_ids: [tag_bar.id])

      expect { revise(title: "A completely different topic title") }.to change { notices.count }.by(
        1,
      )
    end

    it "posts notices again when a bulk action raises" do
      expect { bulk(admin, "not_an_operation") }.to raise_error(Discourse::InvalidParameters)

      expect { revise(title: "A completely different topic title") }.to change { notices.count }.by(
        1,
      )
    end
  end

  describe "skipped changes" do
    it "skips edits by the system user" do
      expect { revise(Discourse.system_user, title: "A completely different topic title") }.not_to(
        change { notices.count },
      )
    end

    it "posts for the system user when skip_bots is off" do
      SiteSetting.topic_change_notice_skip_bots = false

      expect {
        revise(Discourse.system_user, title: "A completely different topic title")
      }.to change { notices.count }.by(1)
    end

    it "skips edits by members of excluded groups" do
      group = Fabricate(:group)
      group.add(admin)
      SiteSetting.topic_change_notice_excluded_groups = group.id.to_s

      expect { revise(title: "A completely different topic title") }.not_to change { notices.count }
    end

    it "skips fields that are turned off" do
      SiteSetting.topic_change_notice_title_enabled = false
      revise(title: "A completely different topic title", category_id: other_category.id)

      expect(notice_data.keys).to eq(["category"])
    end

    it "does nothing when the plugin is disabled" do
      SiteSetting.topic_change_notice_enabled = false

      expect { revise(title: "A completely different topic title") }.not_to change { notices.count }
    end

    it "skips converting a topic to a personal message and back" do
      expect { TopicConverter.new(topic, admin).convert_to_private_message }.not_to change {
        notices.count
      }
      expect {
        TopicConverter.new(topic.reload, admin).convert_to_public_topic(category.id)
      }.not_to change { notices.count }
    end

    it "skips publishing a shared draft" do
      shared_drafts_category = Fabricate(:category)
      SiteSetting.shared_drafts_category = shared_drafts_category.id
      topic.update!(category: shared_drafts_category)
      Fabricate(:shared_draft, topic: topic, category: other_category)

      expect { TopicPublisher.new(topic, admin, other_category.id).publish! }.not_to change {
        notices.count
      }
    end
  end

  describe "guardian" do
    fab!(:moderator) { Fabricate(:moderator, refresh_auto_groups: true) }

    it "only lets staff edit or delete a notice" do
      revise(author, title: "A completely different topic title")
      notice = notices.last

      expect(Guardian.new(author).can_edit?(notice)).to eq(false)
      expect(Guardian.new(author).can_delete?(notice)).to eq(false)
      expect(Guardian.new(moderator).can_edit?(notice)).to eq(true)
      expect(Guardian.new(moderator).can_delete?(notice)).to eq(true)
    end
  end

  describe "core whispers for category and tag changes" do
    before do
      SiteSetting.create_post_for_category_and_tag_changes = true
      SiteSetting.whispers_allowed_groups = Group::AUTO_GROUPS[:staff].to_s
    end

    def core_whispers
      Post.where(topic_id: topic.id, action_code: %w[category_changed tags_changed])
    end

    it "skips them while the plugin covers the field" do
      revise(category_id: other_category.id)
      expect(core_whispers.count).to eq(0)
    end

    it "keeps them when suppression is off" do
      SiteSetting.topic_change_notice_suppress_core_whispers = false
      revise(category_id: other_category.id)
      expect(core_whispers.count).to eq(1)
    end
  end
end
