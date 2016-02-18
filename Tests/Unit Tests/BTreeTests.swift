//
//  BTreeTests.swift
//  TreeCollections
//
//  Created by Károly Lőrentey on 2016-01-13.
//  Copyright © 2016 Károly Lőrentey. All rights reserved.
//

import Foundation
import XCTest
@testable import TreeCollections

extension BTreeNode {
    func assertValid(file file: FileString = __FILE__, line: UInt = __LINE__) {
        func testNode(level level: Int, node: BTreeNode<Key, Payload>, minKey: Key?, maxKey: Key?) -> (count: Int, defects: [String]) {
            var defects: [String] = []

            // Check item order
            var prev = minKey
            for key in node.keys {
                if let p = prev where p > key {
                    defects.append("Invalid item order: \(p) > \(key)")
                }
                prev = key
            }
            if let maxKey = maxKey, prev = prev where prev > maxKey {
                defects.append("Invalid item order: \(prev) > \(maxKey)")
            }

            // Check leaf node
            if node.isLeaf {
                if node.keys.count > node.order - 1 {
                    defects.append("Oversize leaf node: \(node.keys.count) > \(node.order - 1)")
                }
                if level > 0 && node.keys.count < (node.order - 1) / 2 {
                    defects.append("Undersize leaf node: \(node.keys.count) < \((node.order - 1) / 2)")
                }
                if node.payloads.count != node.keys.count {
                    defects.append("Mismatching item counts in leaf node (keys.count: \(node.keys.count), payloads.count: \(node.payloads.count)")
                }
                if !node.children.isEmpty {
                    defects.append("Leaf node should have no children, this one has \(node.children.count)")
                }
                if node.depth != 0 {
                    defects.append("Lead node should have depth 0")
                }
                return (node.keys.count, defects)
            }

            // Check child count
            if node.children.count > node.order {
                defects.append("Oversize internal node: \(node.children.count) > \(node.order)")
            }
            if level > 0 && node.children.count < (node.order + 1) / 2 {
                defects.append("Undersize internal node: \(node.children.count) < \((node.order + 1) / 2)")
            }
            if level == 0 && node.children.count < 2 {
                defects.append("Undersize root node: \(node.children.count) < 2")
            }
            // Check item count
            if node.keys.count != node.children.count - 1 {
                defects.append("Mismatching item counts in internal node (keys.count: \(node.keys.count), children.count: \(node.children.count)")
            }
            if node.payloads.count != node.keys.count {
                defects.append("Mismatching item counts in internal node (keys.count: \(node.keys.count), payloads.count: \(node.payloads.count)")
            }

            // Recursion
            var count = node.keys.count
            for slot in 0 ..< node.children.count {
                let child = node.children[slot]
                let (c, d) = testNode(
                    level: level + 1,
                    node: child,
                    minKey: (slot > 0 ? node.keys[slot - 1] : minKey),
                    maxKey: (slot < node.keys.count - 1 ? node.keys[slot + 1] : maxKey))
                if node.depth != child.depth + 1 {
                    defects.append("Invalid depth: \(node.depth) in parent vs \(child.depth) in child")
                }
                count += c
                defects.appendContentsOf(d)
            }
            if node.count != count {
                defects.append("Mismatching internal node count: \(node.count) vs \(count)")
            }
            return (count, defects)
        }

        let (_, defects) = testNode(level: 0, node: self, minKey: nil, maxKey: nil)
        for d in defects {
            XCTFail(d, file: file, line: line)
        }
    }

    func insert(payload: Payload, at key: Key) {
        var splinter: BTreeSplinter<Key, Payload>? = nil
        self.editAtKey(key) { node, slot, match in
            precondition(!match)
            if node.isLeaf {
                node.keys.insert(key, atIndex: slot)
                node.payloads.insert(payload, atIndex: slot)
                node.count += 1
                if node.isTooLarge {
                    splinter = node.split()
                }
            }
            else {
                node.count += 1
                if let s = splinter {
                    node.insert(s, inSlot: slot)
                    splinter = (node.isTooLarge ? node.split() : nil)
                }
            }
        }
        if let s = splinter {
            let left = clone()
            let right = s.node
            keys = [s.separator.0]
            payloads = [s.separator.1]
            children = [left, right]
            count = left.count + right.count + 1
            _depth = _depth + 1
        }
    }

