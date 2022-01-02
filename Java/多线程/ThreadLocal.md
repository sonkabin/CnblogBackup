# ThreadLocal

## 方法

将ThreadLocalMap看成一个键是弱引用、值是强引用的简化版HashMap（hash冲突用开放地址法解决）

### set

作用：当前线程拷贝一份对象到本地中

```java
public void set(T value) {
    Thread t = Thread.currentThread();
    /*返回线程内部的 threadLocals，它是 ThreadLocal.ThreadLocalMap 对象
    ThreadLocalMap getMap(Thread t) {
        return t.threadLocals;
    }
    */
    ThreadLocalMap map = getMap(t);
    if (map != null) // 说明有其他的 ThreadLocal<?> 对象存在。set 方法清理键被回收的 ThreadLocal<?> 时并不是全部扫描一遍，而是从某个位置开始将它后面的清理一遍
        map.set(this, value);
    else
        /*
        void createMap(Thread t, T firstValue) {
            t.threadLocals = new ThreadLocalMap(this, firstValue); // this 是 ThreadLocal<?>对象
        }
        */
        createMap(t, value);
}
```



### get

作用：返回当前线程的本地值

```java
public T get() {
    Thread t = Thread.currentThread();
    ThreadLocalMap map = getMap(t);
    if (map != null) {
        ThreadLocalMap.Entry e = map.getEntry(this);
        if (e != null) {
            @SuppressWarnings("unchecked")
            T result = (T)e.value;
            return result;
        }
    }
    // 线程本地值没有初始化，先执行初始化
    return setInitialValue();
}

private T setInitialValue() {
    T value = initialValue(); // 由开发人员编写的初始化值的方法
    // 下面的类似于 set 方法
    Thread t = Thread.currentThread();
    ThreadLocalMap map = getMap(t);
    if (map != null)
        map.set(this, value);
    else
        createMap(t, value);
    return value;
}
```



### remove

作用：将以当前ThreadLocal为key对应的value置为null，帮助GC

```java
public void remove() {
    ThreadLocalMap m = getMap(Thread.currentThread());
    if (m != null)
        // 最终会将值置为 null
        m.remove(this);
}
```



### ThreadLocal

![ThreadLocal](pic/ThreadLocal.jpg)



## 示例

```java
static ThreadLocal<SimpleDateFormat> simpleDateFormat = new ThreadLocal<SimpleDateFormat>(){
    @Override
    protected SimpleDateFormat initialValue(){
        return new SimpleDateFormat("yyyy-MM-dd");
    }
};
static SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd");
public static void main(String[] args) throws Exception {
    for(int i = 0; i < 100; i++){
        new Thread(){
            public void run(){
                try {
                    // 线程不安全
                    // System.out.println(format.parse("2021-5-16"));
                    
                    // 线程安全
                    System.out.println(simpleDateFormat.get().parse("2021-5-16"));
                } catch (ParseException e) {
                    e.printStackTrace();
                }
            }
        }.start();
    }
}
```



## 使用场景

1. 线程间数据的隔离，比如`SimpleDateFormat`
2. 对象跨层传递时，可以避免多次传递

## 总结

1. 什么是ThreadLocal？（有什么用？）

   ThreadLocal可以让一个对象是共享变量，统一设置初始值，但是每个线程对这个对象的修改都是互相独立的。

2. 怎么用？

   每个线程的内部都维护了一个 ThreadLocalMap。将一个共用的ThreadLocal**静态实例**（不是静态则失去了线程间共享的本质属性）作为key，set方法拷贝一份对象到线程本地的ThreadLocalMap中，get方法从本地的ThreadLocalMap中获取对象，remove方法将key以及它对应的value置为null

3. 有什么使用时应该注意的事项吗？

   1. 内存泄漏：弱引用的key被回收后，value不会被回收
   2. 脏数据：线程池会重用线程，而复用线程会产生脏数据。如果下一次使用的线程不调用set设置初始值，则get可能会得到脏数据。

   解决办法是每次用完ThreadLocal时，及时调用remove方法清理

