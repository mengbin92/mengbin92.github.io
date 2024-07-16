---
layout: post
title: 链表分组逆序
tags: [go, algorithm]
mermaid: false
math: false
---  

链表分组逆序是一个常见的操作，用于将链表按照一定规则分组后，逆序每个分组。这种操作常常用于解决链表中的某些问题。下面介绍几种常见的用于链表分组逆序的算法，并分析它们的优劣势：

## 迭代法

- **算法描述**：迭代法是一种直观的方法。它维护一个虚拟头节点，然后按照指定的组数 k，逐一遍历链表，将每组的节点逆序，然后将前一组的尾部节点与当前组的头部节点相连接。
- **优点**：相对容易理解和实现，不需要额外的空间。
- **缺点**：需要多次遍历链表，时间复杂度较高，为 O(n)，其中 n 为链表长度。

算法实现：  

```go
package main

type ListNode struct {
    Val  int
    Next *ListNode
}

func reverseKGroup(head *ListNode, k int) *ListNode {
    if head == nil || k == 1 {
        return head
    }

    dummy := &ListNode{Next: head}
    prevGroupTail := dummy

    for {
        groupStart := prevGroupTail.Next
        groupEnd := prevGroupTail.Next

        // 遍历判断组内是否有足够的节点
        for i := 0; i < k && groupEnd != nil {
            groupEnd = groupEnd.Next
        }

        if groupEnd == nil {
            break // 剩余节点不足一组
        }

        nextGroupStart := groupEnd.Next
        groupEnd.Next = nil
        prevGroupTail.Next = reverseList(groupStart)
        groupStart.Next = nextGroupStart
        prevGroupTail = groupStart
    }

    return dummy.Next
}

func reverseList(head *ListNode) *ListNode {
    var prev *ListNode
    current := head

    for current != nil {
        next := current.Next
        current.Next = prev
        prev = current
        current = next
    }

    return prev
}
```

## 递归法

- **算法描述**：递归法通过递归地处理每一组，将其逆序，并连接到前一组的尾部。在递归的过程中，需要记录每组的头部和尾部。
- **优点**：相对简洁的递归实现，不需要额外的空间。
- **缺点**：与迭代法一样，需要多次遍历链表，时间复杂度也为 O(n)。

算法实现：  

```go
package main

type ListNode struct {
    Val  int
    Next *ListNode
}

func reverseKGroup(head *ListNode, k int) *ListNode {
    if head == nil || k == 1 {
        return head
    }

    count := 0
    current := head

    // 计算链表长度
    for current != nil {
        count++
        current = current.Next
    }

    // 若链表长度小于 k，则无需逆序
    if count < k {
        return head
    }

    current = head
    var prev, next *ListNode

    // 逆序前 k 个节点
    for i := 0; i < k; i++ {
        next = current.Next
        current.Next = prev
        prev = current
        current = next
    }

    // 递归处理剩余部分
    head.Next = reverseKGroup(current, k)

    return prev
}
```

## 栈法

- **算法描述**：栈法使用一个栈数据结构，依次将每组的节点压入栈中，然后再依次弹出栈的节点，实现逆序。同时，根据组数 k，维护组内的头尾节点，将它们与前一组的尾部节点和后一组的头部节点相连接。
- **优点**：相对迭代法和递归法，栈法只需一次遍历链表，时间复杂度为 O(n)，并且实现相对简单。
- **缺点**：需要额外的空间来存储栈，可能会引入一些额外的空间复杂度。

算法实现：  

```go
package main

type ListNode struct {
    Val  int
    Next *ListNode
}

func reverseKGroup(head *ListNode, k int) *ListNode {
    if head == nil || k == 1 {
        return head
    }

    dummy := &ListNode{Next: head}
    prevGroupTail := dummy
    stack := make([]*ListNode, k)

    for {
        groupStart := prevGroupTail.Next
        groupEnd := prevGroupTail.Next

        // 将当前组的 k 个节点入栈
        for i := 0; i < k && groupEnd != nil; i++ {
            stack[i] = groupEnd
            groupEnd = groupEnd.Next
        }

        if stack[k-1] == nil {
            break // 剩余节点不足一组
        }

        nextGroupStart := stack[k-1].Next
        prevGroupTail.Next = stack[k-1]

        // 逐一出栈，逆序组内节点
        for i := k - 1; i > 0; i-- {
            stack[i].Next = stack[i-1]
        }

        stack[0].Next = nextGroupStart
        prevGroupTail = stack[0]
    }

    return dummy.Next
}
```

## 双指针法

- **算法描述**：双指针法维护两个指针，一个指向每组的头部，另一个用于遍历组内的节点，逆序每组内的节点。同时，根据组数 k，维护组内的头尾节点，将它们与前一组的尾部节点和后一组的头部节点相连接。
- **优点**：与栈法类似，只需一次遍历链表，时间复杂度为 O(n)，并且不需要额外的空间。
- **缺点**：相对其他方法，需要维护更多的指针。

算法实现：  

```go
package main

type ListNode struct {
    Val  int
    Next *ListNode
}

func reverseKGroup(head *ListNode, k int) *ListNode {
    if head == nil || k == 1 {
        return head
    }

    dummy := &ListNode{Next: head}
    prevGroupTail := dummy
    groupStart, groupEnd := head, head

    for {
        // 判断组内是否有足够的节点
        for i := 0; i < k && groupEnd != nil {
            groupEnd = groupEnd.Next
        }

        if groupEnd == nil {
            break // 剩余节点不足一组
        }

        nextGroupStart := groupEnd.Next
        groupEnd.Next = nil
        prevGroupTail.Next = reverseList(groupStart)
        groupStart.Next = nextGroupStart
        prevGroupTail = groupStart
        groupStart = nextGroupStart
        groupEnd = nextGroupStart
    }

    return dummy.Next
}

func reverseList(head *ListNode) *ListNode {
    var prev *ListNode
    current := head

    for current != nil {
        next := current.Next
        current.Next = prev
        prev = current
        current = next
    }

    return prev
}
```

每种算法都有其优势和劣势，选择合适的算法取决于具体情况。栈法和双指针法通常是效率较高的方法，它们可以在一次遍历中完成操作。递归法和迭代法相对直观，但在大多数情况下需要多次遍历链表，效率较低。最佳选择取决于问题要求和个人偏好。

---

<div align="center">
  <img src="../img/qrcode_wechat.jpg" alt="孟斯特">
</div>

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> Author: [mengbin](mengbin1992@outlook.com)  
> blog: [mengbin](https://mengbin.top)  
> Github: [mengbin92](https://mengbin92.github.io/)  
> cnblogs: [恋水无意](https://www.cnblogs.com/lianshuiwuyi/)  

---