    func remove(key: Key, root: Bool = true) -> Payload? {
        var found: Bool = false
        var result: Payload? = nil
        editAtKey(key) { node, slot, match in
            if node.isLeaf {
                assert(!found)
                if !match { return }
                found = true
                node.keys.removeAtIndex(slot)
                result = node.payloads.removeAtIndex(slot)
                node.count -= 1
                return
            }
            if match {
                assert(!found)
                // For internal nodes, we move the previous item in place of the removed one,
                // and remove its original slot instead. (The previous item is always in a leaf node.)
                result = node.payloads[slot]
                node.makeChildUnique(slot)
                let previousKey = node.children[slot].maxKey()!
                let previousPayload = node.children[slot].remove(previousKey, root: false)!
                node.keys[slot] = previousKey
                node.payloads[slot] = previousPayload
                found = true
            }
            if found {
                node.count -= 1
                if node.children[slot].isTooSmall {
                    node.fixDeficiency(slot)
                }
            }
        }
        if root && keys.isEmpty && children.count == 1 {
            let node = children[0]
            keys = node.keys
            payloads = node.payloads
            children = node.children
            _depth -= 1
        }
        return result
    }
}


func maximalTreeOfDepth(depth: Int, order: Int, offset: Int = 0) -> BTreeNode<Int, String> {
    func maximalTreeOfDepth(depth: Int, inout key: Int) -> BTreeNode<Int, String> {
        let tree = BTreeNode<Int, String>(order: order)
        tree._depth = numericCast(depth)
        if depth == 0 {
            for _ in 0 ..< tree.order - 1 {
                tree.insert(String(key), at: key)
                key += 1
            }
        }
        else {
            for i in 0 ..< tree.order {
                let child = maximalTreeOfDepth(depth - 1, key: &key)
                tree.children.append(child)
                tree.count += child.count
                if i < tree.order - 1 {
                    tree.keys.append(key)
                    tree.payloads.append(String(key))
                    tree.count += 1
                    key += 1
                }
            }
        }
        return tree
    }

    var key = offset
    return maximalTreeOfDepth(depth, key: &key)
}

class BTreeTests: XCTestCase {
    typealias Node = BTreeNode<Int, String>
    let order = 7

    func testEmptyTree() {
        let tree = Node(order: order)
        tree.assertValid()
        XCTAssertTrue(tree.isEmpty)
        XCTAssertEqual(tree.count, 0)
        XCTAssertElementsEqual(tree, [])

        XCTAssertEqual(tree.startIndex, tree.endIndex)

        XCTAssertNil(tree.payloadOf(1))
    }

    func testInsertingASingleKey() {
        let tree = Node(order: order)
        tree.insert("One", at: 1)
        tree.assertValid()
        XCTAssertFalse(tree.isEmpty)
        XCTAssertEqual(tree.count, 1)
        XCTAssertElementsEqual(tree, [(1, "One")])

        XCTAssertEqual(tree.payloadOf(1), "One")
        XCTAssertNil(tree.payloadOf(2))

        XCTAssertNotEqual(tree.startIndex, tree.endIndex)
        XCTAssertEqual(tree[tree.startIndex].0, 1)
        XCTAssertEqual(tree[tree.startIndex].1, "One")
    }

    func testRemovingTheSingleKey() {
        let tree = Node(order: order)
        tree.insert("One", at: 1)
        XCTAssertEqual(tree.remove(1), "One")
        tree.assertValid()

        XCTAssertTrue(tree.isEmpty)
        XCTAssertEqual(tree.count, 0)
        XCTAssertElementsEqual(tree, [])

        XCTAssertEqual(tree.startIndex, tree.endIndex)
    }

