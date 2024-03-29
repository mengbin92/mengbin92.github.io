---
layout: post
title: 覆盖索引
tags: mysql
mermaid: false
math: false
---  

## 1. 什么是覆盖索引？

MySQL覆盖索引（Covering Index）是一种索引类型，它的特点是索引包含了查询所需要的数据，从而避免了对数据的直接查找。通过使用覆盖索引，MySQL可以仅通过索引信息来满足查询条件，而不需要进一步访问数据表，这可以大大提高查询性能。

覆盖索引的概念源于数据库的索引设计。在传统的索引中，索引结构仅包含键值信息，用于快速定位到数据表中的记录。但是，当查询需要访问多个列时，传统的索引无法满足需求，因为它们只包含键值信息，而无法提供其他列的数据。

为了解决这个问题，覆盖索引被引入。覆盖索引不仅包含键值信息，还包含了查询所需要的数据列。这样，当执行查询时，MySQL可以通过覆盖索引直接获取所需的数据，而不需要访问数据表。

## 2. 如何使用覆盖索引？

覆盖索引是一种在查询中使用索引的优化技术，它允许数据库在索引中直接获取查询结果，而无需再次查询数据表。这样可以提高查询性能，减少I/O操作。

要使用覆盖索引，请遵循以下步骤：

1. 确定查询需求：分析查询语句，了解需要查询哪些字段，以及需要执行哪些操作（如排序、分组等）。
2. 创建合适的索引：根据查询需求，创建一个包含所需字段的索引。覆盖索引应该包含查询中涉及的所有字段，以及WHERE子句中使用的过滤条件。例如，如果查询需要字段A、B和C，并且WHERE子句中有一个过滤条件D，那么应该创建一个包含A、B、C和D的索引。
3. 优化查询：在查询中使用覆盖索引。为此，可以在SELECT子句中列出需要的字段，并在WHERE子句中添加过滤条件。确保查询中的字段和索引中的字段保持一致。
4. 监控性能：在使用覆盖索引后，监控查询性能，确保查询速度得到提高。如果性能没有得到提高，可能需要调整索引或查询语句。
5. 定期维护索引：随着数据的变化和查询模式的演化，需要定期检查和优化索引。删除不再需要的索引，确保现有的索引仍然适用于查询需求。

下面以`employees`表为例，包含以下列：`employee_id`、`first_name`、`last_name`、`salary`，现在我们想要查询员工的姓名和薪水，而且我们已经为表创建了一个索引。

首先，创建表并插入一些示例数据：

```sql
CREATE TABLE employees (
  employee_id INT PRIMARY KEY,
  first_name VARCHAR(50),
  last_name VARCHAR(50),
  salary INT
);

INSERT INTO employees VALUES
(1, 'John', 'Doe', 50000),
(2, 'Jane', 'Smith', 60000),
(3, 'Bob', 'Johnson', 75000),
(4, 'Alice', 'Williams', 80000);
```

接下来，我们为表创建一个索引，该索引包含了我们想要查询的列：

```sql
CREATE INDEX idx_covering_index ON employees(first_name, last_name, salary);
```

现在，我们可以使用覆盖索引执行查询：

```sql
-- 使用覆盖索引的查询
mysql> EXPLAIN SELECT first_name, last_name, salary FROM employees WHERE salary > 60000;
+----+-------------+-----------+------------+-------+--------------------+--------------------+---------+------+------+----------+--------------------------+
| id | select_type | table     | partitions | type  | possible_keys      | key                | key_len | ref  | rows | filtered | Extra                    |
+----+-------------+-----------+------------+-------+--------------------+--------------------+---------+------+------+----------+--------------------------+
|  1 | SIMPLE      | employees | NULL       | index | idx_covering_index | idx_covering_index | 411     | NULL |    4 |    33.33 | Using where; Using index |
+----+-------------+-----------+------------+-------+--------------------+--------------------+---------+------+------+----------+--------------------------+
1 row in set, 1 warning (0.00 sec)
```

`EXPLAIN`的结果可能显示 "Using index"，这表示查询成功使用了覆盖索引。

最终的查询可以写成：

```sql
-- 使用覆盖索引的查询
mysql> SELECT first_name, last_name, salary FROM employees WHERE salary > 60000;
+------------+-----------+--------+
| first_name | last_name | salary |
+------------+-----------+--------+
| Alice      | Williams  |  80000 |
| Bob        | Johnson   |  75000 |
+------------+-----------+--------+
2 rows in set (0.00 sec)
```

这样的查询会直接从索引中获取数据，而无需回表查询。这在大型表中可以提高查询性能，因为不需要读取整个行的数据，只需读取覆盖索引包含的列即可。  

