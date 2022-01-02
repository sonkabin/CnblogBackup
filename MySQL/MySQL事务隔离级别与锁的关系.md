## MySQL事务隔离级别

四个隔离级别：读未提交（READ UNCOMMITTED）、读已提交（READ COMMITTED）、可重复读（REPEATABLE READ）、串行化（SERIALIZABLE）。按照使用频率从高到低介绍

目录：

1. [可重复读](#可重复读)
2. [读已提交](#读已提交)
3. [读未提交](#读未提交)
4. [串行化](#串行化)

## 可重复读

默认隔离级别。

**一致性读**：当第一次读的时候建立快照，后面的SELECT都会使用该快照

**加锁读**：显式加锁的SELECT、UPDATE、DELETE，会使用当前读。锁的情况取决于两种情况：

- 使用唯一索引作为条件，只锁匹配的行

  如果有两个字段上有唯一索引，在一个事务中，更新的时候两个字段在 WHERE 条件中用 OR 连接，那么另一个事务的行为是怎样的？

  ```mysql
  DROP TABLE IF EXISTS t;
  CREATE TABLE t (a INT NOT NULL, b INT, c INT, UNIQUE INDEX (b), UNIQUE index(c)) ENGINE = InnoDB;
  INSERT INTO t VALUES (1,2,3),(2,10,4),(3,20,1);
  
  # Session A
  SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
  BEGIN;
  UPDATE t SET b = b+1 WHERE b = 10 or c = 1;
  # Session B
  SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
  BEGIN;
  UPDATE t SET b = 10 WHERE c = 3; # 阻塞，因为b=10和c=1都锁着
  UPDATE t SET b = 11 WHERE c = 3; # ？情况1
  UPDATE t SET b = 12 WHERE c = 3; # ？情况2
  ```

  情况1会阻塞，情况2不会阻塞。Session A更新b字段后，b=11和b=21也会被锁住。

  虽然是唯一索引，但是某个记录不存在，这种情况会怎样呢？答案是会使用间隙锁

- 其他情况，使用gap lock（间隙锁）或者next-key locks

  - 间隙锁：用于阻止其他事务在间隙中插入数据，同一个gap可以在多个事务中存在。**它加在索引之间**

  - next-key locks：是基于索引的记录锁和间隙锁的组合，会**锁间隙+间隙起点到最近的一点+间隙终点到最近的一点**。可重复读使用它解决幻读。
  
    ```mysql
    DROP TABLE IF EXISTS t;
    # b上有索引
    CREATE TABLE t (a INT NOT NULL, b INT, c INT, INDEX (b)) ENGINE = InnoDB;
    INSERT INTO t VALUES (1,2,3),(2,10,4),(3,20,1);
    
    # Session A
    SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    BEGIN;
    UPDATE t SET b = 8 WHERE b BETWEEN 4 AND 10;
    # Session B
    SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    BEGIN;
  INSERT INTO t(a,b,c) VALUES (1,2,2); # 阻塞
    INSERT INTO t(a,b,c) VALUES (1,10,2); # 阻塞
  INSERT INTO t(a,b,c) VALUES (1,11,2); # 阻塞
    INSERT INTO t(a,b,c) VALUES (1,1,2); # 不阻塞
  INSERT INTO t(a,b,c) VALUES (1,20,2); # 不阻塞
    # 间隙为 (min_val, 2), [2, 10), [10, 20), [20, max_val)，next-key locks锁住[2,20)这段。如果把(3,20,1)这条记录删除，那么b>=2的都不能插入
    ```
    
    此外，需要注意的是，**如果索引失效或者字段没有索引，会升级为表锁，这是间隙锁引起的**。

**可重复读如何解决幻读**：对于一致性读，使用快照解决；对于加锁读，使用next-key locks解决

## 读已提交

**一致性读**：当前读

**加锁读**：只锁匹配的行，不匹配的行会释放掉锁。但是，如果WHERE条件包含索引列，MySQL只会考虑与索引匹配的行，不考虑其他条件。

1. 不匹配的行会释放掉锁

   ```mysql
   DROP TABLE IF EXISTS t;
   # 没有索引的情况
   CREATE TABLE t (a INT NOT NULL, b INT) ENGINE = InnoDB;
   INSERT INTO t VALUES (1,2),(2,3),(3,2),(4,3),(5,2);
   
   # Session A
   SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
   BEGIN;
   UPDATE t SET b = 5 WHERE b = 3;
   # Session B
   SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
   BEGIN;
   UPDATE t SET b = 4 WHERE b = 2; # ？情况1
   ```

   情况1：A锁住了(2,3),(4,3)，释放其他三个，因此B能更新成功。

2. WHERE条件包含索引列

   ```mysql
   DROP TABLE IF EXISTS t;
   # b上有索引
   CREATE TABLE t (a INT NOT NULL, b INT, c INT, INDEX (b)) ENGINE = InnoDB;
   INSERT INTO t VALUES (1,2,3),(2,2,4);
   
   # Session A
   SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
   BEGIN;
   UPDATE t SET b = 3 WHERE b = 2 AND c = 3;
   # Session B
   SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
   BEGIN;
   UPDATE t SET b = 4 WHERE b = 2 AND c = 4; # ？情况2
   ```

   情况2：A只考虑b这个索引，而不管c的具体值

## 读未提交

行为和读已提交相同，但它没有用MVCC，存在脏读（SELECT不加锁）

## 串行化

如果关闭自动提交，所有的SELECT语句会隐式的加上FOR SHARE，因此在事务中使用SELECT会阻塞。一致性读不阻塞的情况只有开启自动提交且不在事务中。

## 参考资料

- MySQL refman-8.0
- [面试官：MySQL是怎么解决幻读问题的？](https://zhuanlan.zhihu.com/p/145822414)

