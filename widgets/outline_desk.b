// The other place the platform calls into Beans.
package widgets

import cortado.host

/// Which outline is which, and the tree behind it.
///
/// The same arrangement `TableBook` has and for the same reason: a callback
/// closure may not capture a field — Beans refuses `move self.x` into one —
/// but may capture a local holding a class reference.
class OutlineBook {
    priv handles: List<u64> = []
    priv sources: List<OutlineNodes> = []
    priv icon_handles: List<u64> = []
    priv icon_policies: List<fn(int) -> SystemIcon> = []

    pub fn init() {}

    pub fn put(handle: u64, nodes: OutlineNodes) {
        var index: int = 0
        for index < self.handles.len() {
            if self.handles[index] == handle {
                self.sources[index] = nodes
                return
            }
            index = index + 1
        }
        self.handles.push(handle)
        self.sources.push(nodes)
    }

    pub fn forget(handle: u64) {
        self.clear_icon_when(handle)
        var index: int = 0
        for index < self.handles.len() {
            if self.handles[index] == handle {
                self.handles.remove(index)
                self.sources.remove(index)
                return
            }
            index = index + 1
        }
    }

    pub fn set_icon_when(handle: u64, policy: fn(int) -> SystemIcon) {
        var index: int = 0
        for index < self.icon_handles.len() {
            if self.icon_handles[index] == handle {
                self.icon_policies[index] = policy
                return
            }
            index = index + 1
        }
        self.icon_handles.push(handle)
        self.icon_policies.push(policy)
    }

    pub fn clear_icon_when(handle: u64) {
        var index: int = 0
        for index < self.icon_handles.len() {
            if self.icon_handles[index] == handle {
                self.icon_handles.remove(index)
                self.icon_policies.remove(index)
                return
            }
            index = index + 1
        }
    }

    pub fn icon_of(handle: u64, node: int) -> SystemIcon {
        var index: int = 0
        for index < self.icon_handles.len() {
            if self.icon_handles[index] == handle {
                return self.icon_policies[index](node)
            }
            index = index + 1
        }
        return SystemIcon.none
    }

    pub fn find(handle: u64) -> Option<OutlineNodes> {
        var index: int = 0
        for index < self.handles.len() {
            if self.handles[index] == handle { return some(self.sources[index]) }
            index = index + 1
        }
        return none
    }

    /// The three structural questions, behind the one selector the ABI uses.
    ///
    /// An outline nobody registered a source for answers 0 to all three, which
    /// reads as an empty tree — the right answer while the platform is
    /// drawing, where there is nothing it could do with a refusal.
    pub fn shape(handle: u64, what: i32, node: i64, index: i32) -> i64 {
        var nodes: OutlineNodes = new EmptyNodes()
        match self.find(handle) {
            some(found) => { nodes = found }
            none => { return 0 }
        }
        if (what as int) == host.OUTLINE_CHILDREN { return nodes.child_count(node as int) as i64 }
        if (what as int) == host.OUTLINE_CHILD {
            return nodes.child_at(node as int, index as int) as i64
        }
        if (what as int) == host.OUTLINE_EXPANDS {
            if nodes.expandable(node as int) { return 1 }
            return 0
        }
        if (what as int) == host.OUTLINE_ICON {
            return self.icon_of(handle, node as int).code() as i64
        }
        return 0
    }

    /// The text, answered the way `ctd_get_text` answers: write at most `cap`
    /// bytes, return the number the cell needs.
    pub fn fill(handle: u64, node: i64, column: i32,
                out: RawPtr<i8>, cap: i32) -> i32 {
        var text: string = ""
        match self.find(handle) {
            some(nodes) => { text = nodes.cell(node as int, column as int) }
            none => { return 0 }
        }
        let bytes: Bytes = Bytes.from(text)
        let needed: int = bytes.len()
        var index: int = 0
        for index < needed && index < (cap as int) {
            unsafe { out.offset(index).write(bytes.get(index) as i8) }
            index = index + 1
        }
        return needed as i32
    }
}

/// A tree with nothing in it, so `shape` has something to name when no source
/// is registered. Never reached — `find` returns before it is used — and here
/// because a `var` of an interface type needs a value.
class EmptyNodes implements OutlineNodes {
    pub fn init() {}
    pub fn child_count(node: int) -> int { return 0 }
    pub fn child_at(node: int, index: int) -> int { return 0 }
    pub fn expandable(node: int) -> bool { return false }
    pub fn cell(node: int, column: int) -> string { return "" }
}

/// The process's one outline data source.
///
/// Two callbacks rather than one, because structure and text are different
/// questions with different answers — and because a single function would need
/// seven parameters, one more than a C callback here may have.
pub singleton class OutlineDesk {
    priv book: OutlineBook = new OutlineBook()
    priv shape: LocalStoredCallback<fn(RawPtr<u8>, u64, i32, i64, i32) -> i64>
    priv text: LocalStoredCallback<fn(RawPtr<u8>, u64, i64, i32, RawPtr<i8>, i32) -> i32>

    pub fn init() {
        let book: OutlineBook = new OutlineBook()
        self.book = book
        self.shape = LocalStoredCallback.create(0,
            fn(outline: u64, what: i32, node: i64, index: i32) -> i64 {
                return book.shape(outline, what, node, index)
            })
        self.text = LocalStoredCallback.create(0,
            fn(outline: u64, node: i64, column: i32,
               out: RawPtr<i8>, cap: i32) -> i32 {
                return book.fill(outline, node, column, out, cap)
            })
        unsafe {
            host.ctd_set_outline_source(self.shape.function(), self.shape.context(),
                                        self.text.function(), self.text.context())
        }
    }

    pub fn put(handle: u64, nodes: OutlineNodes) { self.book.put(handle, nodes) }
    pub fn forget(handle: u64) { self.book.forget(handle) }

    pub fn set_icon_when(handle: u64, policy: fn(int) -> SystemIcon) {
        self.book.set_icon_when(handle, policy)
    }

    pub fn clear_icon_when(handle: u64) { self.book.clear_icon_when(handle) }

    pub fn nodes_of(handle: u64) -> Option<OutlineNodes> {
        return self.book.find(handle)
    }
}