    func testInsertingAndRemovingTwoKeys() {
        let tree = Node(order: order)
        tree.insert("One", at: 1)
        tree.insert("Two", at: 2)
        tree.assertValid()

        XCTAssertFalse(tree.isEmpty)
        XCTAssertEqual(tree.count, 2)
        XCTAssertElementsEqual(tree, [(1, "One"), (2, "Two")])

        XCTAssertEqual(tree.payloadOf(1), "One")
        XCTAssertEqual(tree.payloadOf(2), "Two")
        XCTAssertNil(tree.payloadOf(3))

        XCTAssertEqual(tree.remove(1), "One")
        tree.assertValid()

        XCTAssertFalse(tree.isEmpty)
        XCTAssertEqual(tree.count, 1)
        XCTAssertElementsEqual(tree, [(2, "Two")])

        XCTAssertEqual(tree.remove(2), "Two")
        tree.assertValid()

        XCTAssertTrue(tree.isEmpty)
        XCTAssertEqual(tree.count, 0)
        XCTAssertElementsEqual(tree, [])
    }

    func testSplittingRoot() {
        let tree = Node(order: order)
        var reference = Array<(Int, String)>()
        for i in 0..<tree.order {
            tree.insert("\(i)", at: i)
            tree.assertValid()
            reference.append((i, "\(i)"))
        }

        XCTAssertFalse(tree.isEmpty)
        XCTAssertEqual(tree.count, tree.order)
        XCTAssertElementsEqual(tree, reference)

        XCTAssertEqual(tree.keys.count, 1)
        XCTAssertEqual(tree.children.count, 2)
        XCTAssertEqual(tree.depth, 1)
    }

    func testRemovingNonexitentKeys() {
        let tree = Node(order: order)
        for i in 0..<tree.order {
            tree.insert("\(2 * i)", at: 2 * i)
            tree.assertValid()
        }
        for i in 0..<tree.order {
            XCTAssertNil(tree.remove(2 * i + 1))
        }
    }

    func testCollapsingRoot() {
        let tree = Node(order: order)
        var reference = Array<(Int, String)>()
        for i in 0..<tree.order {
            tree.insert("\(i)", at: i)
            tree.assertValid()
            reference.append((i, "\(i)"))
        }
        tree.remove(0)
        tree.assertValid()
        reference.removeAtIndex(0)

        XCTAssertEqual(tree.count, tree.order - 1)
        XCTAssertElementsEqual(tree, reference)

        XCTAssertEqual(tree.keys.count, tree.count)
        XCTAssertEqual(tree.children.count, 0)
        XCTAssertEqual(tree.depth, 0)
    }

    func testSplittingInternalNode() {
        let tree = Node(order: order)
        var reference = Array<(Int, String)>()
        let c = (3 * tree.order + 1) / 2
        for i in 0 ..< c {
            tree.insert("\(i)", at: i)
            tree.assertValid()
            reference.append((i, "\(i)"))
        }

        XCTAssertEqual(tree.count, c)
        XCTAssertElementsEqual(tree, reference)

        XCTAssertEqual(tree.keys.count, 2)
        XCTAssertEqual(tree.children.count, 3)
        XCTAssertEqual(tree.depth, 1)
    }

    func testCreatingMinimalTreeWithThreeLevels() {
        let tree = Node(order: order)
        var reference = Array<(Int, String)>()
        let c = (tree.order * tree.order - 1) / 2 + tree.order
        for i in 0 ..< c {
            tree.insert("\(i)", at: i)
            tree.assertValid()
            reference.append((i, "\(i)"))
        }

        XCTAssertEqual(tree.count, c)
        XCTAssertElementsEqual(tree, reference)

        XCTAssertEqual(tree.depth, 2)

        XCTAssertEqual(tree.payloadOf(c / 2), "\(c / 2)")
        XCTAssertEqual(tree.payloadOf(c / 2 + 1), "\(c / 2 + 1)")
    }

    func testRemovingKeysFromMinimalTreeWithThreeLevels() {
        let tree = Node(order: order)
        let c = (tree.order * tree.order - 1) / 2 + tree.order
        for i in 0 ..< c {
            tree.insert("\(i)", at: i)
            tree.assertValid()
        }

        for i in 0 ..< c {
            XCTAssertEqual(tree.remove(i), "\(i)")
            tree.assertValid()
        }
        XCTAssertElementsEqual(tree, [])
    }

