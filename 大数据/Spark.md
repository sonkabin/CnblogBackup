## Spark Core

### 三大数据结构

- RDD：弹性分布式数据集
- 累加器：分布式共享只写变量
- 广播变量：分布式共享只读变量

### RDD

RDD是最小计算单元。RDD使用装饰器模式，比如对于WordCount的实现步骤如下：

1. 从文件中获得数据得到`HadoopRDD`
2. `flatMap`操作，传入`HadoopRDD`并得到`MapPartitionsRDD`
3. `map`操作，传入`MapPartitionsRDD`并得到`MapPartitionsRDD`
4. `reduceByKey`操作，传入`MapPartitionsRDD`并得到`ShuffledRDD`
5. `collect`操作，真正执行任务

RDD代表一个弹性的、不可变、可分区、里面元素可并行计算的集合。弹性是指存储的弹性（内存与磁盘的自动切换）、容错的弹性（数据丢失可自动恢复）、计算的弹性（计算出错重试机制）、分片的弹性（可根据需要重新分片）。

#### RDD的五个重要配置

- 分区列表：用于执行任务时并行计算。`def getPartitions`
- 分区计算函数：使用分区计算函数对每个分区进行计算，计算函数是一样的。`def compute`
- RDD之间的依赖关系：当需求中需要将多个计算模型进行组合时，就需要将多个RDD建立依赖关系。`def getDependencies`
- 分区器（可选）：指定分区规则。`val partitioner`
- 首选位置：判断将任务发送给哪个节点效率最高。`def getPreferredLocations`

#### RDD执行原理

Driver端将处理逻辑分为一个个的计算任务，放到taskpool中；调度节点将任务根据计算节点的状态发送到对应的计算节点上进行计算。

#### RDD分区数据分配

- 对于从内存（集合）中读取数据，makeRDD方法有一个参数表示分区数量，可以从这入手理解分区数是如何确定的；分区中数据如何划分，可以看ParallelCollectionRDD.getPartitions方法，它会尽可能让分区中数据量相同。

  ```scala
  // 核心划分分区数据代码
  def positions(length: Long, numSlices: Int): Iterator[(Int, Int)] = {
      (0 until numSlices).iterator.map { i =>
          val start = ((i * length) / numSlices).toInt
          val end = (((i + 1) * length) / numSlices).toInt
          (start, end)
      }
  }
  sc.makeRDD(List(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11), 4)
  /* 
  长度11，分区数4，则每组为(0, 2), (2, 5), (5, 8), (8, 11)，左闭右开
  */
  ```

- 对于从文件中获得的数据集，使用Hadoop读取文件的方式，因此分区数据的分配与Hadoop的规则有关。首先有最小分区数，它是CPU核数和设置的默认值的最小值。读出来之后写文件，分区数可能发生变化。`HadoopRDD.getPartitions`，统计读取数据的字节总数，然后除以分区数，得到每个分区的字节数，对于每个文件是否产生新的分区取决于Hadoop的1.1规则，即该文件的总字节数的余数如果大于每个分区字节数的10%，则产生新分区。

  ```java
  for (FileStatus file: files) {
      totalSize += file.getLen(); // 读取所有文件的字节总数（包括不可见字符）
  }
  long goalSize = totalSize / (numSplits == 0 ? 1 : numSplits); // 除以分区数得到每个分区的字节数
  long splitSize = computeSplitSize(goalSize, minSize, blockSize); // Math.max(minSize, Math.min(goalSize, blockSize)); 分区字节数修正
  
  // 每个文件确定是否产生新分区，SPLIT_SLOP=1.1
  while (((double) bytesRemaining)/splitSize > SPLIT_SLOP) {
      String[][] splitHosts = getSplitHostsAndCachedHosts(blkLocations,
                                                          length-bytesRemaining, splitSize, clusterMap);
      splits.add(makeSplit(path, length-bytesRemaining, splitSize,
                           splitHosts[0], splitHosts[1]));
      bytesRemaining -= splitSize;
  }
  ```

  Spark读取文件，采用的是Hadoop的方式，按行读取，与字节数无关。数据读取时以偏移量为单位，偏移量计算规则为每个分区的字节数，且左闭右闭，不会重复读取。

  ```scala
  // 在同一个文件中，7个字节，2个分区，则每个分区3个字节，剩余1个字节
  1CRLF
  2CRLF
  3
  // 偏移量范围计算
  /*
  0 => [0, 3]，分区数据为【1 2】，包括回车和换行
  1 => [3, 6]，分区数据为【3】
  2 => [6, 7]，无数据
  */
  ```

  测试方法：

  ```scala
  // 3个数据文件
  /*
  a.txt：
  a
  d
  b.txt：
  cdef
  c.txt：
  fbg
  */
  // 产生5个分区，因为a.txt和b.txt是4个字节，c.txt是3个字节，那么每个分区的字节数为3
  val sparkConf: SparkConf = new SparkConf().setMaster("local[3]").setAppName("RDD")
  val sc = new SparkContext(sparkConf)
  val rdd: RDD[String] = sc.textFile("input", 3)
  rdd.saveAsTextFile("output")
  sc.stop()
  ```

**在Spark中，shuffle操作的数据必须落盘处理，不能在内存中等待，否则可能导致内存溢出**。落盘处理时，一个task要写临时文件，SortShuffleWriter会写一个索引文件和一个数据文件，这样可以提高shuffle性能。因为如果数据小文件太多，会影响到性能。另外可能存在溢写（Spillable.maybeSpill），为防止内存被爆掉，设置了溢写阈值（5M）和溢写数据量，只要其中一个超过了设定值，就会溢写临时文件，后续再合并这些临时文件即可。

不属于RDD的方法操作都是在Driver端执行的，而属于RDD的算子逻辑是在Executor端执行的。

#### 分区和并行度

并行度：有多少个task可以同时运行。core×instances即并行度，core是executor的虚拟核（可认为是线程），会抢占CPU资源；instances是实例数，可认为是进程数。

分区和并行度之间的关系：分区可以对应到一个task，如果资源足够，那么这些task可以并行，即分区等于并行度；如果资源不够，那么分区会多于并行度。（在可视化界面上看类似于120/200(20running)，即完成了120个分区，总共200个分区，并行度20）

一个stage的task数量是该stage的最后一个RDD的分区数，总task数就是每个stage的task之和。

#### 转换算子之单值类型

- `map`：对数据进行转换和改变。任务执行方式为，分好区后，一个区有多个数据要处理，先发送一个数据到计算节点，待该数据的所有计算逻辑执行完成后，再发送下一个数据。因此性能比较差。

- `mapPartitions`：其需要传递一个迭代器，返回一个迭代器，没有要求数据个数保持不变，功能比`map`更丰富。其会将整个分区的数据一次性发送到计算节点上，计算节点以迭代器的方式进行处理，也就是说对数据进行了缓存，只有当整个分区的全部数据处理完之后才会释放缓存，如果内存比较小的话则容易出现内存溢出。不过一般都会设计成发送计算吧。

