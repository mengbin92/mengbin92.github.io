---
layout: post
title: Secure Randomness in Go 1.22
tags: go 
mermaid: false
math: false
---  

原文在[这里](https://go.dev/blog/chacha8rand)。  

> 由 Russ Cox 和 Filippo Valsorda发布于2024年5月2日

计算机并不随机。相反，硬件设计师非常努力地确保计算机每次都以相同的方式运行每个程序。因此，当一个程序确实需要随机数时，那就需要付出额外的努力。传统上，计算机科学家和编程语言区分了两种不同的随机数：统计随机性和加密随机性。在Go中，它们分别由`math/rand`和`crypto/rand`提供。这篇文章是关于Go 1.22如何通过在`math/rand`（以及我们之前文章中提到的`math/rand/v2`）中使用加密随机数源，使这两者更加靠近。结果是更好的随机性和在开发人员意外地使用`math/rand`代替`crypto/rand`时所带来的损失大大减少。

在我们解释Go 1.22做了什么之前，让我们仔细看看统计随机性与加密随机性的区别。  

## 统计随机性 

通过基本的统计测试的随机数通常适合用于模拟，抽样，数值分析，非加密的随机化算法，[随机测试](https://go.dev/doc/security/fuzz/)，[洗牌输入](https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle)和[随机指数回退](https://en.wikipedia.org/wiki/Exponential_backoff#Collision_avoidance)等用例。非常基本，易于计算的数学公式结果对于这些用例已经足够好。但是，由于这些方法如此简单，观察者一旦知道正在使用什么算法，通常可以在看到足够的值后预测序列的其余部分。

几乎所有的编程环境都提供了一种用于生成统计随机数的机制，该机制可以追溯到C语言，再到Research Unix Third Edition（V3），它添加了一对函数：`srand`和`rand`。手册页中包含了如下的说明：

> 警告： 这个例程的作者已经写了很多年的随机数生成器，但是还没写出过一个有效的。

这个说明部分是一个笑话，但也承认这样的生成器[本质上不是随机的](https://www.tuhs.org/pipermail/tuhs/2024-March/029587.html)。

生成器的源代码清楚的表明了它是多么简单。从PDP-11汇编转换到现代C语言，它是：

```c
uint16 ranx;

void
srand(uint16 seed)
{
    ranx = seed;
}

int16
rand(void)
{
    ranx = 13077*ranx + 6925;
    return ranx & ~0x8000;
}
```

调用`srand`可以用单个整数种子为生成器进行种子设置，而`rand`则返回生成器的下一个数字。返回语句中的AND清除了符号位以确保结果为正。

此函数是[线性同余生成器（LCGs）](https://en.wikipedia.org/wiki/Linear_congruential_generator)一般类别的一个实例，Knuth在《计算机程序设计艺术》第二卷的第3.2.1节中对其进行了分析。LCGs的主要优点是可以选择常数，使它们在重复之前一次发出每个可能的输出值，就像Unix实现对15位输出做的那样。然而，LCGs的一个严重问题是，状态的高位完全不影响低位，因此将序列截断到k位必然会重复一个更小的周期。最低位必须切换：0,1,0,1,0,1。最低的两个位必须向上或向下计数：0,1,2,3,0,1,2,3，或者0,3,2,1,0,3,2,1。有四种可能的三位序列；原始的Unix实现为0,5,6,3,4,1,2,7重复的序列。（通过对值模一个质数进行简化可以避免这些问题，但那在当时会显得代价很高。参看 S. K. Park 与 K. W. Miller 的 1988 年的《计算机通信评论》上的论文[《难得一见的好的随机数生成器》](https://dl.acm.org/doi/10.1145/63039.63042)以获取一个较简短的分析以及Knuth第二卷的第一章以获取较长的分析。）

尽管存在这些已知的问题，`srand`和`rand`函数仍被包含在第一个C标准中，并且从那时起几乎所有语言都包含了等效的功能。LCGs曾经是主导的实现策略，尽管由于一些重要的缺点，它们的受欢迎程度已经下降。一个重要的剩余用途是`java.util.Random`，它给`java.lang.Math.random`提供了动力。

从上面的实现你也可以看出，通过`rand`结果完全暴露了内部状态。一个知道算法并看到单个结果的观察者可以轻松计算所有未来的结果。如果你正在运行一个服务器，计算一些会变公开的随机值和一些必须保持秘密的随机值，使用这种生成器将是灾难性的：这些秘密将不再是秘密。  

尽管更现代的随机生成器并不像原始的 Unix 生成器那样糟糕，但它们仍然是不完全不可预测的。为了阐明这一点，接下来我们将看一下 Go 1 中原始的`math/rand`生成器和我们在`math/rand/v2`中添加的 PCG 生成器。  

### Go 1生成器

Go 1 的 math/rand 中使用的生成器是所谓的[线性反馈移位寄存器](https://en.wikipedia.org/wiki/Linear-feedback_shift_register)的一个实例。该算法基于 George Marsaglia 的想法，由 Don Mitchell 和 Jim Reeds 进行了调整，然后由 Ken Thompson 为 Plan 9，后来是 Go 进行了进一步定制。它没有官方名称，因此本文将其称为 Go 1 生成器。  

Go 1生成器的内部状态是一个包含607个uint64s的切片`vec`。在这个切片中，有两个特殊的元素：`vec[606]`，即最后一个元素，被称为“水龙头”（tap），`vec[334]`被称为“饲料”（feed）。为了生成下一个随机数，生成器将水龙头和饲料相加得到一个值`x`，将`x`存回饲料位置，将整个切片向右移动一个位置（水龙头移动到`vec[0]`，`vec[i]`移动到`vec[i+1]`），然后返回`x`。生成器被称为“线性反馈”，因为水龙头*被加到*饲料上；整个状态是一个“移位寄存器”，因为每一步都会移动切片条目。  

当然，实际上移动每个切片条目向前将是代价高昂的，因此实现改为将切片数据保留在原地，并在每一步中将水龙头和饲料位置向后移动。代码如下所示：  

```go
func (r *rngSource) Uint64() uint64 {
    r.tap--
    if r.tap < 0 {
        r.tap += len(r.vec)
    }

    r.feed--
    if r.feed < 0 {
        r.feed += len(r.vec)
    }

    x := r.vec[r.feed] + r.vec[r.tap]
    r.vec[r.feed] = x
    return uint64(x)
}
```  

生成下一个数字相当便宜：两个减法，两个条件加法，两个加载，一个加法，一个存储。  

不幸的是，由于生成器直接从内部状态`vec`中返回一个切片元素，因此从生成器读取607个值会完全暴露其所有状态。有了这些值，你可以通过填充你自己的`vec`然后运行算法来预测所有未来的值。你也可以通过反向运行算法（从`feed`中减去`tap`并将切片向左移动）来恢复所有先前的值。  

作为一个完整的演示，这里有一个生成伪随机认证令牌的[不安全程序](https://go.dev/play/p/v0QdGjUAtzC)，以及一段给定一系列早期令牌时预测下一个令牌的代码。正如你所看到的，Go 1生成器根本不提供任何安全性（也不是有意为之）。生成的数字的质量也取决于vec的初始设置。  

### PCG生成器  

对于`math/rand/v2`，我们希望提供一个更现代统计随机生成器，并最终选择了Melissa O'Neill在2014年的论文[PCG: A Family of Simple Fast Space-Efficient Statistically Good Algorithms for Random Number Generation](https://www.pcg-random.org/pdf/hmc-cs-2014-0905.pdf)中发表的PCG算法。论文中的详尽分析可能让人一眼难以注意到这些生成器其实非常简单：PCG是一个经过后处理的128位LCG（线性同余生成器）。  

如果状态`p.x`是一个uint128（假设），计算下一个值的代码将是：  

```go
const (
    pcgM = 0x2360ed051fc65da44385df649fccf645
    pcgA = 0x5851f42d4c957f2d14057b7ef767814f
)

type PCG struct {
    x uint128
}

func (p *PCG) Uint64() uint64 {
    p.x = p.x * pcgM + pcgA
    return scramble(p.x)
}
```  

整个状态是一个单一的128位数，更新是一个128位乘法和加法。在返回语句中，`scramble`函数将128位状态减少到一个64位状态。原始的PCG被复用（假设再次使用一个uint128类型）：  

```go
func scramble(x uint128) uint64 {
    return bits.RotateLeft(uint64(x>>64) ^ uint64(x), -int(x>>122))
}
```  

这段代码将128位状态的两部分异或在一起，然后根据状态的顶部六位旋转结果。这个版本被称为PCG-XSL-RR，代表“异或移位低，右旋”。  

[在提案讨论期间，基于O'Neill的建议](https://go.dev/issue/21835#issuecomment-739065688)，Go的PCG使用了一个新的基于乘法的混淆函数，该函数更积极地混合位：  

```go
func scramble(x uint128) uint64 {
    hi, lo := uint64(x>>64), uint64(x)
    hi ^= hi >> 32
    hi *= 0xda942042e4dd58b5
    hi ^= hi >> 48
    hi *= lo | 1
}
```  

O'Neill称这种带有这种混淆器的PCG为PCG-DXSM，意为“双重异或移位乘法”。Numpy也使用这种形式的PCG。  

尽管PCG在生成每个值时使用更多的计算，但它使用的状态明显更少：两个uint64而不是607。它对那个状态的初始值也不太敏感，而且[它通过了许多其他生成器无法通过的统计测试](https://www.pcg-random.org/statistical-tests.html)。在许多方面，它都是一个理想的统计生成器。  

即便如此，PCG也不是不可预测的。虽然准备结果的位混淆并没有像LCG和Go 1生成器那样直接暴露状态，但[PCG-XSL-RR仍然可以被逆转](https://pdfs.semanticscholar.org/4c5e/4a263d92787850edd011d38521966751a179.pdf)，如果PCG-DXSM也能被逆转也不足为奇。对于机密信息，我们需要一些不同的东西。

## 加密随机性

在实践中，*加密随机数*必须是完全不可预测的，即使是对知道它们是如何生成的并且已经观察到之前生成的任何数量的值的观察者也是如此。加密协议的安全性、秘密密钥、现代商业、在线隐私等都需要访问加密随机性来保障。  

提供加密随机性最终是操作系统的工作，它可以从物理设备（鼠标、键盘、磁盘和网络的时间，以及最近[由CPU本身直接测量的电噪声](https://web.archive.org/web/20141230024150/http://www.cryptography.com/public/pdf/Intel_TRNG_Report_20120312.pdf)）中收集真正的随机性。一旦操作系统收集了有意义的随机性数量——比如说，至少有256位——它就可以使用加密哈希或加密算法将那个种子拉伸成一个任意长的随机数序列。（实际上，操作系统也在不断地收集和向序列中添加新的随机性。）  

精确的操作系统接口随着时间的发展而演变。十年前，大多数系统提供了一个名为`/dev/random`或类似名称的设备文件。今天，认识到随机性已经变得多么基础，操作系统改而提供一个直接的系统调用。（这也允许程序在与文件系统断开连接时读取随机性。）在Go中，`crypto/rand`包抽象了这些细节，在每个操作系统上提供相同的接口：`rand.Read`。  

对于`math/rand`来说，每次需要uint64时都向操作系统请求随机性是不切实际的。但我们可以使用加密技术来定义一个进程内的随机生成器，它比LCGs、Go 1生成器甚至PCG都有所提升。  

### ChaCha8Rand生成器  

我们的新生成器，我们毫无想象力地命名为ChaCha8Rand以便于规范目的，并作为`math/rand/v2`的`rand.ChaCha8`实现，是Daniel J. Bernstein的[ChaCha流密码](https://cr.yp.to/chacha.html)的一个略有修改的版本。ChaCha以称为ChaCha20的20轮形式广泛使用，包括在TLS和SSH中。Jean-Philippe Aumasson的论文[Too Much Crypto](https://eprint.iacr.org/2019/1492.pdf)有力地论证了8轮形式的ChaCha8也是安全的（而且它的速度大约快2.5倍）。我们使用ChaCha8作为ChaCha8Rand的核心。  

大多数流密码，包括ChaCha8，都是通过定义一个函数来工作的，该函数给定一个密钥和一个块编号，并产生一个固定大小的看似随机的数据块。这些目标（并且通常满足）的加密标准是，在没有某种指数级昂贵的暴力搜索的情况下，这种输出与实际随机数据无法区分。通过将输入数据的连续块与连续随机生成的块进行异或操作，对消息进行加密或解密。为了将ChaCha8用作`rand.Source`，我们直接使用生成的块，而不是将它们与输入数据进行异或（这相当于加密或解密所有零）。  

我们改变了一些细节，使ChaCha8Rand更适合生成随机数。简而言之：  

- ChaCha8Rand使用32字节种子作为ChaCha8 key。
- ChaCha8生成64字节的块，计算时将一个块视为16个`uint32`。一种常见的实现是使用[SIMD指令](https://en.wikipedia.org/wiki/Single_instruction,_multiple_data)一次计算四个块，这些指令在16个每个包含四个`uint32`的向量寄存器上运行。这会生成四个交错的块，必须对它们进行解交错，以便与输入数据进行XOR。ChaCha8Rand定义交错的块是随机数据流，从而消除了解交错的成本。（出于安全目的，这可以被视为标准的ChaCha8后面跟着一个重排。）
- ChaCha8在完成一个块时会向块中的每个`uint32`添加某些值。其中一半的值是密钥材料，另一半是已知的常数。ChaCha8Rand定义已知常数不再重新添加，从而去掉了最后一半的加法操作。（出于安全目的，这可以被视为标准的ChaCha8之后减去已知常数。）
- 每隔16个生成的块，ChaCha8Rand就会取该块的最后一个32个字节作为下一个16个块的密钥。这提供了一种[前向保密性](https://en.wikipedia.org/wiki/Forward_secrecy)：如果系统因攻击而受损，攻击者恢复了生成器的全部内存状态，那么只能恢复自上次重新密钥以来的生成的值。过去的数据是无法访问的。到目前为止定义的ChaCha8Rand必须一次生成4个块，但我们选择每16个块进行一次密钥轮换，以便留下使用256位或512位向量更快实现的可能性，这些向量可以一次生成8个或16个块。  

我们编写并发布了一个[针对ChaCha8Rand的C2SP规范](https://c2sp.org/chacha8rand)，以及测试用例。这将使其他实现能够与给定种子的Go实现共享可重复性。  

Go运行时现在维护一个每个核心的ChaCha8Rand状态（300字节），用操作系统提供的加密随机性播种，以便可以快速生成随机数，而不会产生任何锁争用。每个核心分配300字节可能听起来很昂贵，但在一个16核系统上，它大约相当于存储一个共享的Go 1生成器状态（4,872字节）。速度是值得的内存开销。这个每个核心的ChaCha8Rand生成器现在在Go标准库的三个不同地方使用：  

- `math/rand/v2`包中的函数，例如`rand.Float64`和`rand.N`，始终使用ChaCha8Rand。
- `math/rand`包中的函数，如`rand.Float64`和`rand.Intn`，在未调用`rand.Seed`时使用`ChaCha8Rand`。在`math/rand`中应用ChaCha8Rand可以提高程序的安全性，即使它们尚未更新到`math/rand/v2`，前提是不调用`rand.Seed`。（如果调用了`rand.Seed`，实现需要回退到 Go 1 生成器以实现兼容性。）
- 运行时选择使用 ChaCha8Rand 为每个新映射生成哈希种子，而不是之前使用的较不安全的基[wyrand 的生成器](https://github.com/wangyi-fudan/wyhash)。需要随机种子是因为，如果攻击者知道映射实现所使用的特定哈希函数，他们可以准备输入使映射陷入二次行为（参见 Crosby 和 Wallach 的“[通过算法复杂性攻击拒绝服务](https://www.usenix.org/conference/12th-usenix-security-symposium/denial-service-algorithmic-complexity-attacks)”）。使用每个映射的种子，而不是所有映射的一个全局种子，也避免了其他退化行为。并不完全清楚映射是否需要加密随机种子，但也不清楚它们不需要。切换似乎谨慎且容易实现。

需要自己的ChaCha8Rand实例的代码可以直接创建自己的`rand.ChaCha8`。  

### 修复安全性错误

Go 的目标是帮助开发者编写默认安全的代码。当我们观察到与安全后果相关的常见错误时，我们会寻找减少这种错误风险或完全消除它的方法。在这种情况下，`math/rand`的全局生成器太容易预测，导致在各种情境中出现严重问题。

例如，当 Go 1.20 弃用`math/rand`的`Read`时，我们从开发者那里听说（多亏了工具指出使用了已弃用的功能），他们在需要使用`crypto/rand`的`Read`的地方使用了它，比如生成密钥材料。使用 Go 1.20，这个错误是一个严重的安全问题，值得详细调查以了解损害的程度。密钥被用在哪里？密钥是如何暴露的？是否有其他随机输出暴露，可能让攻击者推导出密钥？等等。使用 Go 1.22，这个错误只是一个错误。使用`crypto/rand`仍然更好，因为操作系统内核可以更好地保持随机值对各种窥探者的秘密，内核不断为其生成器添加新的熵，而且内核受到了更多的审查。但是，意外使用`math/rand`不再是一个安全灾难。

还有许多看似不是“加密”但实际上需要不可预测随机性的用例。通过使用 ChaCha8Rand 而不是 Go 1 生成器，这些情况变得更加健壮。

例如，考虑生成一个[随机 UUID](https://en.wikipedia.org/wiki/Universally_unique_identifier#Version_4_(random))。由于UUID不是秘密的，使用`math/rand`似乎没问题。但是，如果`math/rand`是用当前时间播种的，那么在不同计算机上同时运行它将产生相同的值，使它们不是“全球唯一”的。在只能以毫秒精度提供当前时间的系统上，这种情况尤其可能发生。即使在 Go 1.20 中引入的使用操作系统提供的熵自动播种，Go 1 生成器的种子只是一个63位整数，因此一个在启动时生成UUID的程序只能生成 $2^{63}$ 个可能的UUID，并且在大约 $2^{31}$ 个UUID之后很可能出现冲突。使用 Go 1.22，新的ChaCha8Rand生成器从256位熵中播种，可以生成  $2^{256}$ 个可能的首选UUID。它不必担心冲突。

再举一个例子，考虑前端服务器中的负载平衡，它随机地将传入的请求分配给后端服务器。如果攻击者可以观察分配情况并知道生成它们的可预测算法，那么攻击者可以发送大量便宜的请求，但安排所有昂贵的请求都落在单个后端服务器上。使用 Go 1 生成器，这是一个不太可能但合理的问题。使用 Go 1.22，这根本不是问题。

在所有这些示例中，Go 1.22 已经消除或大大减少了安全问题。  

### 性能 

ChaCha8Rand的安全优势确实有一些小的成本，但ChaCha8Rand的性能仍然与Go 1 生成器和PCG相当。以下图表比较了三种生成器在各种硬件上的性能，运行两种操作：原始操作“Uint64”，它返回随机流中的下一个`uint64`值；以及更高级别的操作“N(1000)”，它返回范围 [0, 1000) 内的一个随机值。  

<div align="center">
  <img src="../img/2024-05-07/performance.png" alt="performance">
</div>

翻译：
“运行32位代码”的图表显示了现代64位x86芯片执行使用`GOARCH=386`构建的代码，这意味着它们以32位模式运行。在这种情况下，由于PCG需要128位乘法，使其比仅使用32位SIMD算术的ChaCha8Rand慢。实际的32位系统每年变得越来越不重要，但仍然有趣的是，在这些系统上，ChaCha8Rand比PCG更快。

在某些系统上，“Go 1：Uint64”比“PCG：Uint64”快，但“Go 1：N(1000)”比“PCG：N(1000)”慢。这是因为“Go 1：N(1000)”使用了`math/rand`的算法将随机int64缩减到范围 [0, 1000) 内的值，而该算法执行了两个64位整数除法操作。相比之下，“PCG：N(1000)”和“ChaCha8：N(1000)”使用了[更快的 math/rand/v2 算法](https://go.dev/blog/randv2#problem.rand)，该算法几乎总是避免了除法。对于32位执行和在Ampere上，移除64位除法主导了算法变化。

总体而言，ChaCha8Rand比 Go 1 生成器慢，但它从未慢超过两倍，在典型服务器上差异从未超过3ns。很少有程序会因为这个差异而受阻，许多程序将享受到改进的安全性。  

## 结论  

Go 1.22在不进行任何代码更改的情况下使您的程序更加安全。我们通过识别意外使用`math/rand`而不是`crypto/rand`的常见错误，然后加强`math/rand`来实现这一点。这是Go持续旅程中的一小步，旨在默认情况下保持程序安全。

这类错误并非Go所独有。例如，npm keypair包尝试使用Web Crypto API生成RSA密钥对，但如果它们不可用，它将回退到JavaScript的`Math.random`。这几乎不是一个孤立案例，我们系统的安全性不能依赖于开发人员不犯错误。相反，我们希望最终所有编程语言都将转向用于“数学”随机性的加密强伪随机生成器，消除这种错误，或者至少大大减少其影响范围。Go 1.22 的[ChaCha8Rand](https://c2sp.org/chacha8rand)实现证明了这种方法与其他生成器相比具有竞争力。  

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
