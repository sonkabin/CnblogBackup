## 前言
面试中被问了知道LRU算法吗？当然是秒答知道。知道如何实现LRU么？回答用Java的LinkedHashMap，将`accessOrder`属性设置为`true`即可。接下来问道，是否知道这种实现的缺点？如何改进？emmmmmm，没准备过还真不知道如何回答，因此有了这篇博客进行整理。
## LRU的实现方式
参考[简书：LRU算法](https://www.jianshu.com/p/d533d8a66795)。

缓存污染定义：来了一大批被访问的新数据，导致热点key被淘汰，而不常用的key却进入缓存中。

1. 朴素LRU（单个LRU队列）：存在缓存污染问题
2. LRU-K（最近使用K次）
3. Two-queue（FIFO+LRU）
4. Multi Queue（多个优先级不同的LRU队列）

## LRU算法实现
### 手写LRU
O(1)时间实现LRU的各种操作
[Leetcode:146. LRU 缓存机制](https://leetcode-cn.com/problems/lru-cache/)
### Java实现
1. `accessOrder`设为`true`；

	```java
	public LinkedHashMap(int initialCapacity,
							 float loadFactor,
							 boolean accessOrder) {
		super(initialCapacity, loadFactor);
		this.accessOrder = accessOrder;
	}
	```

2. 覆盖方法`removeEldestEntry`，默认实现是返回false

	```java
	@Override
	public boolean removeEldestEntry(Map.Entry<K, V> eldest){
		return size() > capacity; // capacity为LRU队列的长度
	}
	```

### 操作系统
操作系统中的页面置换算法中存在LRU算法，但是不会用Java的这种方式去实现，另外也不用朴素的LRU实现，因为它的时间复杂度是O(N)。因此操作系统使用**CLOCK算法**近似实现LRU

- 简单CLOCK算法：每个页面设置一个**访问位**，将页面链接成**循环队列**。如果某个页被访问，则将访问位置为1，淘汰页面时，如果访问位是0则淘汰它，否则将访问位置为0，检查下一个页面；如果所有页面都是1，则进行第二次扫描
- 改进的CLOCK算法：在考虑访问位的同时，再添加一个修改位。在其他条件相同时优先淘汰没有被修改过的页面，以避免IO操作。
### MySQL
InnoDB使用**链表(buffer pool)**实现LRU算法。

- 当要加入新页时，将新页加入到链表的中间(称为midpoint)，它将链表分为两个子链表，头部到midpoint之间的page是new sublist，midpoint到尾部之间的page是old sublist
- 3/8的buffer pool作为old sublist
- 新页插在midpoint上。新页产生的原因有：执行query语句，InnoDB的自动预读功能
- 数据页加载到buffer pool，在`innodb_old_blocks_time=1s`后被访问，才会被移动new sublist的头部。执行query语句后，新页马上会被访问到，故会放到头部；但是预读的页可能不会被访问到，也许到被淘汰时可能都没被访问过
- 头部到midpoint之间的3/4 page被访问不会移动，这是为了减少缓冲区的异动
- 旧页会在尾部被淘汰
- InnoDB默认的全表扫描（mysqldump、没有WHERE条件的SELECT语句）会淘汰大量的旧数据，通过设置`innodb_old_blocks_time`，可以保护频繁被访问的页面不被淘汰。
### Redis
为了节约内存，不用链表而是用**数组(pool)**实现LRU
- 当有一个key过期时，随机挑选N个key，放入pool（大小为M）中
- pool中按照idle从小到大的顺序排列，idle越大，淘汰的优先级越高
- pool满时，将第一个key挤出pool
- 淘汰时，淘汰最后一个key
- pool中的key可能是已经被删除的key（缓存中不存在了，但是存在于pool中）

## 参考
1. MySQL doc（refman）：InnoDB Buffer Pool LRU Algorithm
2. Redis：`evict.c`