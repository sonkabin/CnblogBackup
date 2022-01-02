# AQS-Node静态内部类

## 约定

CLH 队列，在 AQS 的实现中也被称为同步队列（`SyncQueue`）

## 源码

### Node类

```java
static final class Node {
    // 共享模式和独占模式的标记
    static final Node SHARED = new Node();
    static final Node EXCLUSIVE = null;

    static final int CANCELLED =  1;
    static final int SIGNAL    = -1;
    static final int CONDITION = -2;
    static final int PROPAGATE = -3;
    /*
    status 属性用于表示状态：1）CANCELLED 和 CONDITION 状态表示当前 Node 的状态；2）SIGNAL 和 PROPAGATE 状态表示的是下一个 Node 的状态
    1. SIGNAL：当前 Node 的后继 Node 将被阻塞。当前 Node 释放锁或者被取消时，它要将后继 Node 唤醒。
    2. CANCELLED：由于超时或者中断，该 Node 中的线程处于取消状态。一旦 Node 处于取消状态，它不能再变成其他状态，取消状态的 Node 不会被阻塞
    3. CONDITION： Node 处于条件队列上。调用 await 时，会使用 nextWaiter 来链接，不在 CLH 队列中。当调用 transferred 后，如果该状态被设置为0， Node 才会进入 CLH 队列中
    4. PROPAGATE：releaseShared 操作应传播给其他的所有 Node。当 setHead 完成后，执行传播操作
    5. 状态0表示不是以上的状态。Node 创建时的默认状态
    */
    volatile int waitStatus;

    // 前驱指针。作用是：1）反向查找；2）帮助跳过处于 CANCELLED 状态的 Node
    volatile Node prev;

    // 后继指针。作用是：1）减少反向查找的次数；2）帮助 isOnSyncQueue 方法判断 Node 在同步队列（next）中还是在条件队列（nextWaiter）中，因此处于 CANCELLED 状态的 Node 的 next 指向它自己而不是 null。因为源码中的判断是如果 Node.next 不为 null，就断定它在同步队列中
    volatile Node next;
	// 指向实际的线程
    volatile Thread thread;
    /* 
    作用：
    1）实现条件等待，用 nextWaiter 链接在某个条件上等待的线程（不需要用并发队列，因为条件等待需要独占锁）；
    2）确定下一个 Node 是什么模式，如果是共享模式，则为SHARED；如果是独占模式，则为 null
    */
    Node nextWaiter;
}
```



### isOnSyncQueue

```java
// Internal support methods for Conditions。如果在条件队列上，返回 false；如果在同步队列上，返回 true
final boolean isOnSyncQueue(Node node) {
    // 如果没有 prev，说明不存在前一个 node 拥有当前 node 的控制信息，不可能在同步队列中
    if (node.waitStatus == Node.CONDITION || node.prev == null)
        return false;
   	// 让处于 CANCELLED 状态的 node 的 next 指向自身，除了 tail 外其他 node 的 next 都不会等于 null
    if (node.next != null) // If has successor, it must be on queue
        return true;
    /*
     * node.prev can be non-null, but not yet on queue because
     * the CAS to place it on queue can fail. So we have to
     * traverse from tail to make sure it actually made it.  It
     * will always be near the tail in calls to this method, and
     * unless the CAS failed (which is unlikely), it will be
     * there, so we hardly ever traverse much.
     */
    /*
    node.prev 不会是null，但是可能因为 CAS 失败，node 不在同步队列中的可能性还是存在的。所以从tail 开始往前扫描。
    private boolean findNodeFromTail(Node node) {
        Node t = tail;
        for (;;) {
            if (t == node)
                return true;
            if (t == null)
                return false;
            t = t.prev;
        }
    }
    */
    return findNodeFromTail(node);
}
```



