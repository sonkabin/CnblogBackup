## Explain查看执行计划

Spark SQL执行过程：分析、逻辑优化、生成物理执行计划、评估模型分析（走哪个索引）、代码生成。

物理执行计划（`spark.sql(sqlstr).explain(mode = "extended")`）：

- HashAggregate：数据聚合，一般成对出现，第一个HashAggregate将执行节点本地的数据进行局部聚合，另一个HashAggregate将各个分区的数据进行进一步聚合
- Exchange：shuffle操作，表示需要在集群上移动数据，大部分情况下两个HashAggregate中间以Exchange分隔
- Project：投影操作，选择感兴趣的部分列
- BroadcastHashJoin：基于广播方式进行HashJoin
- LocalTableScan（对于Hive表）：全表扫描本地的表
- FileScan（对于文件）：读文件

## 资源调优

### 资源规划

**内存估算**

估算Other内存（默认占可用内存的40%）=用户自定义数据结构×每个Executor核数

估算Storage内存=广播变量+cache/Executor数量

估算Executor内存=每个Executor核数×（数据集大小/并行度）

**调整内存**

Spark默认使用的内存为：1）预留内存300M；2）其他内存，放用户自定义数据结构和Spark内部元数据，默认占可用内存的40%；3）Storage内存，缓存数据，占可用内存的60%的50%；4）Execution内存，缓存在执行shuffle过程中产生的中间数据，占可用内存的60%的50%。其中，3和4使用统一内存管理，用于动态占用对方的内存。`spark.memory.fraction`控制（3+4）/（3+4+2）的比例，`spark.memory.storageFraction`控制3/（3+4）的比例。

### 持久化和序列化

RDD的缓存结合Kryo序列化，占用的内存会比使用Java序列化占用的内存小很多。

DataFrame和DataSet使用Spark提供的Encoder实现序列化和反序列化，占用的内存也很小。相比较于RDD的缓存，我们无需考虑序列化的方式。

### CPU优化

并行度：

- `spark.default.parallelism`：RDD的默认并行度，没有设置时，由join、reduceByKey、parallelize等转换决定（根据shuffle结果有多少个分区来决定）。
- `spark.sql.shuffle.partitions`：适用于SparkSQL，Shuffle Reduce阶段的默认并行度（200），此参数只能控制SparkSQL、DataFrame、DataSet分区个数，不能控制RDD分区个数。

并发度：同时执行的task数量。

**CPU低效的原因**：

- 并行度过低，数据分片较大容易导致CPU线程挂起，即一个分区中数据过多，占用内存过多，只能支持部分task执行，导致不能充分利用CPU核数。
- 并行度过高，数据过于分散会让调度开销更多，即分区过多，task太多，线程调度消耗太多资源。

合理利用CPU资源：一般将并行度（task数）设置为并发度的2到3倍。

## SparkSQL语法优化

RBO：Rule-Based Optimization，基于规则的优化器。

CBO：Cost-Based Optimization，基于代价的优化器。

### 基于RBO的优化器

**谓词下推**

谓词下推就是提前进行数据过滤：

- 内连接（Inner Join）：谓词写在on后面或者where后面，优化器都会在每张表扫描的时候将该谓词作为条件进行过滤，以减少join的数据量。
- 外连接（Outer Join）：
  - 左外连接：on和where的语义是不同的，因此结果也不同。在on后面的谓词的语义是对右表进行过滤，然后左表进行左外连接；在where后面的谓词的语义是对连接表之后得到的结果再次进行过滤（等价于内连接）。即Join中的条件，谓词下推到右表；Join后的条件，谓词下推到两表。
  - 右外连接，同理。

**列裁剪**

列裁剪指扫描数据源时，只读取那些与查询相关的字段。

**常量替换**

能用常量替换的地方直接用常量替换，而不是每次都计算一遍。

### 基于CBO的优化器

通过`spark.sql.cbo.enabled`开启，CBO优化器会基于表和列的统计信息（需保证统计信息已经生成），进行估算以选出最优的查询计划。如Build侧选择、优化Join类型、优化多表Join顺序。

