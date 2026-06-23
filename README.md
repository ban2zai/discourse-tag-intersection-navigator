# discourse-tag-intersection-navigator

A Discourse plugin that keeps native discovery/category filters working with multi-tag `match_all_tags` query params.

### Features

* Uses native Discourse routes such as `/latest`, `/top`, `/bookmarks`, and category discovery routes.
* Preserves `tags`, `match_all_tags`, category, and ordering query params across filter/category navigation.
* Filters incoming topic counts to the active native tag/category scope.
* Redirects old `/tags/intersection/...` links to native URLs.

### Settings

* Enable the plugin.
* Configure the legacy placeholder string used only when redirecting old intersection URLs.
