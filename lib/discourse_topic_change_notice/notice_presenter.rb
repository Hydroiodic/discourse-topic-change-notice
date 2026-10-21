# frozen_string_literal: true

module ::DiscourseTopicChangeNotice
  class NoticePresenter
    def initialize(data, guardian)
      @data = data
      @guardian = guardian
    end

    def as_json
      return {} if !@data.is_a?(Hash)

      @data
        .slice(*FIELDS)
        .to_h do |field, change|
          change = change.transform_values { |id| category_json(id) } if field == "category"
          [field, change]
        end
    end

    private

    def category_json(id)
      category = Category.find_by(id:)
      return if category.nil? || !@guardian.can_see_category?(category)
      { "id" => category.id, "name" => category.name }
    end
  end
end