## 3. 覆盖索引的优劣

覆盖索引是一种数据库索引技术，通过将查询所需的列包含在索引中，可以避免对数据的直接查找，从而提高查询性能。以下是覆盖索引的详细优势和劣势：

优势：

- **减少磁盘I/O操作**：覆盖索引通过仅读取索引而不是整个数据表来提高性能。这意味着磁盘I/O操作大大减少，因为从磁盘读取数据的次数减少。这有助于提高查询速度并减少等待时间。
- **提高缓存效率**：由于覆盖索引只涉及索引的读取，因此缓存中的数据量减少。这使得缓存更有效地用于存储索引数据，从而提高缓存的利用率。缓存命中率提高，意味着应用程序可以更快地访问数据，因为不需要从磁盘读取数据。
- **减少CPU和内存的使用**：由于覆盖索引减少了数据读取，CPU和内存的使用也相应减少。这意味着数据库服务器可以处理更多的并发请求，因为资源使用更高效。这有助于提高数据库的性能和可伸缩性。
- **提高查询性能**：通过使用覆盖索引，数据库系统可以更快地执行查询。由于索引包含了查询所需的数据，数据库无需访问数据表来获取结果。这避免了额外的磁盘I/O操作和数据检索，从而提高了查询性能。
- **优化查询设计**：覆盖索引有助于优化查询设计。开发人员可以利用覆盖索引来编写更高效的查询，因为它们可以利用索引中的数据而无需访问原始表。这有助于减少查询复杂性和优化查询逻辑。
- **减少网络传输开销**：对于分布式系统或者在网络传输成本较高的场景中，覆盖索引可以减少需要传输的数据量，降低了网络开销。
- **减少锁的竞争**：覆盖索引可以减少对数据表的访问，因此在一些情况下可以减小锁的竞争，提高并发性能。

劣势：

- **增加索引的大小**：覆盖索引包含了更多的列数据，因此相对于非覆盖索引，其大小可能更大。这会增加存储空间的需求，并可能影响索引的维护和管理。
- **增加维护成本**：由于覆盖索引包含了更多的数据列，因此对索引的维护成本可能会增加。当表中的数据发生变化时，覆盖索引可能需要更多的更新操作来保持同步。这可能会对数据库的性能和可伸缩性产生一定的影响。
- **限制了选择性**：虽然覆盖索引在许多情况下可以提高性能，但并不是所有的查询都可以从覆盖索引中受益。对于某些复杂的查询条件或特定的查询类型，非覆盖索引可能更适合。
- **可能影响写入性能**：由于覆盖索引包含了更多的数据列，因此在执行插入、更新或删除操作时，可能需要更频繁地更新索引。这可能会导致写入操作的性能下降，因为需要维护额外的索引数据。
- **局部性原理失效**：覆盖索引可能使得局部性原理失效，因为一个覆盖索引可能包含了多个列，而不是紧密相关的数据块。

综上所述，覆盖索引是一种非常有效的性能优化技术，但也有其劣势。在使用覆盖索引时，需要根据具体的数据库系统和需求进行评估和权衡。通过仔细选择要包含在索引中的列、监控和维护索引以及优化查询设计，可以最大程度地发挥覆盖索引的优势并避免其劣势。

## 4. 其它支持覆盖索引的数据库

覆盖索引的概念是数据库通用的，因此不仅限于MySQL，许多主流的关系型数据库管理系统（RDBMS）都支持覆盖索引。以下是一些常见的数据库系统，它们通常也支持覆盖索引：

1. **PostgreSQL**：PostgreSQL支持索引覆盖扫描，也称为“Covering Index”。当查询的所有列都包含在索引中时，PostgreSQL可以利用索引覆盖扫描来提高性能。
2. **Oracle Database**：Oracle数据库也支持覆盖索引的概念。在Oracle中，覆盖索引是指一个索引包含了查询所需的所有数据，因此可以直接从索引中检索结果，而不需要访问表。
3. **SQL Server**：SQL Server支持包含性索引（Covering Index），这种索引包含了查询所需的所有列。通过使用包含性索引，SQL Server可以减少对数据的访问，从而提高查询性能。
4. **SQLite**：SQLite数据库系统也支持覆盖索引。SQLite的覆盖索引实现类似于其他关系型数据库系统，也是通过将查询所需的所有列包含在索引中来实现的。

需要注意的是，不同的数据库系统可能有自己的实现方式和优化策略，因此具体的覆盖索引支持和效果可能会有所不同。在实际应用中，需要根据具体的数据库系统和需求进行评估和优化。

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
