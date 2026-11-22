# Carbn

**Carbn** is short for **carabiner**: it connects independent state and rendering systems without owning either one. 🔗

Reactive state, dependency-driven invalidation, and ViewComponent rendering boundaries for Ruby.

Carbn is independent of DSL editing, Prism, Rails applications and browsers. The optional `Carbn::ViewComponentRenderer` invokes real `ViewComponent::Base#render_in` and does not implement a replacement component language.

```ruby
require "carbn"

graph = Carbn::Graph.define do
  state :clicks, initial: 0
  derive(:label, from: [:clicks]) { |clicks| "Clicks: #{clicks}" }
  region :counter, depends_on: [:label]
end
store = Carbn::Store.new(graph)
store.subscribe { |regions, revision| puts "#{revision}: #{regions.inspect}" }
store.transaction do
  store.set(:clicks, 1)
  store.set(:clicks, 2)
end
```

Transactions publish once at the outermost boundary. Derived values follow dependency order. Unchanged signals do not invalidate regions. Failed derivations roll back attempted updates.

`Carbn::Presenter` maps region identifiers to application-owned component factories and uses a supplied renderer. `Carbn::ViewComponentRenderer` is the optional real ViewComponent adapter.

Run `ruby -Ilib test/core_test.rb` and `ruby examples/counter.rb`.

## Browser Git and workspace transactions

Carbn also owns optional, framework-neutral browser workspace infrastructure:

- `browser/git-capability.js` handles byte-safe isomorphic-git checkpoints.
- `browser/workspace-history.js` publishes incremental generated repositories, exports Git objects, and restores revisions with dirty-tree checks and rollback.
- Consumers supply filesystem, Git implementation, author, workspace roots, commit phases, and semantic validation. Nothing requires a particular DSL, browser UI, or Ruby runtime.

Run `node --test test/workspace-history.test.mjs` to verify Git history, atomic publication, and rollback. Browser event transport and cursor/IME-aware DOM patching remain outside the core.
