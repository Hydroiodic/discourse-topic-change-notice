## Discourse Topic Change Notice

话题的标题、分类或标签被修改后，在帖子流里插入 small action 进行公示，允许所有能看到话题的用户浏览。

### 合并与撤销

在 core 的 `editing_grace_period` 内，如果同一个人再次修改，而且这期间没有人回复，也没有别人的公示，新的改动会合并进上一条同类公示，每个字段保留最初的旧值。合并后如果所有字段都改回了原值，这条 small action 会被软删。

### 隐私

- 分类只保存 id，渲染时按查看者的权限判断。
- 隐藏标签不会出现在公示里。只修改了隐藏标签时，不发公示。
- 旧标题对所有人可见。

### 站点设置

| 设置 | 默认值 | 作用 |
|---|---|---|
| `topic_change_notice_enabled` | false | 总开关 |
| `topic_change_notice_title_enabled` | true | 公示标题变更 |
| `topic_change_notice_category_enabled` | true | 公示分类变更 |
| `topic_change_notice_tags_enabled` | true | 公示标签变更 |
| `topic_change_notice_skip_bots` | true | 系统用户和机器人的修改不公示 |
| `topic_change_notice_excluded_groups` | 空 | 这些群组成员的修改不公示 |
| `topic_change_notice_suppress_core_whispers` | true | 本插件已公示的字段不再发送 core 的密语 |

### 其他行为

- 只有 staff 能编辑或删除公示，以免修改者自己删掉记录。
- staff 和 TL4 用批量操作修改分类或标签时不发公示，其他用户通过批量操作接口修改自己能编辑的话题，照常公示。

## 安装

参考 https://meta.discourse.org/t/install-a-plugin/19157
