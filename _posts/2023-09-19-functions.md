---
layout: post
title: MySQL 常用内置函数
tags: mysql 
mermaid: false
math: false
---  

MySQL 提供了丰富的内置函数，用于在 SQL 查询中执行各种操作，包括数学运算、字符串处理、日期和时间操作等。以下是 MySQL 中一些常用的内置函数的详细介绍：

## 1. 数学函数

- `ABS(x)`：返回一个数的绝对值。
- `CEIL(x)` 或 `CEILING(x)`：返回不小于 x 的最小整数。
- `FLOOR(x)`：返回不大于 x 的最大整数。
- `ROUND(x, d)`：将 x 四舍五入为指定的小数位数 d。
- `SQRT(x)`：返回 x 的平方根。
- `POWER(x, y)` 或 `POW(x, y)`：返回 x 的 y 次幂。

## 2. 字符串函数

- `CONCAT(str1, str2, ...)`：将多个字符串连接在一起。
- `LENGTH(str)` 或 `CHAR_LENGTH(str)`：返回字符串的字符数。
- `UPPER(str)`：将字符串转换为大写。
- `LOWER(str)`：将字符串转换为小写。
- `SUBSTRING(str, start, length)` 或 `SUBSTR(str, start, length)`：从字符串中提取子字符串。
- `TRIM([LEADING | TRAILING | BOTH] trim_string FROM str)`：删除字符串开头或结尾的指定字符。
- `REPLACE(str, search, replace)`：替换字符串中的子字符串。

## 3. 日期和时间函数

- `NOW()` 或 `CURRENT_TIMESTAMP()`：返回当前日期和时间。
- `CURDATE()`：返回当前日期。
- `CURTIME()`：返回当前时间。
- `DATE_ADD(date, INTERVAL expr unit)`：将一个时间值加上指定的时间间隔。
- `DATE_SUB(date, INTERVAL expr unit)`：从一个时间值减去指定的时间间隔。
- `DATEDIFF(date1, date2)`：计算两个日期之间的天数差。
- `DATE_FORMAT(date, format)`：将日期格式化为指定的格式。

## 4. 聚合函数

- `COUNT(expr)`：计算行数或非 NULL 值的数量。
- `SUM(expr)`：计算表达式的总和。
- `AVG(expr)`：计算表达式的平均值。
- `MIN(expr)`：找到表达式的最小值。
- `MAX(expr)`：找到表达式的最大值。

## 5. 条件函数

- `IF(expr, true_val, false_val)`：如果表达式为真，则返回 true_val；否则返回 false_val。
- `CASE`：用于在查询中执行条件逻辑。

这些是 MySQL 中一些常用的内置函数。MySQL 还提供了许多其他函数，包括数据类型转换函数、加密函数、数据处理函数等。你可以根据具体的需求在查询中使用这些函数来执行各种操作。要了解更多详细信息，可以查阅 MySQL [官方文档](https://dev.mysql.com/doc/refman/8.0/en/functions.html)。

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