- `mapPartitionsWithIndex`：带分区索引的`mapPartitions`，索引能标识分区号。

- `flatMap`：作用和Scala的`flatMap`提供的作用类似

- `glom`：将同一个分区的所有数据直接转换为相同类型的内存数组进行处理，分区的数量和数据所在的分区不发生改变，只是数据类型变成了Array

- `groupBy`：作用和Scala的`groupBy`提供的作用类似，其会重新组合数据，也就是shuffle

- `filter`：作用和Scala的`filter`提供的作用类似，数据筛选过滤后，分区数量不变，但是分区内的数据可能不均衡，可能导致数据倾斜。

- `sample`：根据指定规则从数据集中抽取数据，有三个参数。可用于判断shuffle之后是否发生了数据倾斜。

  - `withReplacement`：表示是否抽取完之后将数据放回，如果放回，则结果集中可能有重复的数据
  - `fraction`：如果抽取后不放回，则该参数表示数据集中每条数据被抽取的概率；如果抽取后放回，则该参数表示每条数据被抽取的可能次数
  - `seed`：抽取数据的随机数种子

- `distinct`：去重

- `coalesce`：根据数据量缩减分区，用于大数据集过滤后，提高小数据集的执行效率。默认情况下不shuffle，仅是将部分分区的数据放在其他分区后面，这可能会导致数据倾斜。可以提供参数让其shuffle，coalesce算子要扩大分区必须要shuffle。

- `repartition`：调整分区，其调用`coalesce`算子

  ```scala
  def repartition(numPartitions: Int)(implicit ord: Ordering[T] = null): RDD[T] = withScope {
      coalesce(numPartitions, shuffle = true)
  }
  ```

- `sortBy`：排序，默认情况下不会改变分区数量，但会shuffle，分区数据会改变

#### 转换算子之双值类型

- `intersection/union/subtract/zip`：交集、并集、差集、拉链，要求两个数据集的数据类型一致，且两个数据源的分区数量要保持一致

#### 转换算子之Key-Value类型

由PairRDDFunctions提供，其会将RDD隐式转换为自身。

```scala
implicit def rddToPairRDDFunctions[K, V](rdd: RDD[(K, V)])
(implicit kt: ClassTag[K], vt: ClassTag[V], ord: Ordering[K] = null): PairRDDFunctions[K, V] = {
    new PairRDDFunctions(rdd)
}
```

- `partitionBy`：根据指定的分区规则对数据集重新分区，如哈希

- `reduceByKey`：相同的key分在一个组中，对value做reduce。有shuffle操作

- `groupByKey`：相同key的数据分在一个组中，value放在集合中。有shuffle操作

  `groupByKey`和`reduceByKey`的区别：从shuffle的角度，`reduceByKey`在将数据落盘之前，会在分区内预处理，也就是将在同一分区内的key进行聚合，因此落盘的数据量会比`groupByKey`少，性能也就更高；从功能的角度，`reduceByKey`将分组和聚合作为一个不可分割的功能，而`groupByKey`只能分组

- `aggregateByKey`：使用了柯里化，有两个参数列表

  - 第一个参数列表：传递一个初始值，在分区内计算时用于初始时的比较
  - 第二个参数列表：第一个参数表示分区内计算规则，第二个参数表示分区间计算规则

  如果分区内计算规则和分区间计算规则相同，可以使用`foldByKey`

  ```scala
  // 获取相同key的数据的平均值 => ("a", 3), ("b", 4)
  // 初始值为(和，个数)
  rdd.aggregateByKey((0, 0))(
      (tuple, value) => (tuple._1 + value, tuple._2 + 1),
      (tuple1, tuple2) => (tuple1._1 + tuple2._1, tuple1._2 + tuple2._2)
  )
  // .map(tuple => (tuple._1, tuple._2._1 / tuple._2._2))
  // 直接处理值用法
  // .mapValues(tuple => tuple._1 / tuple._2)
  // 偏函数用法
  .mapValues{
      case (sum, cnt) => sum / cnt
  }
  .collect().foreach(println)
  ```

  

- `combineByKey`：将相同key的第一个数据进行结构转换作为初始值，其他操作和`aggregateByKey`相同，由于要进行结构转换，分区内计算规则和分区间计算规则的参数需要明确写上，因为编译器无法自动推断

  `reduceByKey/aggregateByKey/foldByKey/combineByKey`底层都使用`combineByKeyWithClassTag`，所以它们都有分区内和分区间计算规则，以及对初始值的处理

- `join`：类似SQL的内连接。将两个数据集的数据，相同key的value会连接在一起，形成元组。如果两个数据集中有多个相同的key，会依次匹配出现笛卡尔积，导致结果数据集快速增加

  ```scala
  // makeRDD方法和parallelize是相同的，只是名称上makeRDD更容易理解
  val rdd1: RDD[(String, Int)] = sc.makeRDD(List(("a", 2), ("b", 3), ("a", 1)))
  val rdd2: RDD[(String, Int)] = sc.makeRDD(List(("a", 6), ("b", 4), ("c", 5)))
  /*
  (a,(2,6))
  (a,(1,6))
  (b,(3,4))
  */
  rdd1.join(rdd2).collect().foreach(println)
  ```

- `leftOuterJoin/rightOuterJoin`：类似SQL的左外连接和右外连接

- `cogroup`：先分组再连接

#### 行动算子（触发任务的真正执行）：

- `reduce`：作用和Scala的`reduce`提供的作用类似
- `collect`：将不同分区的数据按照分区顺序采集到Driver端的内存中
- `count`：统计数据集中数据的个数
- `first`：获取数据集中第一个数据
- `take`：作用和Scala的`take`提供的作用类似
- `takeOrdered`：对数据集排序后取n个数据
- `aggregate`：初始值和分区内的数据进行聚合，再将初始值和分区间的数据聚合。`aggregateByKey`的初始值只参与分区内数据的计算
- `fold`：分区内计算规则和分区间计算规则相同（`aggregate`的特殊情况）
- `countByKey/countByValue`：统计每种key/value的出现次数
- `foreach`：在Executor端执行，不保证顺序
- `foreachPartition`：在Executor端执行，将一个算子应用于同一个分区中

#### RDD序列化

RDD算子外的操作在Driver端进行，如new一个对象，如果在RDD中操作该对象，则需要让它序列化；可以利用样例类，其在编译时会混入序列化特质。

闭包检查：RDD算子需要在Executor端执行，其可能需要用到Driver端传过来的数据，如果数据无法序列化则Executor就无法执行。因此RDD在执行计算任务之前，会检查闭包内的对象是否可以序列化。

Kryo序列化可以绕过Java的`transient`关键字的限制。

#### RDD依赖关系