**在Spark 3.2.0之后，使用AQE代替CBO，AQE的优势是无需预先生成统计信息，其在执行过程中统计数据，并动态地调节执行计划。**

**广播Join**

Spark的join策略中，如果一张小表足够小且可以缓存到内存中，那么可以使用Broadcast Hash Join，原理是先将小表聚合到Driver端，再广播到各个大表的分区中，实现本地join，避免了shuffle过程。

**SMB Join**

sort merge bucket操作，先进行分桶，每个桶再进行排序，然后根据key进行合并。分桶的目的是把大表化成小表，相同的key在同一个桶中进行join操作，就无需扫描大量无效的数据。

## 数据倾斜

数据倾斜的现象：有几个task任务运行缓慢，可能导致数据溢出。**task的运行时间非常长，即小绿条很长**。或者Shuffle Read某几个比较大。或者溢写数据量大。

数据倾斜的原因：shuffle类算子（distinct、groupByKey、reduceByKey、aggregateByKey、join、cogroup）可能导致某个key的数据量非常大。join使得大key出现的情况：比如一张表key=1有1亿个，其他key只有几百个，另一张表key都为1，两者的join之后就会使得处理很慢，groupByKey也会有这种情况。

**倾斜大key定位**

```scala
// 通过采样，取topK个key，实例如下
def sampleTopKey (sparkSession: SparkSession, tableName: String, keyColumn: String): Array[(Int, Row)] = {
    val df = sparkSession.sql(s"select ${keyColumn} from ${tableName}")
    val top10Key = df.select(keyColumn).sample(false, 0.1).rdd // 这里抽样10%
    	.map(k => (k, 1)).reduceByKey(_ + _) // 统计不同的key出现的次数
    	.map(k => (k._2, k._1)).sortByKey(false) // 按照数量降序
    	.take(10)
   	top10Key
}

def main(args: Array[String]): Unit = {
    val sparkConf: SparkConf = new SparkConf().setAppName("BigKeySample")
    val spark: SparkSession = SparkSession.builder().config(sparkConf).getOrCreate()
    
    
    println("----------cscTopKey-----------")
    val cscTopKey = sampleTopKey(spark, "sparktuning.course_shopping_cart", "courseid")
    println(cscTopKey.mkString("\n"))
    
    println("----------scTopKey-----------")
    val scTopKey = sampleTopKey(spark, "sparktuning.sale_course", "courseid")
    println(scTopKey.mkString("\n"))
    
    println("-----------cpKey----------")
    val cpKey = sampleTopKey(spark, "sparktuning.course_pay", "orderid")
    println(cpKey.mkString("\n"))
}
```

**单表数据倾斜优化**

Spark SQL提供预聚合功能（explain时可以发现，在Exchange之前有一个HashAggregate，在之后也有一个HashAggregate，之前的HashAggregate就是在预聚合），优化效果不错。

不过，如果大key分布在大量的不同分区（不过一般不会出现，200个分区经过预聚合后就没啥问题了，比如有10w个分区，可能就用得上了hh，不过也不太可能），则优化效果还可以进一步提高，可以使用二次聚合（加盐局部聚合+去盐全局聚合），可通过UDF实现，先添加盐再去除盐。

**Join数据倾斜优化**

- 广播Join。小表足够小可以被加载到Driver并能广播到各个Executor中。其避免了Shuffle