    func testRemovingRootFromMinimalTreeWithThreeLevels() {
        let tree = Node(order: order)
        let c = (tree.order * tree.order - 1) / 2 + tree.order
        for i in 0 ..< c {
            tree.insert("\(i)", at: i)
            tree.assertValid()
        }
        XCTAssertEqual(tree.remove(c / 2), "\(c/2)")
        tree.assertValid()
        XCTAssertEqual(tree.depth, 1)
    }

    func testMaximalTreeOfDepth() {
        for depth in 0..<3 {
            let tree = maximalTreeOfDepth(depth, order: order)
            tree.assertValid()
            XCTAssertEqual(tree.depth, depth)
            XCTAssertEqual(tree.count, (0...depth).reduce(1, combine: { p, _ in p * tree.order }) - 1)
        }
    }

    func testRemovingFromBeginningOfMaximalTreeWithThreeLevels() {
        // This test exercises left rotations.
        let tree = maximalTreeOfDepth(2, order: order)
        for key in 0..<tree.count {
            XCTAssertEqual(tree.remove(key), String(key))
            tree.assertValid()
        }
        XCTAssertTrue(tree.isEmpty)
    }
    func testRemovingFromEndOfMaximalTreeWithThreeLevels() {
        // This test exercises right rotations.
        let tree = maximalTreeOfDepth(2, order: order)
        for key in (0..<tree.count).reverse() {
            XCTAssertEqual(tree.remove(key), String(key))
            tree.assertValid()
        }
        XCTAssertTrue(tree.isEmpty)
    }

    func testIterationUsingIndexingForward() {
        let tree = maximalTreeOfDepth(3, order: 3)
        var index = tree.startIndex
        var i = 0
        while index != tree.endIndex {
            XCTAssertEqual(tree[index].0, i)
            index = index.successor()
            i += 1
        }
        XCTAssertEqual(i, tree.count)
    }

    func testIterationUsingIndexingBackward() {
        let tree = maximalTreeOfDepth(3, order: 3)
        var index = tree.endIndex
        var i = tree.count
        while index != tree.startIndex {
            index = index.predecessor()
            i -= 1
            XCTAssertEqual(tree[index].0, i)
        }
        XCTAssertEqual(i, 0)
    }

    func testForEach() {
        let tree = maximalTreeOfDepth(2, order: order)
        var values: Array<Int> = []
        tree.forEach { values.append($0.0) }
        XCTAssertElementsEqual(values, 0..<tree.count)
    }

    func testInterruptibleForEach() {
        let tree = maximalTreeOfDepth(1, order: 5)
        for i in 0...tree.count {
            var j = 0
            tree.forEach { pair -> Bool in
                XCTAssertEqual(pair.0, j)
                XCTAssertLessThanOrEqual(j, i)
                if j == i { return false }
                j += 1
                return true
            }
        }
    }

    func testSlotOfParentChild() {
        let root = maximalTreeOfDepth(1, order: 5)
        XCTAssertEqual(root.slotOf(root.children[0]), 0)
        XCTAssertEqual(root.slotOf(root.children[1]), 1)
        XCTAssertNil(root.children[1].slotOf(root))
    }

    func testCursorInitWithEmptyTree() {
        func checkEmpty(cursor: BTreeCursor<Int, String>) {
            XCTAssertTrue(cursor.isValid)
            XCTAssertTrue(cursor.isAtStart)
            XCTAssertTrue(cursor.isAtEnd)
            XCTAssertEqual(cursor.count, 0)
            let tree = cursor.finish()
            XCTAssertElementsEqual(tree, [])
        }

        checkEmpty(BTreeCursor())
        checkEmpty(BTreeCursor(startOf: Node(order: 3)))
        checkEmpty(BTreeCursor(endOf: Node(order: 3)))
        checkEmpty(BTreeCursor(root: Node(order: 3), position: 0))
        checkEmpty(BTreeCursor(root: Node(order: 3), key: 42))

    }

