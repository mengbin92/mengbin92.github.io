---
layout: post
title: 查找数组中第K大的元素
tags: [go, 算法]
mermaid: false
math: false
---  

要查找一个数组中的第 K 大元素，有多种方法可以实现，其中常用的方法是使用分治算法或快速选择算法，这两种方法的时间复杂度到时候O(n)。

## 快速选择算法示例：

```go
package main

import "fmt"

func findKthLargest(nums []int, k int) int {
    return quickSelect(nums, 0, len(nums)-1, len(nums)-k)
}

func quickSelect(nums []int, left, right, k int) int {
    if left == right {
        return nums[left]
    }
    pivotIndex := partition(nums, left, right)
    if k == pivotIndex {
        return nums[k]
    } else if k < pivotIndex {
        return quickSelect(nums, left, pivotIndex-1, k)
    } else {
        return quickSelect(nums, pivotIndex+1, right, k)
    }
}

func partition(nums []int, left, right int) int {
    pivot := nums[right]
    i := left
    for j := left; j < right; j++ {
        if nums[j] < pivot {
            nums[i], nums[j] = nums[j], nums[i]
            i++
        }
    }
    nums[i], nums[right] = nums[right], nums[i]
    return i
}

func main() {
    nums := []int{3, 2, 1, 5, 6, 4}
    k := 2
    result := findKthLargest(nums, k)
    fmt.Printf("The %d-th largest element is: %d\n", k, result)
}
```

上述代码使用快速选择算法来查找第 K 大的元素，其中 `quickSelect` 函数递归地在左半部分或右半部分查找，直到找到第 K 大的元素。`partition` 函数用于对数组进行分区操作，将小于 pivot 值的元素移到左边，大于 pivot 值的元素移到右边。

这种方法的平均时间复杂度为 O(n)，其中 n 是数组的长度。最坏情况下的时间复杂度为 O(n^2)，但快速选择算法通常在平均情况下表现良好。这个算法是一种不需要额外引入空间消耗的高效查找方法。

注意，也可以考虑使用标准库中的排序函数，然后直接访问第 K 大的元素，但这会引入 O(nlogn) 的排序时间复杂度，因此不如快速选择算法高效。

## 分治算法示例

使用分治算法查找数组中第 K 大的元素是一种高效的方法，其时间复杂度为 O(n)。下面是使用分治算法实现的查找第 K 大元素的过程：

1. **分解（Divide）**：将数组分为若干个子数组，每个子数组包含一组元素。可以使用任何方法来划分数组，例如随机选择一个元素作为枢纽元素（pivot），然后将数组中小于枢纽元素的元素放在左侧，大于枢纽元素的元素放在右侧。这个过程类似于快速排序中的分区操作。

2. **选择子数组（Select Subarray）**：根据分解步骤中得到的子数组和枢纽元素的位置，确定要继续查找的子数组。如果 K 大元素的位置在枢纽元素的右侧，那么在右侧的子数组中继续查找；如果在左侧，那么在左侧的子数组中查找。

3. **递归（Recursion）**：递归地在所选子数组中查找第 K 大元素。这个过程会反复进行，直到找到第 K 大元素或确定它在左侧或右侧的子数组中。

4. **合并（Combine）**：合并步骤通常不需要执行，因为在递归的过程中，只需继续查找左侧或右侧的子数组中的第 K 大元素。

5. **基本情况（Base Case）**：递归的终止条件通常是当子数组只包含一个元素时，即找到了第 K 大元素。

下面是一个示例的 Go 代码，实现了查找数组中第 K 大元素的分治算法：

```go
package main

import "fmt"

func findKthLargest(nums []int, k int) int {
    if len(nums) == 1 {
        return nums[0]
    }

    pivotIndex := partition(nums)
    rank := pivotIndex + 1

    if rank == k {
        return nums[pivotIndex]
    } else if rank > k {
        return findKthLargest(nums[:pivotIndex], k)
    } else {
        return findKthLargest(nums[pivotIndex+1:], k-rank)
    }
}

func partition(nums []int) int {
    pivotIndex := len(nums) - 1
    pivot := nums[pivotIndex]
    i := 0

    for j := 0; j < pivotIndex; j++ {
        if nums[j] > pivot {
            nums[i], nums[j] = nums[j], nums[i]
            i++
        }
    }

    nums[i], nums[pivotIndex] = nums[pivotIndex], nums[i]
    return i
}

func main() {
    arr := []int{3, 2, 1, 5, 6, 4}
    k := 2
    result := findKthLargest(arr, k)
    fmt.Printf("The %d-th largest element is: %d\n", k, result)
}
```

这个示例中，`findKthLargest` 函数使用了分治算法，通过递归地在子数组中查找第 K 大元素，直到找到或确定其在左侧或右侧的子数组中。`partition` 函数用于将数组分为左侧大于枢纽元素和右侧小于枢纽元素的两部分。

这个算法的时间复杂度是 O(n)，其中 n 是数组的长度。这是因为在每次递归中，都会将数组一分为二，从而快速缩小问题规模。这使得分治算法成为一种高效的查找第 K 大元素的方法。

## 冒泡排序示例

冒泡排序是一种排序算法，通常不是用来查找第 K 大的元素的最佳选择，因为它的时间复杂度较高。然而，你可以结合冒泡排序的思想来查找数组中第 K 大的元素。具体方法是对数组进行 K 次冒泡排序，每次冒泡排序将当前最大的元素移动到数组的末尾，然后查找第 K 大的元素。下面是一个示例实现：

```go
package main

import "fmt"

func findKthLargest(nums []int, k int) int {
    if k < 1 || k > len(nums) {
        return -1 // 无效的 K
    }

    for i := 0; i < k; i++ {
        for j := 0; j < len(nums)-i-1; j++ {
            if nums[j] > nums[j+1] {
                nums[j], nums[j+1] = nums[j+1], nums[j] // 冒泡排序
            }
        }
    }

    // 第 K 大的元素位于数组倒数第 K 个位置
    return nums[len(nums)-k]
}

func main() {
    arr := []int{3, 2, 1, 5, 6, 4}
    k := 2
    result := findKthLargest(arr, k)
    fmt.Printf("The %d-th largest element is: %d\n", k, result)
}
```

在上述示例中，`findKthLargest` 函数执行 K 次冒泡排序，每次将当前最大的元素冒泡到数组的末尾。最后，第 K 大的元素位于数组倒数第 K 个位置。这个算法的时间复杂度是 O(K*n)，其中 n 是数组的长度。虽然不是最高效的算法，但对于小 K 值或小数组来说，是可行的方法。如果 K 较大或数组很大，建议使用其他更高效的算法。

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
