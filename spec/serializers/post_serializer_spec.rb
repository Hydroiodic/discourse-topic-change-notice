# frozen_string_literal: true

RSpec.describe PostSerializer do
  fab!(:admin)
  fab!(:user)
  fab!(:group)
  fab!(:member, :user)
  fab!(:private_category) { Fabricate(:private_category, group: group) }
  fab!(:public_category, :category)
  fab!(:topic) { Fabricate(:topic, category: private_category) }
  fab!(:first_post) { Fabricate(:post, topic: topic) }

  before do
    enable_current_plugin
    SiteSetting.topic_change_notice_enabled = true
    group.add(member)
    PostRevisor.new(first_post, topic).revise!(admin, category_id: public_category.id)
  end

  let(:notice) { Post.find_by(topic_id: topic.id, action_code: "topic_change_notice") }

  def serialize(post, viewer)
    PostSerializer.new(post, scope: Guardian.new(viewer), root: false).as_json
  end

  it "hides categories the viewer cannot see" do
    change = serialize(notice, user)[:topic_change_notice]["category"]

    expect(change["from"]).to be_nil
    expect(change["to"]).to eq("id" => public_category.id, "name" => public_category.name)
  end

  it "shows categories the viewer can see" do
    change = serialize(notice, member)[:topic_change_notice]["category"]

    expect(change["from"]).to eq("id" => private_category.id, "name" => private_category.name)
  end

  it "is only included for notices" do
    expect(serialize(first_post, user)).not_to have_key(:topic_change_notice)
  end
end
