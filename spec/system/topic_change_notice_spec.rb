# frozen_string_literal: true

RSpec.describe "Topic change notice" do
  fab!(:admin)
  fab!(:user)
  fab!(:category)
  fab!(:other_category, :category)
  fab!(:tag) { Fabricate(:tag, name: "foo") }
  fab!(:topic) { Fabricate(:topic, category: category) }
  fab!(:first_post) { Fabricate(:post, topic: topic) }

  before do
    enable_current_plugin
    SiteSetting.topic_change_notice_enabled = true
    SiteSetting.tagging_enabled = true
    SiteSetting.default_locale = "zh_CN"
    sign_in(user)
  end

  def revise(**fields)
    PostRevisor.new(first_post, topic).revise!(admin, fields)
  end

  it "shows the title change apart from the category and tag changes" do
    old_title = topic.title
    revise(
      title: "A completely different topic title",
      category_id: other_category.id,
      tags: ["foo"],
    )

    visit("/t/#{topic.id}")

    expect(page).to have_css(".small-action.topic-change-notice-post", count: 2)
    title_notice, other_notice = all(".small-action.topic-change-notice-post")

    expect(title_notice).to have_css(".topic-change-notice__line", count: 1)
    title_line = title_notice.find(".topic-change-notice__line")
    expect(title_line).to have_css(".relative-date")
    expect(title_line).to have_text("将标题由『#{old_title}』变更为：")
    expect(title_notice).to have_css(
      ".topic-change-notice__new-title",
      text: "A completely different topic title",
    )

    expect(other_notice).to have_css(".topic-change-notice__line", count: 3)
    when_line, category_line, tags_line = other_notice.all(".topic-change-notice__line")
    expect(when_line[:class]).to include("topic-change-notice__when")
    expect(when_line).to have_css(".relative-date")
    expect(when_line.text).to eq(when_line.find(".relative-date").text)
    expect(category_line).to have_text("将分类由")
    expect(category_line).to have_css(".badge-category__name", text: other_category.name)
    expect(category_line).to have_no_css(".relative-date")
    expect(tags_line).to have_text("添加了标签 foo")
    expect(tags_line).to have_no_css(".relative-date")
  end

  it "shows a single category or tag change on the same line as the time" do
    revise(tags: ["foo"])

    visit("/t/#{topic.id}")

    notice = find(".small-action.topic-change-notice-post")
    expect(notice).to have_css(".topic-change-notice__line", count: 1)
    expect(notice).to have_no_css(".topic-change-notice__when")
    line = notice.find(".topic-change-notice__line")
    expect(line).to have_css(".relative-date")
    expect(line).to have_text("添加了标签 foo")
  end
end
