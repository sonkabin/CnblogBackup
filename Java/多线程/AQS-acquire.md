# AQS源码阅读-acquire/release

## acquire相关方法

### acquire

作用：外观模式

```java
public final void acquire(int arg) {
    // 如果拿不到资源，则创建 Node 并让它入队
    if (!tryAcquire(arg) &&
        // acquireQueued 方法返回 true 表示需要设置线程的中断状态
        acquireQueued(addWaiter(Node.EXCLUSIVE), arg))
    	/*
    	static void selfInterrupt() {
            Thread.currentThread().interrupt();
        }
    	*/
        selfInterrupt();
}
```

### addWaiter

作用：创建新的 Node 并让它入队

```java
// 为当前线程创建 Node 并入队。mode 可以指定为 SHARED 或 EXCLUSIVE ，SHARED = new Node(), EXCLUSIVE = null
private Node addWaiter(Node mode) {
    Node node = new Node(Thread.currentThread(), mode);
    // 通过一次CAS尝试入队，如果失败了，则调用 enq 方法不断重试
    // Try the fast path of enq; backup to full enq on failure
    Node pred = tail;
    if (pred != null) {
        node.prev = pred;
        /*
        private final boolean compareAndSetTail(Node expect, Node update) {
            return unsafe.compareAndSwapObject(this, tailOffset, expect, update);
        }
        */
        if (compareAndSetTail(pred, node)) {
            pred.next = node;
            return node;
        }
    }
    enq(node);
    return node;
}
```



### enq

作用：

1. head 没有初始化时的初始化操作
2. CAS 重试方式将 Node 放入队尾

```java
private Node enq(final Node node) {
    for (;;) {
        Node t = tail; // 取最新的队尾
        if (t == null) { // Must initialize
            // head = tail = null
            /*
            private final boolean compareAndSetHead(Node update) {
                return unsafe.compareAndSwapObject(this, headOffset, null, update);
            }
            */
            if (compareAndSetHead(new Node()))
                tail = head;
        } else {
            node.prev = t;
            if (compareAndSetTail(t, node)) {
                t.next = node;
                return t;
            }
        }
    }
}
```



### acquireQueued

作用：阻塞机制

```java
// 独占、不可中断模式。未抢到资源时的阻塞机制、以及跳过 CANCELLED 状态的 Node 在这里实现
/**
 * Acquires in exclusive uninterruptible mode for thread already in
 * queue. Used by condition wait methods as well as acquire.
 */
final boolean acquireQueued(final Node node, int arg) {
    boolean failed = true;
    try {
        boolean interrupted = false;
        for (;;) {
            // Node 的前驱为 p
            final Node p = node.predecessor();
            // p 是 head 并且 node 抢到了资源，那么 node 里的线程可以执行了，将 node 设置为 head，等它执行完后，该 node 的作用变成虚拟头节点
            if (p == head && tryAcquire(arg)) {
                /*
                private void setHead(Node node) {
                    head = node;
                    node.thread = null;
                    node.prev = null;
                }
                */
                setHead(node);
                p.next = null; // help GC
                failed = false;
                return interrupted;
            }
            // p 不是 head 或者是 head 但是 node 抢资源失败，如果 p 为 SIGNAL 状态，将 node 的线程阻塞；否则设置 p 的状态为 SIGNAL 状态
            if (shouldParkAfterFailedAcquire(p, node) &&
                // 阻塞线程，然后用interrupted()重置中断位，并且返回它的中断状态
                /*
                private final boolean parkAndCheckInterrupt() {
                    LockSupport.park(this);
                    return Thread.interrupted();
                }
                */
                parkAndCheckInterrupt())
                interrupted = true;
        }
    } finally {
        if (failed)
            cancelAcquire(node);
    }
}
```



### shouldParkAfterFailedAcquire

作用：

1. 清理 Node
2. 将 Node 状态转化为 `SIGNAL` 状态

