import { apiInitializer } from "discourse/lib/api";
import TopicChangeNotice from "../components/topic-change-notice";

const ACTION_CODE = "topic_change_notice";

export default apiInitializer((api) => {
  api.addTrackedPostProperties("topic_change_notice");
  api.addPostSmallActionIcon(ACTION_CODE, "pen-to-square");
  api.addPostSmallActionClassesCallback((post) =>
    post.action_code === ACTION_CODE ? ["topic-change-notice-post"] : []
  );
  api.registerValueTransformer(
    "post-small-action-custom-component",
    ({ value, context: { code } }) =>
      code === ACTION_CODE ? TopicChangeNotice : value
  );
});