    func testCursorInitAtStart() {
        let tree = maximalTreeOfDepth(2, order: 5)
        let cursor = BTreeCursor(startOf: tree)
        XCTAssertTrue(cursor.isAtStart)
        XCTAssertFalse(cursor.isAtEnd)
        XCTAssertEqual(cursor.position, 0)
        XCTAssertEqual(cursor.key, 0)
        XCTAssertEqual(cursor.payload, "0")
    }

    func testCursorInitAtEnd() {
        let tree = maximalTreeOfDepth(2, order: 5)
        let cursor = BTreeCursor(endOf: tree)
        XCTAssertFalse(cursor.isAtStart)
        XCTAssertTrue(cursor.isAtEnd)
        XCTAssertEqual(cursor.position, tree.count)
    }

    func testCursorInitAtPosition() {
        let tree = maximalTreeOfDepth(2, order: 5)
        let count = tree.count
        for i in 0..<count {
            let cursor = BTreeCursor(root: tree, position: i)
            XCTAssertEqual(cursor.key, i)
            XCTAssertEqual(cursor.payload, String(i))
        }
        XCTAssertTrue(BTreeCursor(root: tree, position: count).isAtEnd)
    }

    func testCursorInitAtKey() {
        let tree = Node(order: 3)
        (0...30).map { 2 * $0 }.forEach { tree.insert(String($0), at: $0) }

        for i in 0...60 {
            let cursor = BTreeCursor(root: tree, key: i)
            let expectedKey = (i + 1) & ~1
            XCTAssertEqual(cursor.key, expectedKey)
            XCTAssertEqual(cursor.payload, String(expectedKey))
        }
        XCTAssertTrue(BTreeCursor(root: tree, key: 61).isAtEnd)
    }

    func testCursorMoveForward() {
        let cursor = BTreeCursor(startOf: maximalTreeOfDepth(2, order: 5))
        var i = 0
        while !cursor.isAtEnd {
            XCTAssertEqual(cursor.key, i)
            XCTAssertEqual(cursor.payload, String(i))
            cursor.moveForward()
            i += 1
        }
        let tree = cursor.finish()
        XCTAssertEqual(i, tree.count)
    }

    func testCursorMoveBackward() {
        let cursor = BTreeCursor(endOf: maximalTreeOfDepth(2, order: 5))
        var i = cursor.count
        while !cursor.isAtStart {
            cursor.moveBackward()
            i -= 1
            XCTAssertEqual(cursor.key, i)
            XCTAssertEqual(cursor.payload, String(i))
        }
        XCTAssertEqual(i, 0)
    }

    func testCursorMoveToPosition() {
        let cursor = BTreeCursor(startOf: maximalTreeOfDepth(2, order: 5))
        var i = 0
        var j = cursor.count - 1
        var toggle = false
        while i < j {
            if toggle {
                cursor.moveToPosition(i)
                XCTAssertEqual(cursor.position, i)
                XCTAssertEqual(cursor.key, i)
                i += 1
                toggle = false
            }
            else {
                cursor.moveToPosition(j)
                XCTAssertEqual(cursor.position, j)
                XCTAssertEqual(cursor.key, j)
                j -= 1
                toggle = true
            }
        }
        cursor.moveToPosition(cursor.count)
        XCTAssertTrue(cursor.isAtEnd)
        cursor.moveBackward()
        XCTAssertEqual(cursor.key, cursor.count - 1)
    }

    func testCursorUpdatingData() {
        let cursor = BTreeCursor(startOf: maximalTreeOfDepth(2, order: 5))
        while !cursor.isAtEnd {
            cursor.key = 2 * cursor.key
            cursor.payload = String(cursor.key)
            cursor.moveForward()
        }
        let tree = cursor.finish()
        tree.assertValid()
        var i = 0
        for (key, payload) in tree {
            XCTAssertEqual(key, 2 * i)
            XCTAssertEqual(payload, String(2 * i))
            i += 1
        }
    }