- 拆分大key，打散大表，扩容小表。（大表的倾斜key加盐，比如加随机数前缀，构成三类，为了能和小表join，需要让小表扩容，也给小表加相同的盐，因为小表还有其他的key，所以最终小表的数据量会扩大为原来的3倍）。

  有两种情况：

  1. 如果倾斜的key只有一个，可以只将其提出来，然后小表也只提取对应的key，再进行上述的操作；
  2. 如果倾斜的key有多个，则一种方式是拆成多个一个，另一种的话，如果小表足够小，那么直接扩容就可以了。

  实现步骤：

  将表拆分为包含大key的数据和不包含大key的数据两部分，将包含大key的表进行打散（即加盐），小表的每个key需要与打散后大表的key进行聚合，因此每个key需要扩容为打散的次数个key（key1扩容为key1_1, key1_2，...使之能与打散后大表的key对应）。不包含大key的数据表与小表join，打散后大表与扩容小表进行join，最后合并。

  虽然万金油，但是shuffle阶段增多，因此作为最后手段。

  ```scala
  /*
  courseShoppingCart中倾斜key是id=101和103的资源
  */
  def scatterBigAndExpansionSmall(spark: SparkSession): Unit = {
      val saleCourse = spark.sql("select * from sparktuning.sale_course")
      val coursePay = spark.sql("select * from sparktuning.course_pay")
      	.withColumnRenamed("discount", "pay_discount")
      	.withColumnRenamed("createtime", "pay_createtime")
      val courseShoppingCart = spark.sql("select * from sparktuning.course_shopping_cart")
      	.withColumnRenamed("discount", "cart_discount")
      	.withColumnRenamed("createtime", "cart_createtime")
      
      // 1.拆分倾斜key
      val commonCourseShoppingCart: DataSet[Row] = courseShoppingCart.filter(item => item.getAs[Int]("courseid") != 101 && item.getAs[Int]("courseid") != 103)
      val skewCourseShoppingCart: DataSet[Row] = courseShoppingCart.filter(item => item.getAs[Int]("courseid") == 101 || item.getAs[Int]("courseid") == 103)
      
      // 2.倾斜key打散为36份，这里是因为并行度设置了36，其他情况具体分析~
      val newCourseShoppingCart = skewCourseShoppingCart.mapPartitions((partitions: Iterator[Row] => {
          partitions.map(item => {
              val courseid = item.getAs[Int]("courseid")
              val randInt = Random.nextInt(36)
              CourseShoppingCart( // 样例类
                  courseid, 
                  item.getAs[String]("orderid"),
                  item.getAs[String]("coursename"),
                  item.getAs[java.math.BigDecimal]("cart_discount"),
                  item.getAs[java.math.BigDecimal]("sellmoney"),
                  item.getAs[java.sql.Timestamp]("cart_createtime"),
                  item.getAs[String]("dt"),
                  item.getAs[String]("dn"),
                  randInt + "_" + courseid) // join key
          })
      }))
      
      // 3.小表扩容36倍, flatMap是因为一个key对应到多个key，map完直接拍平
      val newSaleCourse = saleCourse.flatMap(item => {
          val res = new ArrayBuffer[SaleCourse]()
          for (i <- 0 until 36) {
              res.append(SaleCourse( // 样例类
              	item.getAs[Int]("courseid"),
              	item.getAs[String]("coursename"),
              	item.getAs[String]("status"),
              	item.getAs[Int]("pointlistid"),
              	item.getAs[Int]("majorid"),
              	item.getAs[Int]("chapterid"),
              	item.getAs[String]("chaptername"),
              	item.getAs[Int]("edusubjectid"),
              	item.getAs[String]("edusubjectname"),
              	item.getAs[Int]("teacherid"),
              	item.getAs[String]("teachername"),
              	item.getAs[String]("coursemanager"),
                  item.getAs[java.math.BigDecimal]("money"),
                  item.getAs[String]("dt"),
                  item.getAs[String]("dn"),
                  i + "_" + courseid // join key
              ))
          }
          res
      })
      
      // 4. 倾斜的大key与扩容后的表join
      val df1 = newSaleCourse
      	.join(newCourseShoppingCart.drop("courseid").drop("coursename"), Seq("rand_courseid", "dt", "dn"), "right")
      	.join(coursePay, Seq("orderid", "dt", "dn"), "left")
      	.select("需要的字段")
      
      // 5. 没有倾斜的部分与原来的表join
      val df2 = saleCourse
      	.join(commonCourseShoppingCart, Seq("rand_courseid", "dt", "dn"), "right")
      	.join(coursePay, Seq("orderid", "dt", "dn"), "left")
      	.select("需要的字段")
      
      // 6. union结果
      df1.union(df2)
  }
  ```

  