多个连续的RDD的依赖关系，称为血缘关系。每个RDD会保存血缘关系（血缘关系保存的是操作），为了提高容错性。通过`rdd.toDebugString`查看血缘关系。

RDD的依赖关系可通过`rdd.dependencies`查看，包括两种类型：1）OneToOne依赖（窄依赖），即新的RDD的一个分区依赖旧的RDD的一个分区，尽管多个窄依赖有多个分区，它们的多个计算逻辑放在同一个task中运行；2）Shuffle依赖（宽依赖），即新的RDD的一个分区依赖旧的RDD的多个分区，需要分stage执行（也就是需要等待前一阶段的分区内的任务完成才能进行下一阶段），**宽依赖产生新的stage**。

源码可以从行动算子（一个Action算子产生一个jobId）点进去，找runJob，最终能找到DAGScheduler的createResultStage方法，然后就可以愉快地看源码了～

#### RDD持久化

RDD算子的结果可以缓存或存储，可供后续的重复使用，而无需再重新执行一遍；另一个作用是当流程太长时为了防止出现错误导致重新开始，通过缓存提高性能。

- `cache`：数据临时存储在内存中，调用`persist`的只缓存内存策略。**会在血缘关系中添加新的依赖**，可能存在内存溢出问题。
- `persist`：数据临时存储在内存或磁盘临时文件中，在运行完成后缓存文件会自动删除。涉及到磁盘IO，性能较低，但数据安全。**会在血缘关系中添加新的依赖**
- `checkpoint`：数据长久存储在磁盘文件中，需要指定分布式存储路径，在运行完成后文件不会自动删除。涉及到磁盘IO，性能较低，但数据安全。此外，为了保证数据安全，一般情况下其会独立执行作业，也就是说再执行一遍作业，因此性能更低，和`cache`一起使用可以改善checkpoint的性能。**执行过程中会切断并重建血缘关系**，因为数据集长久存储了（相当于创建了新的数据集，所以可以重建血缘关系）

### 累加器

累加器的作用：在Driver端定义的变量，在Executor端的每个Task都会得到变量的一个副本，每个Task更新完副本后，将其传回到Driver进行merge。

Spark提供了简单的累加器，如`longAccumulator/doubleAccumulator/collectionAccumulator`。

累加器是分布式共享只写变量，一般会放在行动算子中。

```scala
// 使用累加器实现WordCount，由于之前实现的WordCount的reduceByKey会有Shuffle操作，数据量大会影响性能，通过累加器可免去Shuffle操作
def main(args: Array[String]): Unit = {
    val sparkConf: SparkConf = new SparkConf().setMaster("local[4]").setAppName("RDD")
    val sc = new SparkContext(sparkConf)

    val rdd: RDD[String] = sc.makeRDD(List("Hello Spark", "Hello Scala"))
    // 创建累加器
    val wcAcc = new MyAccumulator
    // 注册累加器
    sc.register(wcAcc, "WordCount")

    rdd.flatMap(word => word.split(" ")).foreach(
        word => {
            // 利用累加器实现数据的累加
            wcAcc.add(word)
        }
    )
    // 获得累加器结果
    println(wcAcc.value)

    sc.stop()
}
// 自定义累加器
class MyAccumulator extends AccumulatorV2[String, mutable.Map[String, Long]]{
    private val wcMap = mutable.Map[String, Long]()

    // 判断是否是初始状态
    override def isZero: Boolean = wcMap.isEmpty

    override def copy(): AccumulatorV2[String, mutable.Map[String, Long]] = new MyAccumulator

    override def reset(): Unit = wcMap.clear()

    override def add(word: String): Unit = wcMap.put(word, wcMap.getOrElse(word, 0L) + 1)

    // 在Driver端合并多个累加器
    override def merge(other: AccumulatorV2[String, mutable.Map[String, Long]]): Unit = {
        other.value.foreach{
            case (word, count) => wcMap.put(word, wcMap.getOrElse(word, 0L) + count)
        }
    }

    override def value: mutable.Map[String, Long] = wcMap

}
```

### 广播变量

广播变量的作用：将闭包数据保存在Executor的内存中，在同一个Executor中的每个Task共享这个闭包数据，从而无需每个任务自身保存闭包数据，减少了重复数据和占用内存的问题。

广播变量是分布式共享只读变量，不可以修改。

```scala
def main(args: Array[String]): Unit = {
    val sparkConf: SparkConf = new SparkConf().setMaster("local[4]").setAppName("RDD")
    val sc = new SparkContext(sparkConf)

    val rdd = sc.makeRDD(List(("a", 1), ("b", 3), ("c", 2)))
    val map = mutable.Map(("a", 4), ("b", 2), ("c", 5))
    val bc = sc.broadcast(map)

    // join会导致数据集快速增长，并且影响shuffle的性能，不推荐使用，因此用map来改进
    rdd.map{
        case (word, count) => {
            val c = bc.value.getOrElse(word, 0)
            (word, (count, c))
        }
    }.foreach(println)

    sc.stop()
}
```

## Spark SQL

### 介绍

Spark SQL用于简化RDD的开发，提高开发效率。

特点：1）整合SQL和Spark编程；2）统一数据访问，即相同的方式连接不同的数据源；3）兼容Hive；4）标准的数据库连接，包括JDBC和ODBC。

数据结构：

- DataFrame：提供元数据，可以知道详细的结构信息，包括数据集中有哪些列，每列的名称和类型是什么，类似于SQL表格。
- DataSet：是DataFrame的扩展，结果处理更方便，功能更强大（强类型，lambda函数）。

### DataFrame

创建DataFrame的方式：1）通过Spark数据源进行创建，如`spark.read.json(文件路径)`，其中`spark`是`SparkSession`对象；2）从一个存在的RDD进行转换，如`rdd.toDF(列名1, 列名2)`；3）从Hive Table进行查询返回。

使用方式：

- SQL形式

  ```scala
  def main(args: Array[String]): Unit = {
      // 创建Spark SQL运行环境
      val sparkConf: SparkConf = new SparkConf().setMaster("local[4]").setAppName("SQL")
      val spark: SparkSession = SparkSession.builder().config(sparkConf).getOrCreate()
      
      // 操作
      val df = spark.read.json("data/user.json")
      df.show
      df.createOrReplaceTempView("user")
      spark.sql("select * from user").show
      
      // 关闭连接
      spark.close()
  }
  ```

- DSL形式

  ```scala
  def main(args: Array[String]): Unit = {
      val sparkConf: SparkConf = new SparkConf().setMaster("local[4]").setAppName("SQL")
      val spark: SparkSession = SparkSession.builder().config(sparkConf).getOrCreate()
      // 使用DataFrame时，如果涉及到转换规则，需要引入转换规则
      import spark.implicits._
      
      val df = spark.read.json("data/user.json")
      df.select("age").show
      df.select($"name", $"age" + 1).show // 所有人年龄加1
      df.select($"age" + 1).show // 年龄加1
      df.select('age + 1).show // $""与'等价
      df.filter('age > 21).show() // 过滤
      df.groupBy("age").count().show() // 根据age分组并统计数量
      
      spark.close()
  }
  ```

