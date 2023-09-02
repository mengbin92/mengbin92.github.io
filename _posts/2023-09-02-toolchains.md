---
layout: post
title: 完全可复制、经过验证的 Go 工具链
tags: go
mermaid: false
math: false
---  

原文在[这里](https://go.dev/blog/rebuild)。  

> 由 Russ Cox 发布于 2023年8月28日

开源软件的一个关键优势是任何人都可以阅读源代码并检查其功能。然而，大多数软件，甚至是开源软件，都以编译后的二进制形式下载，这种形式更难以检查。如果攻击者想对开源项目进行供应链攻击，最不可见的方式是替换正在提供的二进制文件，同时保持源代码不变。

解决这种类型的攻击的最佳方法是使开源软件的构建具有可重现性，这意味着以相同的源代码开始的每个构建都会产生相同的输出。这样，任何人都可以通过从真实源代码构建并检查重建的二进制文件是否与已发布的二进制文件完全相同来验证发布的二进制文件是否没有隐藏的更改。这种方法证明了二进制文件没有后门或源代码中不存在的其他更改，而无需分解或查看其中的内容。由于任何人都可以验证二进制文件，因此独立的团体可以轻松检测并报告供应链攻击。

随着供应链安全的重要性日益增加，可重现构建变得越来越重要，因为它们提供了一种验证开源项目已发布的二进制文件的简单方式。

Go 1.21.0 是第一个具有完全可重现构建的 Go 工具链。以前的工具链也可以重现，但需要付出大量的努力，而且可能没有人这样做：他们只是相信在 go.dev/dl 上发布的二进制文件是正确的。现在，“信任但要验证”变得容易了。

本文解释了使构建具有可重现性所需的内容，检查了我们必须对 Go 进行的许多更改，以使 Go 工具链具有可重现性，并通过验证 Go 1.21.0 的 Ubuntu 包的一个好处来演示可重现性之一。

## 使构建具有可重现性

计算机通常是确定性的，因此您可能认为所有构建都将同样可重现。从某种意义上说，这是正确的。让我们将某个信息称为相关输入，当构建的输出取决于该输入时。如果构建可以重复使用所有相同的相关输入，那么构建是可重现的。不幸的是，许多构建工具事实上包含了我们通常不会意识到是相关的输入，而且可能难以重新创建或提供作为输入。当输入事实上是相关的但我们没有打算让它成为相关输入时，让我们称之为意外输入。

构建系统中最常见的意外输入是当前时间。如果构建将可执行文件写入磁盘，文件系统会将当前时间记录为可执行文件的修改时间。如果构建然后使用类似于 “tar” 或 “zip” 之类的工具打包该文件，那么修改时间将写入存档中。我们当然不希望构建根据当前时间更改，但实际上它确实发生了。因此，当前时间事实上成为构建的意外输入。更糟糕的是，大多数程序都不允许您将当前时间提供为输入，因此没有办法重复此构建。为了解决这个问题，我们可以将创建的文件的时间戳设置为 Unix 时间 0 或从构建的某个源文件中读取的特定时间。这样，当前时间不再是构建的相关输入。

构建的常见相关输入包括：

- 要构建的源代码的特定版本；
- 将包括在构建中的依赖项的特定版本；
- 运行构建的操作系统，这可能会影响生成的二进制文件中的路径名；
- 构建系统上运行的CPU架构，这可能会影响编译器使用的优化或某些数据结构的布局；
- 正在使用的编译器版本以及传递给它的编译器选项，这会影响代码的编译方式；
- 包含源代码的目录的名称，这可能会出现在调试信息中；
- 运行构建的帐户的用户名、组名、uid和gid，这可能会出现在存档中的文件元数据中；
- 还有许多其他因素。

要使构建具有可重现性，每个相关输入都必须在构建中是可配置的，然后必须将二进制文件发布在明确列出了每个相关输入的配置旁边。如果你已经做到了这一点，那么你有一个可重现的构建。恭喜！

但我们还没有完成。如果只有在首先找到具有正确体系结构的计算机，安装特定操作系统版本，编译器版本，将源代码放在正确目录中，正确设置用户身份等情况下才能重现这些二进制文件，那么在实践中这可能是太麻烦了。  

我们希望构建不仅具有可重现性，而且*易于重现*。为此，我们需要识别相关输入，然后不是仅仅将它们记录下来，而是消除它们。构建显然必须依赖于正在构建的源代码，但其他一切都可以被消除。当构建的唯一相关输入是其源代码时，我们可以称之为*完全可重现的*。

## 完全可重现的 Go 构建

从 Go 1.21 版本开始，Go 工具链具有完全可重现的特性：它的唯一相关输入是该构建的源代码。我们可以在支持 Go 的任何主机上构建特定的工具链（例如，针对 Linux/x86-64 的 Go），包括在 Linux/x86-64 主机、Windows/ARM64 主机、FreeBSD/386 主机或其他支持 Go 的主机上构建，并且可以使用任何 Go 引导编译器，包括一直追溯到 Go 1.4 的 C 实现的引导编译器，还可以改变其他任何细节。但这些都不会改变构建出来的工具链。如果我们从相同的工具链源代码开始，我们将得到完全相同的工具链二进制文件。

这种完全可重现性是自从 Go 1.10 以来努力的巅峰，尽管大部分工作集中在 Go 1.20 和 Go 1.21 中进行。以下是一些最有趣的相关输入，它们被消除了，从而实现了这种完美的可重现性。

### 在 Go 1.10 中的可重现性

Go 1.10 引入了一个内容感知的构建缓存，它根据构建输入的指纹而不是文件修改时间来决定目标是否为最新。因为工具链本身是这些构建输入之一，而且 Go 是用 Go 编写的，所以[引导过程](https://go.dev/s/go15bootstrap)只有在单台机器上的工具链构建是可重复的情况下才能收敛。整个工具链构建过程如下：

<div align="center">
  <img src="../img/2023-09-02/toolchains1.png" alt="孟斯特">
</div>

我们首先使用早期版本的 Go 构建当前 Go 工具链的源代码，这个早期版本是引导工具链（Go 1.10 使用 Go 1.4，用 C 编写；Go 1.21 使用 Go 1.17）。这会生成 "toolchain1"，然后我们再次使用 "toolchain1" 来构建一切，生成 "toolchain2"，接着使用 "toolchain2" 再次构建一切，生成 "toolchain3"。

"toolchain1" 和 "toolchain2" 是从相同的源代码构建的，但使用了不同的 Go 实现（编译器和库），所以它们的二进制文件肯定是不同的。然而，如果这两个 Go 实现都是非有错误的、正确的实现，那么 "toolchain1" 和 "toolchain2" 应该表现完全相同。特别是，当给出 Go 1.X 源代码时，"toolchain1" 的输出（"toolchain2"）和 "toolchain2" 的输出（"toolchain3"）应该是相同的，这意味着 "toolchain2" 和 "toolchain3" 应该是相同的。

至少，这是理论上的想法。在实际操作中，要使其成为真实情况，需要消除一些无意的输入：

在构建系统中，有一些常见的无意的输入（unintentional inputs）可能导致构建的结果不可重复，这里介绍了其中两个主要问题：

**随机性（Randomness）**：在使用多个 Goroutines 和锁进行序列化的情况下，例如地图迭代和并行工作，可能会引入结果生成的顺序上的随机性。这种随机性会导致工具链每次运行时产生几种不同的可能输出之一。为了使构建可重复，必须找到这些随机性，并在用于生成输出之前对相关项目的列表进行排序。  

**引导库（Bootstrap Libraries）**：编译器使用的任何库，如果它可以从多个不同的正确输出中选择，可能会在不同的 Go 版本之间更改其输出。如果该库的输出更改导致编译器输出更改，那么 "toolchain1" 和 "toolchain2" 将不会在语义上相同，"toolchain2" 和 "toolchain3" 也不会在比特位上相同。  

一个经典的例子是 `sort` 包，它可以以[任何顺序](https://go.dev/blog/compat#output)放置比较相等的元素。寄存器分配器可能会根据常用变量对其进行排序，链接器会根据大小对数据段中的符号进行排序。为了完全消除排序算法的任何影响，使用的比较函数不能将两个不同的元素报告为相等。在实践中，要在工具链的每次使用 `sort` 的地方强制执行这种不变性太困难，因此我们安排将 Go 1.X 中的 `sort` 包复制到呈现给引导编译器的源代码树中。这样，编译器在使用引导工具链时将使用相同的排序算法，就像在使用自身构建时一样。

另一个我们不得不复制的包是 `compress/zlib`，因为链接器会写入压缩的调试信息，而对压缩库的优化可能会更改精确的输出。随着时间的推移，我们[还将其他包添加到了这个列表](https://go.googlesource.com/go/+/go1.21.0/src/cmd/dist/buildtool.go#55)中。这种方法的额外好处是允许 Go 1.X 编译器立即使用这些包中添加的新 API，但代价是这些包必须编写以与较旧版本的 Go 兼容。


### 在 Go 1.20 中的可重现性

Go 1.20 为易于重现的构建和[工具链管理](https://go.dev/blog/toolchain)做了准备，通过从工具链构建中移除两个相关输入来解决了更多的问题。

**主机 C 工具链**：一些 Go 包，尤其是 `net` 包，默认在大多数操作系统上[使用 cgo](https://go.dev/blog/cgo)。在某些情况下，比如 macOS 和 Windows，使用 cgo 调用系统 DLL 是解析主机名的唯一可靠方法。然而，当我们使用 cgo 时，会调用主机的 C 工具链（即特定的 C 编译器和 C 库），不同的工具链具有不同的编译算法和库代码，从而产生不同的输出。一个使用 cgo 的包的构建图如下所示：  

<div align="center">
  <img src="../img/2023-09-02/toolchains2.png" alt="孟斯特">
</div>  

因此，主机的 C 工具链是预编译的 net.a（与工具链一起提供的库文件）的相关输入。在 Go 1.20 中，我们决定通过从工具链中删除 net.a 来解决这个问题。换句话说，Go 1.20 停止提供预编译的包来填充构建缓存。现在，当程序第一次使用 net 包时，Go 工具链会使用本地系统的 C 工具链进行编译并缓存结果。除了从工具链构建中删除相关输入和减小工具链下载的大小外，不提供预编译包还使工具链下载更加便携。如果我们在一个系统上使用一个 C 工具链构建 net 包，然后在不同的系统上使用不同的 C 工具链编译程序的其他部分，通常不能保证这两部分可以链接在一起。

最初我们提供预编译的 net 包的一个原因是允许在没有安装 C 工具链的系统上构建使用 net 包的程序。如果没有预编译的包，那么在这些系统上会发生什么呢？答案因操作系统而异，但在所有情况下，我们都安排好了 Go 工具链，以便继续很好地构建纯 Go 程序，而无需主机的 C 工具链。

- 在 macOS 上，我们重写了 package net，使用了 cgo 使用的底层机制，而没有实际的 C 代码。这样可以避免调用主机的 C 工具链，但仍然生成一个引用所需系统 DLLs 的二进制文件。这种方法之所以可行，是因为每台 Mac 都安装了相同的动态库。使非 cgo macOS 版本的 package net 使用系统 DLLs 也意味着交叉编译的 macOS 可执行文件现在使用系统 DLLs 进行网络访问，解决了一个长期存在的功能请求。
- 在 Windows 上，package net 已经直接使用 DLLs 而没有 C 代码，因此不需要进行任何更改。
- 在 Unix 系统上，我们不能假定网络代码的特定 DLL 接口，但纯 Go 版本对于使用典型 IP 和 DNS 设置的系统来说效果很好。此外，在 Unix 系统上安装 C 工具链要容易得多，而在 macOS 和尤其是 Windows 上则要困难得多。我们更改了 go 命令，根据系统是否安装了 C 工具链，自动启用或禁用 cgo。没有 C 工具链的 Unix 系统将退回到 package net 的纯 Go 版本，在极少数情况下，如果这还不够好，它们可以安装 C 工具链。

在删除了预编译包之后，Go 工具链中仍然依赖于主机 C 工具链的部分是使用 package net 构建的二进制文件，特别是 go 命令。有了 macOS 的改进，现在可以使用 cgo 禁用构建这些命令，完全消除了主机 C 工具链作为输入的问题，但我们将这最后一步留给了 Go 1.21。  

**主机动态链接器**：当程序在使用动态链接的 C 库的系统上使用 cgo 时，生成的二进制文件会包含系统的动态链接器路径，类似于 /lib64/ld-linux-x86-64.so.2。如果路径错误，二进制文件将无法运行。通常，每种操作系统/架构组合都有一个正确的路径。不幸的是，像 Alpine Linux 这样的基于 musl 的 Linux 和像 Ubuntu 这样的基于 glibc 的 Linux 使用不同的动态链接器。为了使 Go 在 Alpine Linux 上运行，Go 引导过程如下：  

<div align="center">
  <img src="../img/2023-09-02/toolchains3.png" alt="孟斯特">
</div>

引导程序 cmd/dist 检查了本地系统的动态链接器，并将该值写入一个新的源文件，与其余链接器源代码一起编译，实际上将默认值硬编码到链接器本身。然后，当链接器从一组已编译的包构建程序时，它使用该默认值。结果是，在 Alpine 上构建的 Go 工具链与在 Ubuntu 上构建的工具链不同：主机配置是工具链构建的一个相关输入。这是一个可重复性问题，但也是一个可移植性问题：在 Alpine 上构建的 Go 工具链不会在 Ubuntu 上构建可工作的二进制文件，反之亦然。

对于 Go 1.20，我们采取了一步措施来解决可重复性问题，即在运行时更改链接器，以便在运行时咨询主机配置，而不是在工具链构建时硬编码默认值：  

<div align="center">
  <img src="../img/2023-09-02/toolchains4.png" alt="孟斯特">
</div>

这解决了在 Alpine Linux 上链接器二进制文件的可移植性问题，尽管工具链整体上没有解决，因为 `go` 命令仍然使用了 `package net`，因此也使用了 `cgo`，因此在其自身的二进制文件中有一个动态链接器引用。就像前一节一样，编译 `go` 命令时禁用 `cgo` 将解决这个问题，但我们将这个更改留到了 Go 1.21 版本中（我们觉得在 Go 1.20 版本周期内没有足够的时间来充分测试这个更改）。

## Go 1.21 中的复现性

在 Go 1.21 中，完美可复现性的目标在望，我们处理了其余的，主要是一些小的相关输入。  

**Host C toolchain and dynamic linker（主机C工具链和动态链接器）**：在 Go 1.20 中，已经采取了一些重要措施来消除主机C工具链和动态链接器作为相关输入的问题。Go 1.21 则通过禁用cgo来完成了消除这些相关输入的工作。这提高了工具链的可移植性。Go 1.21 是第一个可以在Alpine Linux系统上无需修改就能运行的标准Go工具链版本。  

去除这些相关的输入使得可以在不损失功能的情况下从不同系统进行交叉编译 Go 工具链成为可能。这反过来提高了 Go 工具链的供应链安全性：现在我们可以使用受信任的 Linux/x86-64 系统为所有目标系统构建 Go 工具链，而不需要为每个目标系统安排一个单独的受信任系统。因此，Go 1.21 是首个在 [go.dev/dl/](https://go.dev/dl/) 中发布适用于所有系统的二进制文件的版本。

**Source directory（源代码目录）**：Go程序包含了运行时和调试元数据中的完整路径，以便在程序崩溃或在调试器中运行时，堆栈跟踪包含源文件的完整路径，而不仅仅是文件名。不幸的是，包含完整路径使源代码存储目录成为构建的相关输入。为了解决这个问题，Go 1.21 将发布工具链构建更改为使用`go install -trimpath`来安装命令，将源目录替换为代码的模块路径。这样，如果发布的编译器崩溃，堆栈跟踪将打印类似`cmd/compile/main.go`的路径，而不是`/home/user/go/src/cmd/compile/main.go`。由于完整路径将引用不同机器上的目录，这个重写不会有损失。另外，在非发布构建中，保留完整路径，以便在开发人员自身导致编译器崩溃时，IDE和其他工具可以轻松找到正确的源文件。

**Host operating system（主机操作系统）**：Windows系统上的路径是用反斜杠分隔的，如 `cmd\compile\main.go` 。而其他系统使用正斜杠，如 `cmd/compile/main.go` 。尽管早期版本的Go已经规范化了大多数这些路径以使用正斜杠，但某种不一致性又重新出现了，导致Windows上的工具链构建略有不同。我们找到并修复了这个错误。

**Host architecture（主机架构）**：Go可以运行在各种ARM系统上，并且可以使用软件浮点数库（SWFP）或使用硬件浮点指令（HWFP）来生成代码。默认使用其中一种模式的工具链将会有所不同。就像我们之前在动态链接器中看到的那样，Go引导过程会检查构建系统，以确保生成的工具链在该系统上可以正常工作。出于历史原因，规则是“假设SWFP，除非构建运行在带有浮点硬件的ARM系统上”，跨编译工具链会假定为SWFP。如今，绝大多数ARM系统都配备了浮点硬件，因此这引入了本地编译和跨编译工具链之间不必要的差异，而且进一步复杂的是，Windows ARM构建始终假定为HWFP，使这个决策依赖于操作系统。我们将规则更改为“假设HWFP，除非构建运行在不带浮点硬件的ARM系统上”。这样，跨编译和在现代ARM系统上构建将产生相同的工具链。

**Packaging logic（打包逻辑）**：用于创建我们发布供下载的工具链档案的所有代码都存储在单独的Git存储库中（golang.org/x/build），档案的确切细节随时间而变。如果要重现这些档案，您需要具有该存储库的正确版本。我们通过将代码移动到Go主源代码树中（作为cmd/distpack）来消除了这个相关输入。截至Go 1.21，如果您拥有特定版本的Go源代码，那么您也拥有打包档案的源代码。golang.org/x/build存储库不再是相关输入。

**User IDs（用户ID）**：我们发布供下载的tar档案是从写入文件系统的分发构建的，并且使用tar.FileInfoHeader将用户和组ID从文件系统复制到tar文件中，使运行构建的用户成为相关输入。我们通过修改打包代码来清除这些相关输入。

**Current time（当前时间）**：与用户ID一样，我们发布供下载的tar和zip档案也是通过将文件系统修改时间复制到档案中来构建的，使当前时间成为相关输入。我们可以清除时间，但我们认为这可能看起来会出人意料，甚至可能会破坏一些工具，因为它使用Unix或MS-DOS的零时间。相反，我们更改了存储库中的go/VERSION文件，以添加与该版本关联的时间：  

```shell
$ cat go1.21.0/VERSION
go1.21.0
time 2023-08-04T20:14:06Z
$
```  

现在，打包工具在将文件写入存档时会复制VERSION文件中的时间，而不是复制本地文件的修改时间。  

**Cryptographic signing keys（加密签名密钥）**：macOS上的Go工具链除非我们使用获得苹果批准的签名密钥对二进制文件进行签名，否则不会在最终用户系统上运行。我们使用一个内部系统来使用Google的签名密钥对它们进行签名，显然，我们不能分享该秘密密钥以允许其他人复制已签名的二进制文件。相反，我们编写了一个验证器，可以检查两个二进制文件是否相同，除了它们的签名。

**OS-specific packagers（操作系统特定的打包工具）**：我们使用Xcode工具的pkgbuild和productbuild来创建可下载的macOS PKG安装程序，使用WiX来创建可下载的Windows MSI安装程序。我们不希望验证器需要完全相同版本的这些工具，所以我们采用了与加密签名密钥相同的方法，编写了一个验证器，可以查看软件包内部并检查工具链文件是否与预期完全相同。  

## 验证Go工具链

仅一次性使Go工具链可重复是不够的。我们希望确保它们保持可重复性，也希望确保其他人能够轻松地复制它们。

为了保持自己的诚实，我们现在在受信任的Linux/x86-64系统和Windows/x86-64系统上构建所有Go发行版。除了架构之外，这两个系统几乎没有共同之处。这两个系统必须生成位对位相同的存档，否则我们不会继续发布。

为了让其他人验证我们的诚实，我们编写并发布了一个验证器，[golang.org/x/build/cmd/gorebuild](https://pkg.go.dev/golang.org/x/build/cmd/gorebuild)。该程序将从我们的Git存储库中的源代码开始重新构建当前的Go版本，并检查它们是否与在 [go.dev/dl](https://go.dev/dl/) 上发布的存档匹配。大多数存档必须位对位匹配。如上所述，有三个例外情况，其中使用更宽松的检查：

- macOS tar.gz文件预计会有所不同，但然后验证器会比较内部内容。重新构建和发布的副本必须包含相同的文件，并且所有文件必须完全匹配，除了可执行二进制文件。在剥离代码签名后，可执行二进制文件必须完全匹配。
- macOS PKG安装程序不会被重新构建。相反，验证器会读取PKG安装程序内部的文件并检查它们是否与macOS tar.gz完全匹配，同样是在剥离代码签名后。从长远来看，PKG创建足够简单，可以潜在地添加到cmd/distpack，但验证器仍然必须解析PKG文件以运行忽略签名的代码可执行文件比较。
- Windows MSI安装程序不会被重新构建。相反，验证器会调用Linux程序msiextract来提取内部文件，并检查它们是否与重新构建的Windows zip文件完全匹配。从长远来看，可能可以将MSI创建添加到cmd/distpack，然后验证器可以使用位对位的MSI比较。

我们每晚运行gorebuild，并在 [go.dev/rebuild](https://go.dev/rebuild) 上发布结果，当然其他任何人也可以运行它。  

## 验证Ubuntu的Go工具链

Go工具链的易重现构建应该意味着在go.dev上发布的工具链中的二进制文件与其他打包系统中包含的二进制文件相匹配，即使这些打包程序是从源代码构建的。即使打包程序使用了不同的配置或其他更改进行编译，易于重现的构建仍然应该使复制它们的二进制文件变得容易。为了证明这一点，让我们复制Ubuntu的golang-1.21软件包版本1.21.0-1，适用于Linux/x86-64。

首先，我们需要下载并提取Ubuntu软件包，这些软件包是 [ar(1)存档](https://linux.die.net/man/1/ar)，包含zstd压缩的tar存档：  

```shell
$ mkdir deb
$ cd deb
$ curl -LO http://mirrors.kernel.org/ubuntu/pool/main/g/golang-1.21/golang-1.21-src_1.21.0-1_all.deb
$ ar xv golang-1.21-src_1.21.0-1_all.deb
x - debian-binary
x - control.tar.zst
x - data.tar.zst
$ unzstd < data.tar.zst | tar xv
...
x ./usr/share/go-1.21/src/archive/tar/common.go
x ./usr/share/go-1.21/src/archive/tar/example_test.go
x ./usr/share/go-1.21/src/archive/tar/format.go
x ./usr/share/go-1.21/src/archive/tar/fuzz_test.go
...
$
```  

那是源代码存档。现在是amd64二进制存档：  

```shell
$ rm -f debian-binary *.zst
$ curl -LO http://mirrors.kernel.org/ubuntu/pool/main/g/golang-1.21/golang-1.21-go_1.21.0-1_amd64.deb
$ ar xv golang-1.21-src_1.21.0-1_all.deb
x - debian-binary
x - control.tar.zst
x - data.tar.zst
$ unzstd < data.tar.zst | tar xv | grep -v '/$'
...
x ./usr/lib/go-1.21/bin/go
x ./usr/lib/go-1.21/bin/gofmt
x ./usr/lib/go-1.21/go.env
x ./usr/lib/go-1.21/pkg/tool/linux_amd64/addr2line
x ./usr/lib/go-1.21/pkg/tool/linux_amd64/asm
x ./usr/lib/go-1.21/pkg/tool/linux_amd64/buildid
...
$
```  

Ubuntu将普通的Go树拆分成两半，分别位于/usr/share/go-1.21和/usr/lib/go-1.21。让我们将它们重新组合在一起：  

```shell
$ mkdir go-ubuntu
$ cp -R usr/share/go-1.21/* usr/lib/go-1.21/* go-ubuntu
cp: cannot overwrite directory go-ubuntu/api with non-directory usr/lib/go-1.21/api
cp: cannot overwrite directory go-ubuntu/misc with non-directory usr/lib/go-1.21/misc
cp: cannot overwrite directory go-ubuntu/pkg/include with non-directory usr/lib/go-1.21/pkg/include
cp: cannot overwrite directory go-ubuntu/src with non-directory usr/lib/go-1.21/src
cp: cannot overwrite directory go-ubuntu/test with non-directory usr/lib/go-1.21/test
$
```  

这些错误只是复制符号链接时出现的，我们可以忽略它们。

现在我们需要下载并提取上游的Go源代码：  

```shell
$ curl -LO https://go.googlesource.com/go/+archive/refs/tags/go1.21.0.tar.gz
$ mkdir go-clean
$ cd go-clean
$ curl -L https://go.googlesource.com/go/+archive/refs/tags/go1.21.0.tar.gz | tar xzv
...
x src/archive/tar/common.go
x src/archive/tar/example_test.go
x src/archive/tar/format.go
x src/archive/tar/fuzz_test.go
...
$
```  

为了避免一些尝试和错误，结果表明Ubuntu使用 `GO386=softfloat` 构建Go，这会在为32位x86编译时强制使用软浮点，并剥离（从生成的ELF二进制文件中删除符号表）。现在我们从  `GO386=softfloat` 构建开始：  

```shell
$ cd src
$ GOOS=linux GO386=softfloat ./make.bash -distpack
Building Go cmd/dist using /Users/rsc/sdk/go1.17.13. (go1.17.13 darwin/amd64)
Building Go toolchain1 using /Users/rsc/sdk/go1.17.13.
Building Go bootstrap cmd/go (go_bootstrap) using Go toolchain1.
Building Go toolchain2 using go_bootstrap and Go toolchain1.
Building Go toolchain3 using go_bootstrap and Go toolchain2.
Building commands for host, darwin/amd64.
Building packages and commands for target, linux/amd64.
Packaging archives for linux/amd64.
distpack: 818d46ede85682dd go1.21.0.src.tar.gz
distpack: 4fcd8651d084a03d go1.21.0.linux-amd64.tar.gz
distpack: eab8ed80024f444f v0.0.1-go1.21.0.linux-amd64.zip
distpack: 58528cce1848ddf4 v0.0.1-go1.21.0.linux-amd64.mod
distpack: d8da1f27296edea4 v0.0.1-go1.21.0.linux-amd64.info
---
Installed Go for linux/amd64 in /Users/rsc/deb/go-clean
Installed commands in /Users/rsc/deb/go-clean/bin
*** You need to add /Users/rsc/deb/go-clean/bin to your PATH.
$
```  

这将标准包留在了 `pkg/distpack/go1.21.0.linux-amd64.tar.gz` 中。让我们解压它并剥离二进制文件以匹配 Ubuntu ：  

```shell
$ cd ../..
$ tar xzvf go-clean/pkg/distpack/go1.21.0.linux-amd64.tar.gz
x go/CONTRIBUTING.md
x go/LICENSE
x go/PATENTS
x go/README.md
x go/SECURITY.md
x go/VERSION
...
$ elfstrip go/bin/* go/pkg/tool/linux_amd64/*
$
```  

现在我们可以比较我们在 Mac 上创建的 Go 工具链与 Ubuntu 提供的 Go 工具链之间的差异：  

```shell
$ diff -r go go-ubuntu
Only in go: CONTRIBUTING.md
Only in go: LICENSE
Only in go: PATENTS
Only in go: README.md
Only in go: SECURITY.md
Only in go: codereview.cfg
Only in go: doc
Only in go: lib
Binary files go/misc/chrome/gophertool/gopher.png and go-ubuntu/misc/chrome/gophertool/gopher.png differ
Only in go-ubuntu/pkg/tool/linux_amd64: dist
Only in go-ubuntu/pkg/tool/linux_amd64: distpack
Only in go/src: all.rc
Only in go/src: clean.rc
Only in go/src: make.rc
Only in go/src: run.rc
diff -r go/src/syscall/mksyscall.pl go-ubuntu/src/syscall/mksyscall.pl
1c1
< #!/usr/bin/env perl
---
> #! /usr/bin/perl
...
$
```  

我们成功地复制了Ubuntu软件包的可执行文件，并确定了剩下的完整更改集：

- 删除了各种元数据和支持文件。
- 修改了 gopher.png 文件。仔细检查后，这两个文件是相同的，唯一的区别是嵌入的时间戳，Ubuntu 已经更新了它。也许 Ubuntu 的打包脚本使用了重新压缩 png 的工具，即使在不能改善现有压缩的情况下，也会重新写入时间戳。
- 二进制文件 dist 和 distpack 是在引导过程中构建的，但未包含在标准存档中，但包含在 Ubuntu 软件包中。
- Plan 9构建脚本（\*.rc）已被删除，尽管Windows构建脚本（*.bat）仍然存在。
- `mksyscall.pl`和其他七个未显示的Perl脚本的头部已更改。

特别注意的是，我们完全按位重建了工具链二进制文件：它们根本不显示在差异中。也就是说，我们证明了Ubuntu的Go二进制文件与上游Go源代码完全对应。

更好的是，我们证明了这一点，完全不使用任何Ubuntu软件：这些命令在Mac上运行，而unzstd和elfstrip是短小的Go程序。一个复杂的攻击者可能会通过更改软件包创建工具来将恶意代码插入到Ubuntu软件包中。如果他们这样做了，使用这些恶意工具从干净的源代码重新生成Ubuntu软件包仍将生成与恶意软件包完全相同的位对位的副本。这种重新构建方式对于这种类型的重新构建来说是不可见的，就像[Ken Thompson的编译器攻击](https://dl.acm.org/doi/10.1145/358198.358210)一样。不依赖于像主机操作系统、主机体系结构和主机C工具链这样的细节的完美可重复构建是使这种更强的检查成为可能的原因。

（顺便提一下，为了历史记录，Ken Thompson曾告诉我，他的攻击事实上已被检测到，因为编译器构建停止变得可重复。它有一个漏洞：在添加到编译器的后门中的字符串常量被不完全处理，并且每次编译器编译自身时都会增加一个NUL字节。最终，有人注意到了不可重复构建，并尝试通过编译为汇编来找到原因。编译器的后门在汇编输出中根本没有复制自己，因此汇编该输出会删除后门。）  

## 结论

可重复构建是增强开源供应链的重要工具。像[SLSA](https://slsa.dev/)这样的框架关注来源和软件责任链，可以用来指导关于信任的决策。可重复构建通过提供一种验证信任是否恰当的方法来补充这种方法。

完美可重复性（当源文件是构建的唯一相关输入时）仅对能够自行构建的程序来说是可能的，例如编译器工具链。这是一个崇高但值得追求的目标，因为自我托管的编译器工具链在其他情况下很难验证。Go的完美可重复性意味着，假设打包工具没有修改源代码，那么任何形式的Go 1.21.0的重新打包（替换为您喜欢的系统）都应该分发完全相同的二进制文件，即使它们都是从源代码构建的。正如我们在这篇文章中所看到的，对于Ubuntu Linux来说并不完全如此，但完美的可重复性仍然让我们能够使用非常不同的非Ubuntu系统来复制Ubuntu打包。

理想情况下，以二进制形式分发的所有开源软件都应具有易于复制的构建。实际上，正如我们在本文中所看到的，不经意的输入很容易渗入构建过程。对于不需要cgo的Go程序，可重复构建就像使用`CGO_ENABLED=0 go build -trimpath`这样简单。禁用cgo会删除主机C工具链作为相关输入，而`-trimpath`会删除当前目录。如果您的程序需要cgo，您需要在运行`go build`之前为特定的主机C工具链版本做安排，比如在特定的虚拟机或容器镜像中运行构建。

超越Go，[可重复构建](https://reproducible-builds.org/)项目旨在提高所有开源软件的可重复性，是获取有关使您自己的软件构建可重复的更多信息的良好起点。  

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
