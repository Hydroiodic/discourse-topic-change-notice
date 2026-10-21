import Component from "@glimmer/component";
import { trustHTML } from "@ember/template";
import { autoUpdatingRelativeAge } from "discourse/lib/formatter";
import renderTag from "discourse/lib/render-tag";
import { escapeExpression } from "discourse/lib/utilities";
import Category from "discourse/models/category";
import { categoryBadgeHTML } from "discourse/ui-kit/helpers/d-category-link";
import { i18n } from "discourse-i18n";

function categoryHTML(category) {
  if (!category) {
    return escapeExpression(i18n("topic_change_notice.hidden_category"));
  }

  const model = Category.findById(category.id);
  return model
    ? categoryBadgeHTML(model, { link: true })
    : escapeExpression(category.name);
}

function tagsHTML(tags) {
  return tags.map((tag) => renderTag(tag)).join(" ");
}

function tagsLine({ from, to }) {
  const added = to.filter((tag) => !from.includes(tag));
  const removed = from.filter((tag) => !to.includes(tag));

  if (added.length && removed.length) {
    return {
      key: "tags_changed",
      params: { added: tagsHTML(added), removed: tagsHTML(removed) },
    };
  } else if (added.length) {
    return { key: "tags_added", params: { added: tagsHTML(added) } };
  } else if (removed.length) {
    return { key: "tags_removed", params: { removed: tagsHTML(removed) } };
  }
}

export default class TopicChangeNotice extends Component {
  get when() {
    return autoUpdatingRelativeAge(this.args.createdAt, {
      format: "medium-with-ago-and-on",
    });
  }

  get changes() {
    const { title, category, tags } = this.args.post.topic_change_notice || {};
    const changes = [];

    if (title) {
      changes.push({
        key: "title",
        params: { from: escapeExpression(title.from) },
        newTitle: title.to,
      });
    }

    if (category) {
      changes.push({
        key: "category",
        params: {
          from: categoryHTML(category.from),
          to: categoryHTML(category.to),
        },
      });
    }

    const tagLine = tags && tagsLine(tags);
    if (tagLine) {
      changes.push(tagLine);
    }

    return changes;
  }

  get whenOnOwnLine() {
    return this.changes.length > 1;
  }

  get whenHTML() {
    return trustHTML(this.when);
  }

  get lines() {
    const variant = this.whenOnOwnLine ? "plain" : "with_when";
    return this.changes.map((change) => ({
      ...change,
      html: trustHTML(
        i18n(`topic_change_notice.${change.key}.${variant}`, {
          ...change.params,
          when: this.when,
        })
      ),
    }));
  }

  get fallback() {
    return trustHTML(
      i18n("action_codes.topic_change_notice", { when: this.when })
    );
  }

  <template>
    <div class="topic-change-notice">
      {{#if this.whenOnOwnLine}}
        <p
          class="topic-change-notice__line topic-change-notice__when"
        >{{this.whenHTML}}</p>
      {{/if}}
      {{#each this.lines as |line|}}
        <p class="topic-change-notice__line">{{line.html}}</p>
        {{#if line.newTitle}}
          <p class="topic-change-notice__new-title">{{line.newTitle}}</p>
        {{/if}}
      {{else}}
        <p class="topic-change-notice__line">{{this.fallback}}</p>
      {{/each}}
    </div>
  </template>
}
