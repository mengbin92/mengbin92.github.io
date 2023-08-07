---
layout: post
title: Govulncheck v1.0.0 发布了！
tags: go
mermaid: false
math: false
---  

原文在[这里](https://go.dev/blog/govulncheck)

> 原文作者：Julie Qiu, for the Go security team 发布于 13 July 2023

我们很高兴地宣布，govulncheck v1.0.0 已经发布，同时还发布了用于将扫描集成到其他工具中的 API 的 v1.0.0 版本！  

Go对漏洞管理的支持首次在去年九月[宣布](https://go.dev/blog/vuln)。自那以后，我们进行了多次更改，最终在今天发布了最新版本。  

这篇文章介绍了Go更新后的漏洞工具，并说明了如何开始使用它。我们最近还发布了一份[安全最佳实践指南](https://go.dev/security/best-practices)，帮助你在Go项目中优先考虑安全性。  

## Govulncheck

[Govulncheck](https://golang.org/x/vuln/cmd/govulncheck)是一个命令行工具，帮助Go用户在项目依赖中查找已知的漏洞。该工具可以分析代码库和二进制文件，并通过优先考虑实际调用你代码的函数中的漏洞来减少干扰。  

你可以通过[go install](https://pkg.go.dev/cmd/go#hdr-Compile_and_install_packages_and_dependencies)来安装最新版：  

```shell
$ go install golang.org/x/vuln/cmd/govulncheck@latest
```  

然后在你的项目中执行govulncheck：  

```shell
$ govulncheck ./...
```  

请查看[govulncheck](https://go.dev/doc/tutorial/govulncheck)教程，以获取有关如何开始使用该工具的其他信息。  

在v1.0.0版本中，现在有一个稳定的API可用，该API的说明位于[golang.org/x/vuln/scan](https://golang.org/x/vuln/scan)。该API提供了与govulncheck命令相同的功能，使开发人员能够将安全扫描器和其他工具与govulncheck集成。例如，可以查看与[govulncheck集成的osv-scanner示例](https://github.com/google/osv-scanner/blob/d93d6b73e90ae392fe2b1b64a33bda6976b65b2d/internal/sourceanalysis/go.go#L20)。  

## 数据库  

Govulncheck由Go漏洞数据库[https://vuln.go.dev](https://vuln.go.dev/)提供支持，该数据库提供了关于公共Go模块中已知漏洞的详尽信息。你可以在[pkg.go.dev/vuln](https://pkg.go.dev/vuln)上浏览数据库中的条目。  

自初始发布以来，我们已更新了[数据库API](https://go.dev/security/vuln/database#api)以提高性能并确保长期的可扩展性。提供了一个实验性工具来生成你自己的漏洞数据库索引，位于[golang.org/x/vulndb/cmd/indexdb](https://golang.org/x/vulndb/cmd/indexdb)。

如果你是Go包维护者，我们鼓励你[贡献关于你项目中公开漏洞的信息](https://go.dev/s/vulndb-report-new)。

有关Go漏洞数据库的更多信息，请参见[go.dev/security/vuln/database](https://go.dev/security/vuln/database)。  

## 集成

漏洞检测现已集成到许多Go开发人员常用的工具套件中。

可以在 pkg.go.dev/vuln 上浏览来自Go漏洞数据库的数据。漏洞信息还会在[pkg.go.dev](https://pkg.go.dev/vuln)的搜索和包页面中显示。例如，[golang.org/x/text/language](https://pkg.go.dev/golang.org/x/text/language?tab=versions)的版本页面会显示该模块旧版本中的漏洞。

你还可以使用Visual Studio Code的Go扩展直接在编辑器中运行 govulncheck。详细操作请参见[教程](https://go.dev/doc/tutorial/govulncheck-ide)。

最后，我们知道许多开发人员希望将 govulncheck 作为CI/CD系统的一部分运行。作为起点，我们为 govulncheck 提供了一个[GitHub Action](https://github.com/marketplace/actions/golang-govulncheck-action)，以便与你的项目集成使用。  

## 视频演示

如果你对上述集成感兴趣，今年我们在Google I/O大会上展示了这些工具的演示，我们在演讲中介绍了[如何使用Go和Google构建更安全的应用程序](https://www.youtube.com/watch?v=HSt6FhsPT8c&ab_channel=TheGoProgrammingLanguage)。  

## 反馈

我们一如既往地欢迎你的反馈！请查看有关[如何贡献和帮助我们进行改进的详细信息](https://go.dev/security/vuln/#feedback)。

我们希望你会发现Go对漏洞管理的最新支持对你有用，并与我们一起建立更安全可靠的Go生态系统。  

---

<div align="center">
  <img src="../img/qrcode_wechat.jpg" alt="孟斯特">
</div>

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。  
> author: [mengbin](mengbin1992@outlook.com)  
> blog: [mengbin](https://mengbin.top)  
> github: [mengbin92](https://mengbin92.github.io/)  
> cnblogs: [恋水无意](https://www.cnblogs.com/lianshuiwuyi/)  

---
