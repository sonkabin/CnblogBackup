# AQS源码阅读-acquireShared/releaseShared

## acquireShared相关方法

### acquireShared

```java
// 获取共享资源，如果未能获得，则让线程入队
public final void acquireShared(int arg) {
    if (tryAcquireShared(arg) < 0)
        doAcquireShared(arg);
}
```



### doAcquireShared

作用：阻塞机制

```java
/**
 * Acquires in shared uninterruptible mode.
 * 共享、不可中断模式，可类比于 acquireQueued 方法
 */
private void doAcquireShared(int arg) {
    final Node node = addWaiter(Node.SHARED);
    boolean failed = true;
    try {
        boolean interrupted = false;
        for (;;) {
            final Node p = node.predecessor();
            if (p == head) {
                /*
                tryAcquireShared：以共享模式 acquire，它会去看 state 是否允许被 acquire，如果可以的话就 acquire
                1) CountDownLatch：获取操作表示，等待并直到闭锁状态结束（state == 0）
                protected int tryAcquireShared(int acquires) {
                    return (getState() == 0) ? 1 : -1;
                }
                2) Semaphore：提供公平和非公平的实现方式，这里放公平方式
                protected int tryAcquireShared(int acquires) {
                    for (;;) {
                        if (hasQueuedPredecessors())
                            return -1;
                        int available = getState();
                        int remaining = available - acquires;
                        // 返回剩余的许可
                        if (remaining < 0 ||
                            compareAndSetState(available, remaining))
                            return remaining;
                    }
                }
                */
                int r = tryAcquireShared(arg);
                if (r >= 0) {
                    setHeadAndPropagate(node, r);
                    p.next = null; // help GC
                    if (interrupted)
                        selfInterrupt();
                    failed = false;
                    return;
                }
            }
            // 如果 p 不是 head， 或者是 head 但是未能成功 acquire，则需要阻塞该线程
            // shouldParkAfterFailedAcquire 方法中，如果 p 为 SIGNAL 状态，将 node 的线程阻塞；否则将状态为0或者是 PROPAGATE 状态的 p 设置为 SIGNAL 状态，准备进行阻塞
            if (shouldParkAfterFailedAcquire(p, node) &&
                parkAndCheckInterrupt())
                interrupted = true;
        }
    } finally {
        if (failed)
            cancelAcquire(node);
    }
}
```



### setHeadAndPropagate

作用：

1. 设置新的 head
2. `releaseShare` 传播

```java
/**
 * Sets head of queue, and checks if successor may be waiting
 * in shared mode, if so propagating if either propagate > 0 or
 * PROPAGATE status was set.
 * 在调用该方法之前，都会检查 propagate，只有大于等于0，才会调用该方法
 */
private void setHeadAndPropagate(Node node, int propagate) {
    Node h = head; // Record old head for check below
    setHead(node);
    /*
     * Try to signal next queued node if:
     *   Propagation was indicated by caller,
     *     or was recorded (as h.waitStatus either before
     *     or after setHead) by a previous operation
     *     (note: this uses sign-check of waitStatus because
     *      PROPAGATE status may transition to SIGNAL.)
     * and
     *   The next node is waiting in shared mode,
     *     or we don't know, because it appears null
     *
     * The conservatism in both of these checks may cause
     * unnecessary wake-ups, but only when there are multiple
     * racing acquires/releases, so most need signals now or soon
     * anyway.
     */
    /*
    唤醒下一个线程的情况包括：(在独占模式中，设置好 head 后，不会去唤醒下一个线程)
    1）propagate 大于0，唤醒下一个线程；
    2）propagate 等于0，但是其他线程将 h（旧的 head）的状态改为了 PROPAGATE 状态
       h == null 的判断是防止空指针异常。 h.waitStatus < 0，表示 h 处于 SIGNAL 或 PROPAGATE 状态，一般情况下是 PROPAGATE 状态，因为在 doReleaseShared 方法中 h 状态变化是 SIGNAL -> 0 -> PROPAGATE。那么为什么 SIGNAL 状态也要唤醒呢？这是因为在 doAcquireShared 中，第一次没有获得足够的资源时，shouldParkAfterFailedAcquire 将 PROPAGATE 状态转换成 SIGNAL，准备阻塞线程，但是第二次进入本方法时发现资源刚好够，而此时 h 的状态是 SIGNAL 状态
       (h = head) == null 是再次检查
    */
    if (propagate > 0 || h == null || h.waitStatus < 0 ||
        (h = head) == null || h.waitStatus < 0) {
        Node s = node.next;
        /*
        如果 next node 是 SHARED 模式，或者是 null，则执行传播操作
        final boolean isShared() {
            return nextWaiter == SHARED;
        }
        */
        if (s == null || s.isShared())
            doReleaseShared();
    }
}
```



