---
layout: post
title: 二叉树遍历
tags: [algorithm, go]
mermaid: false
math: false
---  

二叉树是一种树形数据结构，其中每个节点最多有两个子节点，分别称为左子节点和右子节点。遍历二叉树是一种访问所有节点的过程，主要有三种遍历方式：前序遍历、中序遍历和后序遍历。

### 二叉树遍历方式

1. **前序遍历（Pre-order Traversal）**：
   - 访问根节点
   - 递归遍历左子树
   - 递归遍历右子树

2. **中序遍历（In-order Traversal）**：
   - 递归遍历左子树
   - 访问根节点
   - 递归遍历右子树

3. **后序遍历（Post-order Traversal）**：
   - 递归遍历左子树
   - 递归遍历右子树
   - 访问根节点

### Go语言实现二叉树遍历

以下是用Go语言实现二叉树及其遍历的示例代码：

```go
package main

import "fmt"

// 定义二叉树节点结构体
type TreeNode struct {
    Val   any
    Left  *TreeNode
    Right *TreeNode
}

// 前序遍历
func preOrderTraversal(root *TreeNode) {
    if root == nil {
        return
    }
    fmt.Printf("%v ", root.Val)
    preOrderTraversal(root.Left)
    preOrderTraversal(root.Right)
}

// 中序遍历
func inOrderTraversal(root *TreeNode) {
    if root == nil {
        return
    }
    inOrderTraversal(root.Left)
    fmt.Printf("%v ", root.Val)
    inOrderTraversal(root.Right)
}

// 后序遍历
func postOrderTraversal(root *TreeNode) {
    if root == nil {
        return
    }
    postOrderTraversal(root.Left)
    postOrderTraversal(root.Right)
    fmt.Printf("%v ", root.Val)
}

func main() {
    // 创建一个示例二叉树
    /*
            1
           / \
          2   3
         / \
        4   5
    */
    root := &TreeNode{Val: 1}
    root.Left = &TreeNode{Val: 2}
    root.Right = &TreeNode{Val: 3}
    root.Left.Left = &TreeNode{Val: 4}
    root.Left.Right = &TreeNode{Val: 5}

    // 前序遍历
    fmt.Print("Pre-order Traversal: ")
    preOrderTraversal(root)
    fmt.Println()

    // 中序遍历
    fmt.Print("In-order Traversal: ")
    inOrderTraversal(root)
    fmt.Println()

    // 后序遍历
    fmt.Print("Post-order Traversal: ")
    postOrderTraversal(root)
    fmt.Println()
}
```

---

<div align="center">
  <img src="../img/qrcode_wechat.jpg" alt="孟斯特">
</div>

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  

> Author: [mengbin](mengbin1992@outlook.com)  

> blog: [mengbin](https://mengbin.top)  

> Github: [mengbin92](https://mengbin92.github.io/)  

> cnblogs: [恋水无意](https://www.cnblogs.com/lianshuiwuyi/)  

> 腾讯云开发者社区：[孟斯特](https://cloud.tencent.com/developer/user/6649301)  

---