- AQE

## Job优化

### Map端优化

**Map端聚合**

使用RDD时建议使用reduceByKey或aggregateByKey算子来代替groupByKey算子，因为groupByKey算子不会进行预聚合。

**读取小文件优化**

读取的数据源有很多小文件，由于每个小文件对应Spark中的一个分区，也就是一个Task，当存在shuffle操作时，严重影响性能，大量的数据分片信息以及对应产生的Task元信息也会给Spark Driver的内存造成压力。

```properties
# 默认128MB，最大分区字节数
spark.sql.files.maxPartitionBytes=128MB
# 默认4MB，打开文件的预估成本，当一个分区写入多个文件时使用。高估更好，这样小文件分区将比大文件分区更先被调度。
spark.files.openCostInBytes=4194304
```

**增大map溢出时输出流buffer的大小**

`spark.shuffle.file.buffer`默认是32k，通过增大它的大小，可以提高性能（写的性能，即输出的缓冲区变大，文件打开关闭的次数就能减少）。

### Reduce端优化

**设置Reduce数**

与并发度和并行度相关。

**输出产生小文件优化**

- Join的结果插入新表，生成的文件数等于shuffle并行度，默认是200

  解决方法：

  1. 在插入表数据之前缩小分区，如coalesce、repartition算子，缺点是join之后还需要重新分区。
  2. 调整shuffle并行度，缺点是并行度过低可能导致数据分片较大

- 动态分区插入数据

  小文件产生原因：在没有shuffle情况下，最差的情况是每个Task都有表各个分区的记录，那么每个分区中都会保存Task数量个文件。

  解决方法：通过shuffle，让一个分区的数据都在一个Task中，那么写入的时候文件数量就减少了。

与Suffle Read时间有关：

- **增大Reduce端缓冲区，减少拉取次数**

  Reduce端需要拉取Map端的数据先放到缓冲区内（`spark.reducer.maxSizeInFlight`，默认48MB），如果Map端数据量很多，那么Reduce端可能要拉取多次，网络传输次数较多。如果内存资源充足，可以增大缓冲区大小，以减少拉取次数。

- **调整Reduce端拉取数据重试次数**

  Reduce Task拉取数据时，如果因为网络波动或JVM full gc等原因失败会自动重试。对于那些包含了特别耗时的shuffle操作的作业，建议增加最大重试次数（`spark.shuffle.io.maxRetries`，默认为3）。如果指定次数重试仍然未能成功拉取，则作业执行失败。

- **调整Reduce端拉取数据的等待间隔**

  在一次失败后，会等待一定的时间间隔（`spark.shuffle.io.retryWait`，默认为5秒）再进行重试，可以通过增加等待间隔以增加shuffle操作的稳定性。

**合理利用bypass**

当ShuffleManager为SortedShuffleManager时，如果shuffle read task（并行度）数量小于阈值（`spark.shuffle.sort.bypassMergeThreshold`，默认200）且不进行Map端聚合（比如group by+sum会有预聚合），则shuff write过程不会进行排序操作，相比较SortShuffleWriter性能更好，其使用BypassMergeSortShuffleWriter写数据，最后将每个task产生的临时文件合并成一个文件，并创建单独的索引文件实现排序。

使用SortedShuffleManager时，**如果无需排序操作**，那么可以将阈值调大一些以大于shuffle read task数量，从而启用bypass机制。

```scala
SortShuffleManager.scala#registerShuffle方法
```



### 整体优化

**调节数据本地化等待时长**

