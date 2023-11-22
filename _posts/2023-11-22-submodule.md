---
layout: post
title: git 子模块使用
tags: [git, tools]
mermaid: false
math: false
---  

Git 子模块是 Git 仓库中的另一个 Git 仓库。它允许将一个 Git 仓库作为另一个 Git 仓库的子目录。这对于在多个项目之间共享代码或者将一个大型项目拆分成更小的、可独立管理的部分非常有用。

以下是使用 Git 子模块的一般步骤：

### 1. 添加子模块

```bash
git submodule add <repository-url> <path>
```

- `<repository-url>` 是子模块的 Git 仓库 URL。
- `<path>` 是子模块在父仓库中的存放路径。

### 2. 初始化和更新子模块

刚添加子模块后，需要运行以下命令初始化和更新子模块：

```bash
git submodule update --init --recursive
```

这将克隆子模块并检出它的正确版本。

### 3. 克隆带有子模块的项目

如果你克隆了一个包含子模块的项目，可以使用以下命令来初始化和更新子模块：

```bash
git clone --recursive <repository-url>
```

如果你已经克隆了项目但没有使用 `--recursive`，你可以运行以下命令：

```bash
git submodule update --init --recursive
```

### 4. 在父仓库中查看子模块的状态

```bash
git status
```

这将显示子模块的状态，例如是否有未提交的修改或者是否有新的提交。

### 5. 在子模块中进行更改

进入子模块目录，像普通的 Git 仓库一样进行更改，提交并推送。

### 6. 在父仓库中更新子模块

如果子模块有新的提交，你需要在父仓库中执行以下命令：

```bash
git submodule update --remote
```

这将拉取子模块的最新变更。

### 7. 移除子模块

如果你想移除子模块，首先需要移除子模块的引用，然后删除子模块的相关文件。执行以下步骤：

```bash
# 移除子模块的引用
git submodule deinit -f -- <path-to-submodule>

# 删除子模块的相关文件
rm -rf .git/modules/<path-to-submodule>
rm -rf <path-to-submodule>
```

以上就是使用 Git 子模块的基本步骤。  

在使用子模块时需要小心，因为它的引入增加了项目的复杂性。  

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