```java
/**
 * Checks and updates status for a node that failed to acquire.
 * Returns true if thread should block. This is the main signal
 * control in all acquire loops.  Requires that pred == node.prev.
 */
private static boolean shouldParkAfterFailedAcquire(Node pred, Node node) {
    int ws = pred.waitStatus;
    if (ws == Node.SIGNAL)
        /*
         * This node has already set status asking a release
         * to signal it, so it can safely park.
         * 当 pred 处于 SIGNAL 状态，表示 node 可以被阻塞
         */
        return true;
    if (ws > 0) {
        // 如果 pred 为 CANCELLED 状态，则重新链接 Node 的 prev
        do {
            node.prev = pred = pred.prev;
        } while (pred.waitStatus > 0);
        pred.next = node;
    } else {
        // 尝试设置 pred 为 SIGNAL
        /*
         * waitStatus must be 0 or PROPAGATE.  Indicate that we
         * need a signal, but don't park yet.  Caller will need to
         * retry to make sure it cannot acquire before parking.
         */
        compareAndSetWaitStatus(pred, ws, Node.SIGNAL);
    }
    return false;
}
```



## release相关方法

### release

```java
public final boolean release(int arg) {
    if (tryRelease(arg)) {
        Node h = head;
        // 成功释放资源时，唤醒 CLH 队列里的 Node，一个 Node 能被唤醒的条件是它的 prev 节点处于 SIGNAL 状态
        if (h != null && h.waitStatus != 0)
            // waitStatus 不为0，说明存在阻塞的线程，此外也不可能为1
            unparkSuccessor(h);
        return true;
    }
    return false;
}
```



### unparkSuccessor

作用：唤醒机制

```java
private void unparkSuccessor(Node node) {
    int ws = node.waitStatus;
    if (ws < 0)
        // 在 release 方法中， node 是 head ，将 waitStatus 置为0
        compareAndSetWaitStatus(node, ws, 0);

    // 寻找后继节点。如果后继节点是 null 或者是 CANCELLED 状态，从 tail 开始向前找到离 head 最近的非 CANCELLED 状态的 Node
    Node s = node.next;
    if (s == null || s.waitStatus > 0) {
        s = null;
        for (Node t = tail; t != null && t != node; t = t.prev)
            if (t.waitStatus <= 0)
                s = t;
    }
    if (s != null)
        // 唤醒该节点内部的线程
        LockSupport.unpark(s.thread);
}
```



## 总结

阻塞机制由 `acquireQueued` 方法实现，唤醒机制由 `unparkSuccessor` 方法实现

- 阻塞机制：队首的 Node 有机会和其他线程竞争，如果 Node 抢到资源，则将 Node 设置为 head；如果 Node 未能抢到资源且 head 的 `waitStatus` 是0，则设置为 `SIGNAL`；如果 head 的`waitStatus` 是 `SIGNAL`，则阻塞 Node。此外它做的另一个工作是清理 head 和当前 Node 之间处于 `CANCELLED` 状态的 Node （`shouldParkAfterFailedAcquire`）

  阻塞过程：

  1. 创建 Node 对象，存放 Thread 对象
  2. 在尾部插入 Node
     - 如果 tail 不是 null，尝试 CAS 插入到尾部，若成功返回 Node 对象；失败进入 `enq` 方法用 CAS 插入尾部直到成功
     - 如果 tail 为 null，则进入 `enq` 方法，先用 CAS 初始化 head，再用 CAS 插入尾部直到成功
  3. 在队列中等待获取资源
     - 如果前继节点是 head 并且 Node 内部的线程获得了资源，将当前 Node 设置为 head
     - 否则，如果前继节点的状态是 `SIGNAL` 则去阻塞线程；如果是取消状态，则清理取消的 Node；否则CAS 操作将状态设置为 `SIGNAL` 

- 唤醒机制：一个线程释放资源时，将 head 的 `waitStatus` 设置为0，然后去唤醒 CLH 队列里第一个处于非 `CANCELLED` 状态的 Node。通常 `head.next` 就是符合条件的 Node，如果不符合，再从 tail 开始反向查找，使用 `head.next` 大大减少了反向查找的次数

  唤醒过程：

  1. 成功释放资源后，如果 head 不为 null 且状态不为0，执行唤醒操作
  2. 将 head 的状态设置为0，唤醒线程

- 阻塞线程之前，需要把它的前驱 Node 的 `waitStatus` 设置为 `SIGNAL` 状态；唤醒线程之前，需要把它的前驱 Node 的 `waitStatus` 设置为0。因此可以知道，除了 head.next 外，其他已经在 CLH 队列中的 Node 的 prev 必然都是 `SIGNAL` 状态

