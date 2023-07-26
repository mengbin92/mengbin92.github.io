---
layout: post
title: Golang漏洞管理
tags: go
mermaid: false
math: false
---  

原文在[这里](https://go.dev/security/vuln/)

## 概述

Go帮助开发人员检测、评估和解决可能被攻击者利用的错误或弱点。在幕后，Go团队运行一个管道来整理关于漏洞的报告，这些报告存储在Go漏洞数据库中。各种库和工具可以读取和分析这些报告，以了解特定用户项目可能受到的影响。这个功能集成到[pkg.go.dev](https://pkg.go.dev/)和一个新的命令行工具govulncheck中。

这个项目正在进行中，并且正在积极开发中。我们欢迎您的[反馈](https://go.dev/security/vuln/#feedback)，以帮助我们改进！

> 要报告Go项目中的漏洞，请参阅[Go安全政策](https://go.dev/security/policy)。

## 架构

<div align="center">
  <p> <img src="../img/2023-07-26/architecture.drawio.png" alt="Go漏洞管理架构"></p>
  <p>Go漏洞管理架构</p>
</div>


Go中的漏洞管理包括以下高级组件：

- 数据管道从各种来源收集漏洞信息，包括[国家漏洞数据库（NVD）](https://nvd.nist.gov/)、[GitHub咨询数据库](https://github.com/advisories)，以及[直接从Go包维护者](https://go.dev/s/vulndb-report-new)那里获得的信息。
- 使用数据管道的信息填充漏洞数据库。数据库中的所有报告都由Go安全团队进行审查和整理。报告的格式采用[开源漏洞（OSV）格式](https://ossf.github.io/osv-schema/)，并通过[API](https://go.dev/security/vuln/database#api)访问。
- 与[pkg.go.dev](https://pkg.go.dev/)和govulncheck的集成，使开发人员能够在其项目中查找漏洞。[govulncheck命令](https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck)会分析您的代码库，并仅显示真正影响您的漏洞，根据您的代码中哪些函数传递调用了有漏洞的函数。govulncheck为您的项目提供了一种低噪音、可靠的方式来查找已知的漏洞。

## 资源

### Go漏洞数据库

[Go漏洞数据库](https://vuln.go.dev/)包含来自许多现有来源的信息，除此之外还有直接报告给Go安全团队的信息。数据库中的每个条目都经过审查，以确保漏洞的描述、包和符号信息以及版本详细信息的准确性。

有关Go漏洞数据库的更多信息，请参阅[go.dev/security/vuln/database](https://go.dev/security/vuln/database)，以及[pkg.go.dev/vuln](https://pkg.go.dev/vuln)，以在您的浏览器中查看数据库中的漏洞。

我们鼓励包维护者[贡献](https://go.dev/security/vuln/#feedback)有关其自己项目中公共漏洞的信息，并向我们[发送减少阻力的建议](https://golang.org/s/vuln-feedback)。

### Go漏洞检测

Go的漏洞检测旨在为Go用户提供一种低噪音、可靠的方式，以了解可能影响其项目的已知漏洞。漏洞检查集成在Go的工具和服务中，包括一个新的命令行工具[govulncheck](https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck)，[Go包发现网站](https://pkg.go.dev/)以及[带有Go扩展的主要编辑器](https://go.dev/security/vuln/editor)（如VS Code）。

要开始使用govulncheck，请在您的项目中运行以下命令：

```bash
$ go install golang.org/x/vuln/cmd/govulncheck@latest
$ govulncheck ./...
```

要在您的编辑器中启用漏洞检测，请参阅[编辑器集成](https://go.dev/security/vuln/editor)页面中的说明。

### Go CNA

Go安全团队是[CVE编号机构](https://www.cve.org/ProgramOrganization/CNAs)。有关更多信息，请参阅[go.dev/security/vuln/cna](https://go.dev/security/vuln/cna)。

## 反馈

我们希望您能为以下方面做出贡献，帮助我们进行改进：

- 为您维护的Go包的公共漏洞提供[新的](https://golang.org/s/vulndb-report-new)和[更新](https://go.dev/s/vulndb-report-feedback)现有的信息
- [参与这项调查](https://golang.org/s/govulncheck-feedback)，分享您使用govulncheck的经验
- 向我们发送有关问题和功能请求的[反馈](https://golang.org/s/vuln-feedback)

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