## releaseShared相关方法

### releaseShared

```java
public final boolean releaseShared(int arg) {
    if (tryReleaseShared(arg)) {
        // 唤醒后继节点以及设置传播状态
        doReleaseShared();
        return true;
    }
    return false;
}
```



### doReleaseShared

作用：

1. 将 `SIGNAL` 状态设置为0，或者将0设置为 `PROPAGATE` 
2. 调用 `unparkSuccessor` 去唤醒

```java
/**
 * Release action for shared mode -- signals successor and ensures
 * propagation. (Note: For exclusive mode, release just amounts
 * to calling unparkSuccessor of head if it needs signal.)
 */
private void doReleaseShared() {
    /*
    * Ensure that a release propagates, even if there are other
    * in-progress acquires/releases.  This proceeds in the usual
    * way of trying to unparkSuccessor of head if it needs
    * signal. But if it does not, status is set to PROPAGATE to
    * ensure that upon release, propagation continues.
    * Additionally, we must loop in case a new node is added
    * while we are doing this. Also, unlike other uses of
    * unparkSuccessor, we need to know if CAS to reset status
    * fails, if so rechecking.
    * 共享模式存在多个线程，需要 CAS 来观察操作是否成功
    */
    for (;;) {
        Node h = head;
        if (h != null && h != tail) {
            int ws = h.waitStatus;
            if (ws == Node.SIGNAL) {
                // head 是 SIGNAL 状态，尝试将状态设为0，设置成功的话唤醒下一个 Node
                if (!compareAndSetWaitStatus(h, Node.SIGNAL, 0))
                    continue;            // loop to recheck cases
                unparkSuccessor(h);
            }
            // 状态为0表示已经有一个线程将 head 的状态设置为0了，当前线程尝试设置 PROPAGATE 状态
            else if (ws == 0 &&
                     !compareAndSetWaitStatus(h, 0, Node.PROPAGATE))
                continue;                // loop on failed CAS
        }
        // 共享模式，可能有多个线程在操作，如果 head 发生变化，应该去唤醒下一个 Node
        if (h == head)                   // loop if head changed
            break;
    }
}
```



## 理解

### 为什么需要 PROPAGETE 状态？

`PROPAGETE` 表示需要将 `releaseShared` 传播给其他 Node。为什么需要将 `releaseShared` 传播呢？考虑有10个线程，3个资源，假设当前有3个线程在运行，那么有7个线程在 CLH 队列中处于阻塞状态（`node.prev`的状态都是 `SIGNAL`）。不考虑外部有新的线程过来，有以下情况：

1. 3个线程串行执行`释放资源->唤醒线程->设置 head`，那么每个线程串行着将 head 的状态位修改为0，不会在 `setHeadAndPropagate` 方法中调用 `doReleaseShared`

2. 3个线程同时释放资源，设3个线程分别是线程1、线程2、线程3。线程4是 CLH 队列中的第一个线程

   线程1成功将 head 的状态设置为0，线程4被唤醒。线程1看 head 是否发生变化，线程2、3重试准备将 head 的状态从0设置为 `PROPAGETE`，最终三个线程都会查看 head 是否发生变化

   - 线程4未调用 `setHead` 。线程1、2、3结束 `doReleaseShared`，多出3个资源，活跃线程数为1，且 head 的状态一定是  `PROPAGETE`。线程4通过**旧的 head **的状态，知道应该调用 `doReleaseShared` 来唤醒线程
   - 线程4已调用 `setHead` 。线程1、2、3继续尝试唤醒线程

因此，`PROPAGETE` 状态可以让活跃的线程数量尽可能达到资源的数量，以利用资源

## 总结

阻塞机制由 `doAcquireShared` 方法实现，唤醒机制由 `doReleaseShared` 方法实现

- 阻塞机制：队首的 Node 如果能获得资源，则将 Node 设置为 head，如果资源剩余数大于0或者旧 head 的状态是 `PROPAGATE`，那么就调用 `doReleaseShared` 来唤醒线程；如果 Node 未能获得资源，则 head 的 `waitStatus` 设置为 `SIGNAL`，如果下一次检查它是 `SIGNAL`，则阻塞 Node。此外它做的另一个工作是清理 head 和当前 Node 之间处于 `CANCELLED` 状态的 Node （`shouldParkAfterFailedAcquire`）
- 唤醒机制：CAS 操作将 head 的状态从 `SIGNAL` 改为0，如果改成功则调用 `unparkSuccessor` 唤醒下一个线程，以及 CAS 操作将 head 的状态从0改为 `PROPAGATE`， CAS 操作失败后继续循环。如果发现 head 的状态不是 `SIGNAL` 或者0，就去看 head 是否改变，如果改变了继续循环