DataFrame的默认生命周期是Session范围内的，如果想应用范围内有效，可以使用全局临时表。

```scala
df.createGlobalTempView("user") // 创建全局临时表
spark.sql("SELECT * FROM global_temp.user").show() // 使用时需要全路径使用
```

### DataSet

DataSet是强类型的数据集合，需要提供对应的类型信息。序列化和反序列化需要具体的`Encoder`，而不是Java或Kyro的序列化方式，因为其可以在DataSet上动态地添加操作（如filter、map等）而无需反序列化。Scala会通过隐式转换提供`Encoder`，而[Java需要创建它](https://spark.apache.org/docs/latest/sql-getting-started.html#creating-datasets)。

创建DataSet的方式：1）从DataFrame转换，如`df.as[样例类]`；2）从一个存在的RDD进行转换，Spark提供两种方式进行转换：

- 使用反射推断模式。`val ds = userRDD.map(attr => User(attr(0), attr(1).toInt)).toDS`
- [手动指定模式](https://spark.apache.org/docs/latest/sql-getting-started.html#programmatically-specifying-the-schema)。虽然这种方法比较繁琐，但它允许我们能对那些在运行过程中才能知道列类型的DataSet进行模式指定。

### RDD、DataFrame、DataSet的关系

相同点：

- 都是分布式弹性数据集
- 都具有惰性机制
- 有许多相同的函数，如`filter`
- 都有分区概念

区别：

- DataFrame和DataSet可使用模式匹配获取各个字段的值和类型
- RDD一般和Spark MLib一起使用，不支持Spark SQL操作。转成DataFrame使用`rdd.toDF(列名1, 列名2)`，转成DataSet使用`rdd.toDS`（最好rdd是使用了样例类的，否则即使转换过去使用起来也并不方便）
- DataFrame每一行的类型为Row，每一列的值不能直接访问，一般不与Spark MLib一起使用，支持Spark SQL操作，多样的保存方式（如`csv`）。转成RDD使用`df.rdd`，转成DataSet使用`df.as[样例类]`
- DataSet是DataFrame的扩展，区别在于每一行的数据类型是强类型，而不是Row。转成RDD使用`df.rdd`，转成DataFrame使用ds.toDF

### 用户自定义函数（User-Defined Functions）

用户自定义标量函数（UDFs）：实现原理是缓冲区，在缓冲区中对每一行数据进行处理。每一行返回单值。

```scala
// 通过用户自定义函数，为查询的名字结果加上前缀
spark.udf.register("prefix", (name: String) => "Name: " + name)
spark.sql("select prefix(username), age from user").show
```



用户自定义聚合函数（User-Defined Aggregate Functions，UDAF）：多行返回单值。

- DataFrame

  ```scala
  def main(args: Array[String]): Unit = {
      val sparkConf: SparkConf = new SparkConf().setMaster("local[4]").setAppName("SQL")
      val spark: SparkSession = SparkSession.builder().config(sparkConf).getOrCreate()
      import spark.implicits._
  
      val df = spark.read.json("data/user.json")
      df.createOrReplaceTempView("user")
  
      spark.udf.register("ageAvg", functions.udaf(new MyAvgUDF))
      spark.udf.register("oldAgeAvg", new MyOldAvgUDF)
      spark.sql("select ageAvg(age) from user").show
      spark.sql("select oldAgeAvg(age) from user").show
  
      spark.close()
  }
  
  /*
  自定义聚合函数类：计算年龄的平均值
  1. 继承org.apache.spark.sql.expressions.Aggregator，定义泛型
  	IN：输入数据类型
  	BUF：缓冲区类型
  	OUT：输出数据类型
  2. 重写方法
  */
  case class Buf(var total: Long, var count: Long)
  // Spark3.0.0之后，UserDefinedAggregateFunction被标记为过时，因为它是弱类型的方式。但是，其实之前也可以使用强类型的方式实现UDAF，方式和下面的几乎一样，不过，早期在SQL中是不支持强类型UDAF操作的，可以在DSL中使用，如下面的DataSet的使用
  class MyAvgUDF extends Aggregator[Long, Buf, Long]{
      // 缓冲区的初始化
      override def zero: Buf = Buf(0L, 0L)
  
      // 根据输入的数据更新缓冲区
      override def reduce(buf: Buf, in: Long): Buf = {
          buf.total += in
          buf.count += 1
          buf
      }
  
      // 合并缓冲区
      override def merge(b1: Buf, b2: Buf): Buf = {
          b1.total += b2.total
          b1.count += b2.count
          b1
      }
  
      // 计算结果
      override def finish(reduction: Buf): Long = reduction.total / reduction.count
  
      // 缓冲区的编码操作。自定义类使用Encoders.product
      override def bufferEncoder: Encoder[Buf] = Encoders.product
  
      // 输出的编码操作
      override def outputEncoder: Encoder[Long] = Encoders.scalaLong
  }
  // Spark3.0.0之前使用UserDefinedAggregateFunction
  class MyOldAvgUDF extends UserDefinedAggregateFunction{
      override def inputSchema: StructType = {
          StructType(
              Array(
                  StructField("age", LongType)
              )
          )
      }
  
      override def bufferSchema: StructType = {
          StructType(
              Array(
                  StructField("total", LongType),
                  StructField("count", LongType)
              )
          )
      }
  
      override def dataType: DataType = LongType
  
      // 函数的稳定性，传入的相同的参数结果是否相同
      override def deterministic: Boolean = true
  
      override def initialize(buffer: MutableAggregationBuffer): Unit = {
          buffer(0) = 0L
          buffer(1) = 0L
          // 可以替换为update方法，如 buffer.update(0, 0L)
      }
  
      // 缓冲区更新
      override def update(buffer: MutableAggregationBuffer, input: Row): Unit = {
          buffer.update(0, buffer.getLong(0) + input.getLong(0))
          buffer.update(1, buffer.getLong(1) + 1)
      }
  
      // 缓冲区数据合并，因为是分布式计算，会有多个缓冲区结果
      override def merge(buffer1: MutableAggregationBuffer, buffer2: Row): Unit = {
          buffer1.update(0, buffer1.getLong(0) + buffer2.getLong(0))
          buffer1.update(1, buffer1.getLong(1) + buffer2.getLong(1))
      }
  
      // 计算最终的结果
      override def evaluate(buffer: Row): Any = {
          buffer.getLong(0) / buffer.getLong(1)
      }
  }
  ```

- DataSet（早期在SQL中是不支持强类型UDAF操作的，可以在DSL中使用）

  ```scala
  def main(args: Array[String]): Unit = {
      val sparkConf: SparkConf = new SparkConf().setMaster("local[4]").setAppName("SQL")
      val spark: SparkSession = SparkSession.builder().config(sparkConf).getOrCreate()
      import spark.implicits._
  
      val df = spark.read.json("data/user.json")
  	// 使用DataSet
      val ds = df.as[User]
      // 将UDAF函数转换为查询的列对象
      val udafCol: TypedColumn[User, Long] = new MyAvgUDAF().toColumn
      ds.select(udafCol).show
  
      spark.close()
  }
  // 定义用例类User
  case class User(username: String, age: Long)
  case class Buf(var total: Long, var count: Long)
  // Long改为User
  class MyAvgUDAF extends Aggregator[User, Buf, Long]{
      override def zero: Buf = Buf(0L, 0L)
  	// Long改为User
      override def reduce(buf: Buf, in: User): Buf = {
          buf.total += in.age
          buf.count += 1
          buf
      }
  
      override def merge(b1: Buf, b2: Buf): Buf = {
          b1.total += b2.total
          b1.count += b2.count
          b1
      }
  
      override def finish(reduction: Buf): Long = reduction.total / reduction.count
  
      override def bufferEncoder: Encoder[Buf] = Encoders.product
  
      override def outputEncoder: Encoder[Long] = Encoders.scalaLong
  }
  ```


### 数据读取和保存

读取：

- `load`：通用的数据读取操作，默认只能处理parquet格式的文件，可通过和`format`组合来读取其他格式的文件，如`spark.read.format("json").load("user.json")`可读取json文件
- `json`：读取json文件，Spark读取的json文件需要每行符合json的格式，不需要符合传统的json规范，如果要读取传统的json，也许要开启`multiLine`选项。

保存：

- `save`：通用的数据保存操作，默认保存为parquet格式的文件，可通过和`format`组合来保存其他格式的文件，如`df.write.format("json").save("output")`可保存为son文件
- 保存模式（`SaveMode`）：保存模式不使用锁，不保证原子性。

### 调优

- 缓存：通过`dataFrame.cache()`或`spark.catalog.cacheTable("tableName")`缓存数据，Spark SQL会扫描需要的列并自动调整压缩来减少内存占用和GC压力。对应的移除缓存数据方法为`dataFrame.unpersist()`或`spark.catalog.uncacheTable("tableName")

- 手动指定连接策略（`BROADCAST/MERGE/SHUFFLE_HASH/SHUFFLE_REPLICATE_NL`，同时出现时优先级从高到低），Spark会使用指定的策略

  Hint方式为`/*+ BROADCAST(指定小表) */ `，如

  ```scala
  SELECT /*+ BROADCAST(t1) */ * FROM t1 INNER JOIN t2 ON t1.key = t2.key;
  ```

  API方式，即操作DataSet或DataFrame

- 合并分区。减少输出文件数量，策略有`COALESCE/REPARTITION/REPARTITION_BY_RANGE/REBALANCE`，其中REBALANCE策略将结果平衡到每个分区上，解决数据倾斜的问题，需要AQE的开启

- 自适应查询执行（Adaptive Query Execution，AQE），Spark 3.2.0之后。其基于运行时分析选择最有效的执行计划，有三个特点：动态合并分区、动态切换Join策略、动态优化Join倾斜
  - 动态合并分区：基于输出的统计信息合并在shuffle完成后的分区，无需手动指定shuffle分区数
  
  - 动态切换Join策略，即将sort-merge join转换为broadcast join（小表的数据广播到大表端，进行join，避免shuffle）：1）当参与join的某一端数据量小于adaptive broadcast hash join threshold时，AQE将sort-merge join转换为broadcast hash join以提高性能；2）当所有的post shuffle partitions都小于一个阈值`spark.sql.adaptive.maxShuffledHashJoinLocalMapThreshold`，且该阈值不小于`spark.sql.adaptive.advisoryPartitionSizeInBytes`，则AQE将sort-merge join转换为shuffled hash join以提高性能
  
  - 动态优化Join倾斜，即skew join优化：通过将数据倾斜的任务拆分（必要时复制）成大小均匀的任务，动态处理在sort-merge join中出现的数据倾斜，也就是自动打散大表，扩容小表。
  
    `spark.sql.adaptive.skewJoin.skewdPartitionFactor`，默认值为5，当任务中最大数据量分区中的数据量大于所有分区中位数乘上该参数时，并且其也大于`spark.sql.adaptive.skewJoin.skewdPartitionThresholdInBytes`（默认256MB）时，认为发生了数据倾斜。
  
    当动态合并分区和动态优化Join倾斜一起使用时，会先动态合并分区，再在其基础上做动态优化Join倾斜。

## Spark Streaming

准实时、微批次的数据处理框架

工作原理：Spark Streaming将实时数据按照时间划分为多个批次的数据序列，传递给Spark引擎处理。

[DStream（discretized stream）](https://spark.apache.org/docs/latest/streaming-programming-guide.html#discretized-streams-dstreams)是随时间推移而收到的数据序列。每个时间区间收到的数据都作为RDD存在。

### StreamingContext

StreamingContext是Spark Streaming的核心类，简称为ssc。因为Spark Streaming是Spark Core的扩展，因此ssc内部维护者SparkContext，通过`ssc.sparkContext`访问。

注意点：

- 调用`ssc.stop`会同时停止SparkContext，如果不想停止SparkContext，在stop方法中设置参数
- SparkContext可以创建ssc，但一个JVM中只能有一个ssc，因此要创建ssc需要前一个ssc已调用stop方法

### 数据采集器

除了从文件系统中获得的DStream之外，从其他源获得的DStream都需要与数据采集器（Receiver）搭配使用。

可以创建多个DStream一起处理，前提是CPU个数要足够，每个Receiver需要占用一个CPU来处理接收数据，因此CPU个数应大于Receiver的个数，使得最少有一个CPU能处理数据分析任务。

数据源：

- 文件系统：从文件系统中获得的DStream不需要Receiver；Spark Streaming扫描目录下的所有文件，并根据文件的修改时间来组织DStream；某个文件被处理完之后再更新，Spark Streaming不会再次对其进行处理

  存储对象的文件系统：对于完全的文件系统如HDFS，最好的方式是先在别的地方写完数据，再将文件移动到Spark Streaming监控的目录让其处理，不这么做的结果可能是HDFS还未写完，Spark Streaming已经对数据进行了处理，导致后续写入的数据不会被处理，对于对象存储的文件系统，也许直接写入监控目录是合适的

- socket

- 第三方源：如[Kafka](https://spark.apache.org/docs/latest/streaming-kafka-0-10-integration.html)、Kinesis

- 自定义数据源（需要自定义数据采集器）：

  ```scala
  def main(args: Array[String]): Unit = {
      val conf = new SparkConf().setAppName("SparkStreaming").setMaster("local[4]")
      // 数据采集周期
      val ssc = new StreamingContext(conf, Seconds(3))
  
      // 数据操作
      val dStream = ssc.receiverStream(new MyReceiver)
      dStream.print()
  
      // 启动数据采集器
      ssc.start()
      // 等待数据采集器的关闭
      ssc.awaitTermination()
  }
  // 自定义数据采集器
  class MyReceiver extends Receiver[String](StorageLevel.MEMORY_ONLY){
      private var isStop = false
      override def onStart(): Unit = {
          new Thread(){
              override def run(): Unit ={
                  while(!isStop){
                      val message = "采集的数据为：" + new Random().nextInt(10).toString
                      store(message)
                      Thread.sleep(500)
                  }
              }
          }.start()
      }
  
      override def onStop(): Unit = {
          isStop = true
      }
  }
  ```


### 无状态转化和有状态转化操作

无状态转化操作：每个数据序列的操作都是独立的，不会对其他批次的结果产生影响。

- `transform`：获取底层的RDD并进行操作，应用场景为1）DStream功能不完善；2）需要周期性执行的代码（每个数据序列需要特殊处理），如RDD操作、分区数量、广播变量、数据库连接等等
- `join`：底层使用两个RDD的join

有状态转化操作：数据序列的操作会对其他批次的结果产生影响。

- `updateStateByKey`：根据key对数据的状态进行更新，需要和checkpoint一起使用
- `window/countByWindow/reduceByWindow/reduceByKeyAndWindow/countByValueAndWindow`：滑动窗口，将多个采集周期的数据一起处理，窗口的范围和移动步长（默认为一个数据采集周期）必须是数据采集周期的整数倍，其中带`invFunc`的`reduceByKeyAndWindow`需要和checkpoint一起使用

### DStream的输出

DStream是惰性求值，如果没有输出就会报错。

- `print`：带时间戳的打印

- `saveAsTextFiles/saveAsObjectFiles/saveAsHadoopFiles`：保存为文件

- `foreachRDD`：对底层的RDD进行操作

  ```scala
  dstream.foreachRDD { rdd =>
    // 在Driver端执行的代码
    ...
    rdd.foreach { record =>
      // 在Executor端执行的代码
      ...
    }
  }
  ```

  对于要使用连接的情况，比较好的方式为：

  ```scala
  dstream.foreachRDD { rdd =>
    rdd.foreachPartition { partitionIterationOfRecords =>
        // 分区共用的连接，更好的方式是从连接池中获取连接，用完后重新放回连接池
      val connection = createNewConnection()
      partitionIterationOfRecords.foreach(record => connection.send(record))
      connection.close()
    }
  }
  ```

  

### 其他

优雅地关闭：启动子线程，在子线程中判断第三方数据（如MySQL、Redis、ZooKeeper）是否存在某个状态，如果存在则进行关闭（`ssc.stop(stopSparkContext=true, stopGracefully=true)`）。

[恢复数据](https://spark.apache.org/docs/latest/streaming-programming-guide.html#how-to-configure-checkpointing)：`StreamingContext.getActivateOrCreate(checkpointPath, 处理逻辑)`。DStream的默认checkpoint是10秒，DStream的checkpoint推荐为移动步长的5～10倍

可以在Spark Streaming中执行Spark SQL，因为ssc中有SparkContext对象

### 调优

- 提高数据采集器的并行度，比如一个采集器接收Kafka的两个topic，那么可以使用两个采集器分别接收不同的topic，再合并为一个DStream
- 设置Receiver的块间隔（`spark.streaming.blockInterval`参数），块间隔与Task数量有关（约等于batchInterval /blockInterval）。如果Task数量太少，则不能有效利用CPU；Task数量太多，则开销大，推荐的最小间隔为50ms。另一个解决办法是使用重分区（`dStream.repartition`），等价于指定了Task的数量，但是需要shuffle
- 数据处理的并行度
- 数据序列化。为了减少GC的花费，Spark会将输入数据和持久化RDD数据进行序列化放在内存中，取用的时候再反序列化，因此这部分会使性能降低，选择合适的序列化方法（如Kryo）或者在某些情况下（比如批次的时间间隔小于几秒且无有状态转换操作）显式设置禁用序列化操作可以提高性能
- 数据批次大小和数据处理能力，让数据处理能力能满足数据批次内的数据量
- 内存调节：
  - 保证足够的内存。Receiver会将数据先放在内存中，如果内存中存放不下数据，则会溢写到磁盘，导致性能降低
  - 减少数据在内存中的占用大小，如启用Kyro序列化机制、启用RDD压缩功能
  - 清除旧数据。默认情况由Spark决定何时清除在内存中的数据和RDD，但如果对数据和RDD使用了`streamingContext.remember`，那么要经过设定的时间之后，Spark才可能去清除这些数据
  - 启用CMS/G1
  - 其他：包括使用堆外内存、使用更多的Executor，但它们的内存更小，从而减小每个堆的GC压力

### 容错机制

在流式处理中，与数据有关的有三处：

- 接收数据：如果数据来自有容错机制的文件系统如HDFS，那么可以保证恰好处理一次；如果数据来自其他源，则Spark可以通过启用write-ahead logs和可靠的Receiver（收到数据并复制完成后使用ack确认），无论是Executor端还是Driver端故障了，都能保证无数据丢失，具有至少一次语义
- 转换数据：由RDD的血缘关系保证数据恰好处理一次
- 写出数据：保证结果至少一次写出，有幂等更新和事务更新（如利用批处理时间戳或者唯一ID）两种方法

## GraphX

### 介绍

通过Graph抽象（关联顶点和边的有向多重图），GraphX扩展了RDD。为了支持图计算，GraphX提供了基础操作（如`subgraph`、`joinVertices`、`aggregateMessage`）以及高级操作Pregel API，还内置了图算法。

### 属性图（property graphs）

属性图是一个在每个顶点和边上有用户自定义对象的有向多重图。有向多重图是一个有向图，可能包含的多条共享起点和终点的平行边。每个顶点使用唯一的VertexId进行标识（long类型），顶点之间的关系与VertexId无关。每条边包含起点与终点的VertexId。

有向多重图需要指定顶点和边的类型，如果它们是基本数据类型（如int、double），GraphX会将它们存储在特殊的数组中以减少内存占用。如果在同一个图中，顶点需要使用不同的类型，可以使用继承实现，比如在二分图中，匹配的顶点类型可能不同。

```scala
// 使用继承，实现在同一个图中顶点类型不同的目的
class VertexProperty()
case class UserProperty(val name: String) extends VertexProperty
case class ProductProperty(val name: String, val price: Double) extends VertexProperty
// 顶点的类型在使用时再决定
var graph: Graph[VertexProperty, String] = null
```

属性图是不可变的、可分区的，具有容错性，改变值或者图的结构都会生成新的图（新图会重用原图未受影响的结构、属性和索引）。通过顶点分区启发式算法将图分区到Executor上。

Graph类包含`VertexRDD[VD]`和`EdgeRDD[ED]`，它们提供图计算的额外功能以及优化，其中`VD`和`ED`分别表示顶点和边的类型。`VertexRDD[VD]`和`EdgeRDD[ED]`分别扩展并优化了`RDD[(VertexId, VD)]`和`RDD[Edge[ED]]`。

使用：

```scala
def main(args: Array[String]): Unit = {
    val sparkConf: SparkConf = new SparkConf().setMaster("local[4]").setAppName("GraphX")
    val sc = new SparkContext(sparkConf)
    // 创建顶点RDD
    val users: RDD[(VertexId, (String, String))] =
    sc.makeRDD(Seq((3L, ("rxin", "student")), (7L, ("jgonzal", "postdoc")),
                   (5L, ("franklin", "prof")), (2L, ("istoica", "prof"))))
    // 创建边RDD
    val relationships: RDD[Edge[String]] =
    sc.makeRDD(Seq(Edge(3L, 7L, "collab"), Edge(5L, 3L, "advisor"),
                   Edge(2L, 5L, "colleague"), Edge(5L, 7L, "pi")))
    // Define a default user in case there are relationship with missing user
    val defaultUser = ("John Doe", "Missing")
    // 初始化图
    val graph: Graph[(String, String), String] = Graph(users, relationships, defaultUser)

    // 统计职位为postdoc的顶点数量
    graph.vertices.filter { case (id, (name, pos)) => pos == "postdoc" }.count
    // 统计起点id大于终点id的边的数量
    graph.edges.filter(e => e.srcId > e.dstId).count
    // 统计起点id大于终点id的边的数量，样例类的方式
    graph.edges.filter { case Edge(src, dst, prop) => src > dst }.count
    // 三元组形式，包括起点属性、终点属性和边属性
    val facts: RDD[String] =
    graph.triplets.map(triplet =>
                       triplet.srcAttr._1 + " is the " + triplet.attr + " of " + triplet.dstAttr._1)
    facts.collect.foreach(println(_))
}
```

### 图操作

Graph类中定义了核心的操作，GraphOps类中定义了组合核心操作的运算操作，由于Scala的隐式转换，GraphOps中的操作可以直接使用，如`graph.inDegrees`。区分Graph类和GraphOps类的原因是所有继承Graph类的子类都需要实现这些核心操作，可以重用GraphOps类的操作。

属性操作（可以重用原图的结构索引，常用于初始化或丢弃掉不必要的属性）：

- `mapVertices`：转换顶点类型
- `mapEdges`：转换边类型
- `mapTriplets`：转换边类型

结构操作：

- `reverse`：反向图
- `subgraph`：子图
- `mask`：类似两张图的交集
- `groupEdge`：将平行边合并为一条边

连接操作：

- `joinVertices`：用输入的RDD中的属性更新图中的顶点属性，当在RDD中存在与顶点的VertexId相同的VertexId时，`map`函数才会被顶点调用，因此，如果不匹配的话则顶点保留原值。其底层调用`outerJoinVertices`。RDD应保证至多只有一个唯一的VertexId
- `outerJoinVertices`：更通用的连接操作，与`joinVertices`的不同是`map`函数会被所有的顶点调用且可以改变顶点的属性类型。RDD应保证至多只有一个唯一的VertexId

相邻聚合操作（在图算法中一般顶点都是与相邻的顶点进行信息交互的）：

- `aggregateMessages`：

  - `sendMsg`函数：用于边的三元组，其是一个`EdgeContext`，包含起点属性、终点属性、边的属性、发送到起点的消息函数（`sendToSrc`）和发送到终点的消息函数（`sendToDst`）（在map-reduce中起map作用）
  - `mergeMsg`函数：聚合这些消息到目的顶点中（将发往同一个顶点的消息两两聚合直到只剩一个消息为止，在map-reduce中起reduce作用）
  - 可选参数`tripletsFields`：指定`EdgeContext`中哪些数据可以被访问，可以帮助GraphX选择优化的join策略
  - 返回包含聚合消息的`VertexRDD[Msg]`，不包含聚合消息的顶点不会返回

  ```scala
  // 统计所有年龄大于以某个顶点为终点的起点的数量以及它们的年龄和 examples/src/main/scala/org/apache/spark/examples/graphx/AggregateMessagesExample.scala
  def main(args: Array[String]): Unit = {
      val sparkConf: SparkConf = new SparkConf().setMaster("local[4]").setAppName("GraphX")
      val sc = new SparkContext(sparkConf)
      // 随机创建100个顶点的图，顶点类型为Double（表示年龄），边类型不重要
      val graph: Graph[Double, Int] =
      GraphGenerators.logNormalGraph(sc, numVertices = 100).mapVertices((id, _) => id.toDouble)
      // 对于一个顶点，统计所有年龄大于以该顶点为终点的起点的数量以及它们的年龄和
      val olderFollowers: VertexRDD[(Int, Double)] = graph.aggregateMessages[(Int, Double)](
          triplet => { // Map Function
              // 对于一个顶点来说，如果它年龄大于终点的年龄，则将数量和年龄发送给终点
              if (triplet.srcAttr > triplet.dstAttr) {
                  triplet.sendToDst((1, triplet.srcAttr))
              }
          },
          // 累积数量与年龄和
          (a, b) => (a._1 + b._1, a._2 + b._2) // Reduce Function
      )
      // 计算平均年龄
      val avgAgeOfOlderFollowers: VertexRDD[Double] =
      // VertexRDD提供的方法有两种形式，一种是带VertexId的，另一种是不带VertexId的
      olderFollowers.mapValues((id, value) =>
                               value match {
                                   case (count, totalAge) => totalAge / count
                               })
      avgAgeOfOlderFollowers.collect.foreach(println(_))
  }
  ```

- `inDegrees/outDegrees/degrees`：由`GraphOps`提供的计算度数的方法

- `collectNeighborIds/collectNeighbors`：收集相邻顶点的信息，消耗较大，因为其需要拷贝相邻顶点的信息，如果能用`aggregateMessages`实现就不要使用这些方法

- `cache`：如果一张图需要使用多次，通过缓存提高性能。然而对于迭代的图计算来说，我们需要在迭代过程中对中间数据进行缓存和清除缓存，这比较难控制，因此推荐使用Pergel API，它能正确清除中间数据的缓存

### Pergel API

Pergel API是GraphX提供的图并行抽象，用于表达图的迭代算法（所谓迭代指某些算法中，顶点的属性可能被更新多次）。

Pergel操作：一个受拓扑约束的批量同步并行消息传递抽象。

Pergel操作执行一系列的super steps：

1. 顶点接收上一个super step的入站消息的总和
2. 计算顶点的新属性
3. 在下一个super step中将消息发送发送到相邻顶点
4. 如果一个顶点在当前super step中没有收到消息，则跳过这个顶点
5. 如果所有顶点都没有消息，则结束Pergel操作

Pergel API包含两个参数列表（`graph.pergel(list1)(list2)`）：

1. 第一个参数列表表示配置参数，包括初始消息（在第一次迭代中每个顶点都会收到）、最大迭代次数、消息发送的方向（默认为向出边发送消息）
2. 第二个参数列表包括接收消息函数（vertex progrom, vprog）、计算消息函数（sendMsg）、合并消息函数（mergeMsg）

使用：

```scala
def main(args: Array[String]): Unit = {
    val sparkConf: SparkConf = new SparkConf().setMaster("local[4]").setAppName("GraphX")
    val sc = new SparkContext(sparkConf)
    // 单源最短路径实现
    // 随机创建100个顶点的图，边类型为Double，表示距离
    val graph: Graph[Long, Double] = GraphGenerators.logNormalGraph(sc, numVertices = 100).mapEdges(e => e.attr.toDouble)
    // VertexId为42的顶点作为起点
    val sourceId: VertexId = 42
    // 初始化距离，到起点的距离初始化为0，到其他顶点的距离初始化为正无穷大
    val initialGraph: Graph[Double, Double] = graph.mapVertices((id, _) => if (id == sourceId) 0.0 else Double.PositiveInfinity)
    val sssp = initialGraph.pregel(Double.PositiveInfinity)(
        (id, dist, newDist) => math.min(dist, newDist), // Vertex Program
        triplet => { // 发消息
            if(triplet.srcAttr + triplet.attr < triplet.dstAttr){
                Iterator((triplet.dstId, triplet.srcAttr + triplet.attr))
            }else{
                Iterator.empty // 该顶点将在下一个super step中被忽略
            }
        },
        (a, b) => math.min(a, b) // 合并消息
    )
    println(sssp.vertices.collect.mkString("\n"))
}
```

### 图构建器

GraphX可以从RDD或者磁盘上构建图，默认情况下，图构建器不会对图的边进行重新分区（仍保留在原来的分区中）。`Graph.groupEdges`对图的边进行重新分区，由于其假设相同的边位于同一分区，因此在调用它之前需要先调用`Graph.partitionBy`。

`GraphLoader.edgeListFile`从磁盘上加载边并构建图（以邻接表的形式存储，`#`是注释行），会创建边和对应的点，边和顶点的属性都是1，`canonicalOrientation`参数（规范方向）表示起点id必小于终点id，而不是简单地认为第一个是起点id，第二个是终点id。如：

```
# 起点id 终点id
2 1
4 1
1 2
```

`Graph.apply`：从顶点RDD和边RDD中创建图，如果某个顶点不在顶点RDD中出现，则赋默认值

`Graph.fromEdges`：从边RDD中创建图，顶点赋默认值

`Graph.fromEdgeTuples`：从边的元组RDD中创建图（与边RDD的不同之处在于只有起点和终点），边的值为1，顶点赋默认值，支持根据策略将重边删除

### VertexRDD和EdgeRDD

**VertexRDD**

`VertexRDD[VD]`扩展了`RDD[(VertexId, VD)]`：1）其添加了每个VertexId只会出现一次的约束；2）其用可重用的HashMap结构存顶点的属性，因此如果从一个`VertexRDD`中生成两个不同的`VertexRDD`（如用filter方法或mapValues方法），新生成的两个`VertexRDD`可以在常数时间内合并。其提供的额外功能有：

- `filter`：过滤顶点但保留内部的索引。通过`BitSet`实现重用索引以及能与其他`VertexRDD`进行快速join

- `mapValues`：转换值的类型，但保留内部的索引。与`filter`同理

- `minus`：返回两个RDD的交集

- `diff`：当前RDD中移除两个RDD的交集

- `leftJoin/innerJoin`：使用内部索引加快join操作。如果输入的RDD是`VertexRDD`并且它们来自同一个HashMap，则通过线性扫描来join两个RDD而不是用点查询（点查询消耗相对较大）

- `aggregateUsingIndex`：对于输入的RDD，使用当前RDD上的索引来加速`reduceByKey`操作。如果一个`VertexRDD`来自于调用了本方法的`VertexRDD`，那么对这两个`VertexRDD`进行join操作效率会很高

  ```scala
  val setA: VertexRDD[Int] = VertexRDD(sc.parallelize(0L until 100L).map(id => (id, 1)))
  val rddB: RDD[(VertexId, Double)] = sc.parallelize(0L until 100L).flatMap(id => List((id, 1.0), (id, 2.0)))
  rddB.count // rddB中有200个entries
  val setB: VertexRDD[Double] = setA.aggregateUsingIndex(rddB, _ + _)
  setB.count // setB中有100个entries
  // Joining A and B should now be fast!
  val setC: VertexRDD[Double] = setA.innerJoin(setB)((id, a, b) => a + b)
  ```

**EdgeRDD**

`EdgeRDD[ED]`扩展了`RDD[Edge[ED]]`，其使用分区策略将边放在分区的块中。为了保证重用性（比如改变属性值时），每个分区中边的属性和邻接结构是分开存储的。其提供的额外功能通常通过图操作或者RDD基类中的操作完成，有：

- `mapValues`：保留结构的同时转换边的类型
- `reverse`：翻转边的方向，保留结构和属性
- `innerJoin`：对两个使用相同分区策略的`EdgeRDD`进行join操作

### 优化表示

Spark使用点切割以实现分布式图计算。点分割实现过程：

1. 思路是将一个点拆分成多份，放到不同的分区中，也就是说边都是完整的
2. 由于一般边的数量会多于顶点的数量，因此，将顶点的属性放在边里（也就是三元组）
3. 并非所有分区都包含与所有顶点相邻的边（由2决定），因此通过路由表来标识顶点的分区（比如对于顶点A，它的路由表是1、2，就表示其在分区1和分区2中），要跨分区操作时就需要用到路由表（如`triplets`和`aggregateMessages`）

### 图算法

**PageRank**

PageRank用于说明顶点的重要性，GraphX提供静态和动态的PageRank，静态PageRank运行固定的迭代次数，而动态PageRank则需要收敛到某一值后才会停止

**Connected Components（连通分量）**

每个连通分量用其编号最小的VertexId来标识。

**Triangle Counting（三角计数）**

计算图中有多少个三个顶点的子图，三个顶点两两相连。三角计数算法使用的前提有：1）规范方向（即srcId < dstId）；2）图能被`Graph.partitionBy`方法分区。

计算三角形个数时，要计算方向（如，起点id<中间点id<终点id），如：设A和B是邻居，A的相邻顶点集合是B、C、D、E，B的相邻顶点集合是A、C、E、F、G，而它们的交集是C、E，则有ABC和ABE两个三角形。

