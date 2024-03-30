---
layout: post
title: 分解质因数
tags: [go, 算法]
mermaid: false
math: false
---  

分解质因数是将一个正整数分解为若干个质数的乘积的过程。每个质数都是一个素数，即只能被1和自身整除的数。

分解质因数的一般方法是通过试除法（Trial Division）来进行。该方法的基本思想是从最小的质数开始，逐个尝试将待分解的整数进行整除。如果整数能够整除某个质数，则将该质数作为其中一个因子，并将被整除后的结果继续分解。重复这个过程，直到无法再整除为止。

具体步骤如下：

1. 从最小的质数2开始，尝试将待分解的整数进行整除。
2. 如果整数能够整除当前的质数，则该质数是其中一个因子。将整数除以该质数，并记录下这个质数。
3. 继续用相同的质数尝试整除整数，直到无法整除为止。
4. 如果无法整除了，将当前质数加一，然后重复步骤2和3，直到待分解的整数等于1为止。

最终，得到的所有质数就是待分解整数的所有质因数。

## 实现  

下面是试除法的一个简单实现，借助了标准库中的[math/big](https://pkg.go.dev/math/big)中的`big.Int`类型，以及它的一些常用方法：  

1. **SetInt64(int64)**：将一个int64类型的整数转换为`big.Int`类型。
2. **Mul(x, y *big.Int) *big.Int**：将两个`big.Int`类型的整数相乘。
3. **Cmp(y *big.Int) int**：比较两个`big.Int`类型的整数大小，返回-1表示小于，0表示等于，1表示大于。
4. **Mod(x, y, m *big.Int) *big.Int**：计算x除以y的余数，并将结果存储在m中。
5. **Add(x, y *big.Int) *big.Int**：将两个`big.Int`类型的整数相加。
6. **Div(x, y, m *big.Int) *big.Int**：计算x除以y的商，并将结果存储在m中。
7. **NewInt(int64) *big.Int**：创建一个新的`big.Int`类型的整数。
8. **Sign() int**：返回`big.Int`类型整数的符号，-1表示负数，0表示零，1表示正数。
9. **Set(x *big.Int) *big.Int**：将一个`big.Int`类型的整数赋值给另一个`big.Int`类型的整数。

```go
package main

import (
	"fmt"
	"math/big"
)

// primeFactors 函数用于计算给定大整数 n 的所有质因数，并将它们存储在一个切片中返回。
func primeFactors(n *big.Int) []*big.Int {
	factors := []*big.Int{} // 用于存储质因数的切片

	// 从最小素数 2 开始，逐渐递增检查直到 p*p 大于 n
	p := big.NewInt(2)
	for new(big.Int).Mul(p, p).Cmp(n) <= 0 {
		// 如果 n 能整除 p，则 p 是 n 的一个质因数
		if n.Mod(n, p).Sign() == 0 {
			// 计算 p 的最大幂，同时更新 n
			exp := big.NewInt(0)
			for n.Mod(n, p).Sign() == 0 {
				n.Div(n, p)
				exp.Add(exp, big.NewInt(1))
			}

			// 将 p 的最大幂添加到因子列表中
			for i := 0; i < exp.Int64(); i++ {
				factors = append(factors, new(big.Int).Set(p))
			}
		}
		p.Add(p, big.NewInt(1)) // 尝试下一个素数
	}

	// 如果 n 是一个大于 1 的素数，则 n 是一个质因数
	if n.Cmp(big.NewInt(1)) > 0 {
		factors = append(factors, n)
	}

	return factors // 返回计算得到的质因数切片
}

func main() {
	// 创建大整数 n
	n := new(big.Int).SetInt64(1041601901437367792339)

	// 调用 primeFactors 函数计算 n 的所有质因数
	factors := primeFactors(n)

	// 打印 n 的所有质因数
	fmt.Printf("Prime factors of %d are: ", n)
	for _, factor := range factors {
		fmt.Printf("%d ", factor)
	}
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