每个Task都有本地化级别，分别为PROCESS_LOCAL、NODE_LOCAL、RACK_LOCAL、ANY。如果发现很多级别是前两个，则无需调节；但是如果大部分是后两个，则可能需要调节本地化的等待时长。所谓本地化指的是数据和Task所处的位置，PROCESS_LOCAL指数将和Task在同一个进程，NODE_LOCAL指数据和Task在同一个节点上，RACK_LOCAL指数据和Task在同一个机架上（同一块区域内的服务器集群上），ANY指数据和Task在任意位置。等待时长指的是将Task调度到目标节点上需要花费的时间，Task会从最高优先级的本地化级别开始，如果在指定的等待时长内未能完成调度，则会降级到下一个本地化级别。因此，可以通过增加本地化等待时长尝试缩短Spark运行时间，但是要注意的是，如果网络传输时间比等待时长要短，提高等待时长可能反而增加Spark运行时间。

**使用堆外内存**

堆外内存参数：

```
spark.executor.memory # 指定任务提交时的堆内内存
spark.executor.memory.Overhead # 堆外内存参数，表示内存的额外开销。默认开启，默认值为 spark.executor.memory×0.1，并且取MAX(384MB, cur)，这就是YARN模式下，申请堆内内存1个G时，实际申请的内存大于1个G的原因
spark.memory.offHeap.size # 堆外内存参数，Spark中默认关闭，需要将spark.memory.offHeap.enabled设置为true才能生效
```

堆外缓存：

当需要缓存的数据量比较大时，为了减轻JVM的GC压力，可以将缓存放在堆外（在cache的时候指定缓存位置）。

**调节连接等待时长**

生产环境下，有时候会遇到file not found、file lost这类错误，这种情况下可能是因为Executor的BlockManager在拉取数据时，无法建立连接（如发生Full GC使得无法提供服务），超过默认的连接等待时长后，说明数据拉取失败，重新拉取数据从而延长了Spark作业时间，如果反复尝试都失败，可能导致Spark作业失败。

```
--conf spark.core.connection.ack.wait.timeout=300s。默认等于spark.network.timeout的值120s，一般是够了的，除非一直在full GC
```

## AQE

自适应查询执行（Adaptive Query Execution，AQE），Spark 3.2.0之后。其基于运行时分析选择最有效的执行计划，有三个特点：动态合并分区、动态切换Join策略、动态优化Join倾斜

- 动态合并分区：基于输出的统计信息合并在shuffle完成后的分区，无需手动指定shuffle分区数

- 动态切换Join策略，即将sort-merge join转换为broadcast join（小表的数据广播到大表端，进行join，避免shuffle）：1）当参与join的某一端数据量小于adaptive broadcast hash join threshold时，AQE将sort-merge join转换为broadcast hash join以提高性能；2）当所有的post shuffle partitions都小于一个阈值`spark.sql.adaptive.maxShuffledHashJoinLocalMapThreshold`，且该阈值不小于`spark.sql.adaptive.advisoryPartitionSizeInBytes`，则AQE将sort-merge join转换为shuffled hash join以提高性能

- 动态优化Join倾斜，即skew join优化：通过将数据倾斜的任务拆分（必要时复制）成大小均匀的任务，动态处理在sort-merge join中出现的数据倾斜，也就是自动打散大表，扩容小表。

  `spark.sql.adaptive.skewJoin.skewdPartitionFactor`，默认值为5，当任务中最大数据量分区中的数据量大于所有分区中位数乘上该参数时，并且其也大于`spark.sql.adaptive.skewJoin.skewdPartitionThresholdInBytes`（默认256MB）时，认为发生了数据倾斜。

  当动态合并分区和动态优化Join倾斜一起使用时，会先动态合并分区，再在其基础上做动态优化Join倾斜。

## DPP

动态分区裁剪（Dynamic Partition Pruning），也就是谓词下推，将join一侧作为子查询计算出来，再将其所有分区用到join的另一侧作为表过滤条件，从而减少另一侧的数据量，以提高最终join时的速度。默认开启，需要满足：1）join条件里必须有分区字段；2）如果要裁剪左表，那么join必须是inner join、left semi join或right join，如果是left outer join，无论右表有没有这个分区，左表都存在，因此不需要被裁剪；3）至少存在一个过滤条件。

