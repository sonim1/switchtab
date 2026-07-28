public enum SwitcherWindowOrderPolicy {
    /// Cmd+` semantics: slot 0 must be the window you are on right now, so the
    /// default highlight (slot 1) is the window you toggle back to.
    ///
    /// Recency history alone cannot guarantee that. It only records switches
    /// made through SwitchTab, so any focus change from outside — a click,
    /// Cmd+Tab, a newly opened window — leaves the history leading with a
    /// window that is no longer frontmost, and the highlight lands on the
    /// wrong entry (sometimes on the window already in front).
    public static func pinningFocusedWindowFirst<Item>(
        _ items: [Item],
        isFocused: (Item) -> Bool
    ) -> [Item] {
        guard items.count > 1 else {
            return items
        }

        guard let focusedIndex = items.indices.first(where: { isFocused(items[$0]) }),
              focusedIndex != items.startIndex else {
            return items
        }

        var orderedItems = items
        let focusedItem = orderedItems.remove(at: focusedIndex)
        orderedItems.insert(focusedItem, at: 0)
        return orderedItems
    }
}