    func testCursorSetPayload() {
        let cursor = BTreeCursor(startOf: maximalTreeOfDepth(2, order: 5))
        var i = 0
        while !cursor.isAtEnd {
            XCTAssertEqual(cursor.setPayload("Hello"), String(i))
            cursor.moveForward()
            i += 1
        }
        let tree = cursor.finish()
        tree.assertValid()
        for (_, payload) in tree {
            XCTAssertEqual(payload, "Hello")
        }
    }

    func testCursorBuildingATreeUsingInsertBefore() {
        let cursor = BTreeCursor(startOf: Node(order: 5))
        XCTAssertTrue(cursor.isAtEnd)
        for i in 0..<30 {
            cursor.insertBefore(i, String(i))
            XCTAssertTrue(cursor.isAtEnd)
        }
        let tree = cursor.finish()
        tree.assertValid()
        XCTAssertElementsEqual(tree, (0..<30).map { ($0, String($0)) })
    }

    func testCursorBuildingATreeInTwoPassesUsingInsertBefore() {
        let cursor = BTreeCursor(startOf: Node(order: 5))
        XCTAssertTrue(cursor.isAtEnd)
        let c = 30
        for i in 0..<c {
            cursor.insertBefore(2 * i + 1, String(2 * i + 1))
            XCTAssertTrue(cursor.isAtEnd)
        }

        cursor.moveToStart()
        XCTAssertEqual(cursor.position, 0)
        for i in 0..<c {
            XCTAssertEqual(cursor.key, 2 * i + 1)
            XCTAssertEqual(cursor.position, 2 * i)
            XCTAssertEqual(cursor.count, c + i)
            cursor.insertBefore(2 * i, String(2 * i))
            XCTAssertEqual(cursor.key, 2 * i + 1)
            XCTAssertEqual(cursor.position, 2 * i + 1)
            XCTAssertEqual(cursor.count, c + i + 1)
            cursor.moveForward()
        }

        let tree = cursor.finish()
        tree.assertValid()
        XCTAssertElementsEqual(tree, (0 ..< 2 * c).map { ($0, String($0)) })
    }

    func testCursorBuildingATreeUsingInsertAfter() {
        let cursor = BTreeCursor<Int, String>(startOf: Node(order: 5))
        cursor.insertBefore(0, "0")
        cursor.moveToStart()
        let c = 30
        for i in 1 ..< c {
            cursor.insertAfter(i, String(i))
            XCTAssertEqual(cursor.position, i)
            XCTAssertEqual(cursor.key, i)
        }
        let tree = cursor.finish()
        tree.assertValid()
        XCTAssertElementsEqual(tree, (0..<30).map { ($0, String($0)) })
    }

    func testCursorBuildingATreeInTwoPassesUsingInsertAfter() {
        let cursor = BTreeCursor(startOf: Node(order: 5))
        XCTAssertTrue(cursor.isAtEnd)
        let c = 30
        for i in 0..<c {
            cursor.insertBefore(2 * i, String(2 * i))
        }

        cursor.moveToStart()
        XCTAssertEqual(cursor.position, 0)
        for i in 0..<c {
            XCTAssertEqual(cursor.key, 2 * i)
            XCTAssertEqual(cursor.position, 2 * i)
            XCTAssertEqual(cursor.count, c + i)
            cursor.insertAfter(2 * i + 1, String(2 * i + 1))
            XCTAssertEqual(cursor.key, 2 * i + 1)
            XCTAssertEqual(cursor.position, 2 * i + 1)
            XCTAssertEqual(cursor.count, c + i + 1)
            cursor.moveForward()
        }

        let tree = cursor.finish()
        tree.assertValid()
        XCTAssertElementsEqual(tree, (0 ..< 2 * c).map { ($0, String($0)) })
    }

    func testCursorBuildingATreeBackward() {
        let cursor = BTreeCursor(startOf: Node(order: 5))
        XCTAssertTrue(cursor.isAtEnd)
        let c = 30
        for i in (c - 1).stride(through: 0, by: -1) {
            cursor.insertBefore(i, String(i))
            XCTAssertEqual(cursor.count, c - i)
            XCTAssertEqual(cursor.position, 1)
            cursor.moveBackward()
            XCTAssertEqual(cursor.position, 0)
            XCTAssertEqual(cursor.key, i)
        }
    }

