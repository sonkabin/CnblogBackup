## Spark SQL测试

### scala shell版本

```scala
import org.apache.spark.sql._
import org.apache.spark.sql.types._
/*
使用DataFrame时，如果涉及到转换规则，需要引入转换规则
比如$：df.select($"username", $"age")
*/
import spark.implicits._

// 一些常用的库
import java.util.regex.Pattern
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import scala.collection.mutable.ArrayBuffer

val data = Seq(
      Row("A", "www.baidu.com"),
      Row("B", "www.bing.com"),
      Row("C", "www.360.com"),
      Row("A", "www.shenma.com")
    )
val dataSchema = StructType(Array(
    StructField("name", StringType, true),
    StructField("url", StringType, true)
))
val df = spark.createDataFrame(spark.sparkContext.makeRDD(data), dataSchema)
df.show()
```



### python shell版本

```python
from pyspark.sql.types import *

data = [
      ("A", "www.baidu.com"),
      ("B", "www.bing.com"),
      ("C", "www.360.com"),
      ("A", "www.shenma.com")
    ]
dataSchema = StructType([
    StructField("name", StringType, True),
    StructField("url", StringType, True)
])
df = spark.createDataFrame(spark.sparkContext.makeRDD(data), schema=dataSchema)
df.show()
```



### 一个RDD中是否包含另一个RDD的