    func testRemoveAllElementsInOrder() {
        let cursor = BTreeCursor(startOf: maximalTreeOfDepth(2, order: 5))
        var i = 0
        while cursor.count > 0 {
            let (key, payload) = cursor.remove()
            XCTAssertEqual(key, i)
            XCTAssertEqual(payload, String(i))
            XCTAssertEqual(cursor.position, 0)
            i += 1
        }
    }

    func testRemoveEachElement() {
        let tree = maximalTreeOfDepth(2, order: 5)
        for i in 0..<tree.count {
            let cursor = BTreeCursor(root: tree, position: i)
            let removed = cursor.remove()
            XCTAssertEqual(removed.0, i)
            XCTAssertEqual(removed.1, String(i))
            let newTree = cursor.finish()
            newTree.assertValid()
            XCTAssertElementsEqual(newTree, (0..<tree.count).filter{$0 != i}.map{ ($0, String($0)) })
        }
    }

    func testJoin() {
        func createTree(keys: Range<Int> = 0..<0) -> Node {
            let t = Node(order: 5)
            for key in keys {
                t.insert(String(key), at: key)
            }
            return t
        }
        func checkTree(t: Node, _ keys: Range<Int>, file: FileString = __FILE__, line: UInt = __LINE__) {
            t.assertValid(file: file, line: line)
            XCTAssertElementsEqual(t, keys.map { ($0, String($0)) }, file: file, line: line)
        }

        checkTree(Node.join(left: createTree(), separator: (0, "0"), right: createTree()), 0...0)
        checkTree(Node.join(left: createTree(), separator: (0, "0"), right: createTree(1...1)), 0...1)
        checkTree(Node.join(left: createTree(0...0), separator: (1, "1"), right: createTree()), 0...1)
        checkTree(Node.join(left: createTree(0...0), separator: (1, "1"), right: createTree(2...2)), 0...2)

        checkTree(Node.join(left: createTree(0...98), separator: (99, "99"), right: createTree(100...100)), 0...100)
        checkTree(Node.join(left: createTree(0...0), separator: (1, "1"), right: createTree(2...100)), 0...100)
        checkTree(Node.join(left: createTree(0...99), separator: (100, "100"), right: createTree(101...200)), 0...200)

        do {
            let l = maximalTreeOfDepth(2, order: 3)
            let r = maximalTreeOfDepth(2, order: 3, offset: l.count + 1)
            let s = (l.count, String(l.count))
            let c = l.count + r.count + 1
            checkTree(Node.join(left: l, separator: s, right: r), 0..<c)
        }

        do {
            let l = maximalTreeOfDepth(1, order: 3)
            let r = maximalTreeOfDepth(2, order: 3, offset: l.count + 1)
            let s = (l.count, String(l.count))
            let c = l.count + r.count + 1
            checkTree(Node.join(left: l, separator: s, right: r), 0..<c)
        }

        do {
            let l = maximalTreeOfDepth(2, order: 3)
            let r = maximalTreeOfDepth(1, order: 3, offset: l.count + 1)
            let s = (l.count, String(l.count))
            let c = l.count + r.count + 1
            checkTree(Node.join(left: l, separator: s, right: r), 0..<c)
        }
    }

    func testCursorRemoveRangeFromMaximalTree() {
        let tree = maximalTreeOfDepth(3, order: 3)
        let count = tree.count
        for i in 0 ..< count {
            for n in 0 ... count - i {
                let cursor = BTreeCursor(root: tree, position: i)
                cursor.remove(n)
                let t = cursor.finish()
                t.assertValid()
                let keys = Array(0..<i) + Array(i + n ..< count)
                XCTAssertElementsEqual(t, keys.map { ($0, String($0)) })
            }
        }
        tree.assertValid()
        XCTAssertElementsEqual(tree, (0..<count).map { ($0, String($0)) })
    }
}