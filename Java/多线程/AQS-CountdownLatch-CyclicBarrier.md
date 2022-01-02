# AQS源码-CountdownLatch-CyclicBarrier

## CountdownLatch

### 实现 AQS 的 Sync

```java
private static final class Sync extends AbstractQueuedSynchronizer {
    private static final long serialVersionUID = 4982264981922014374L;

    Sync(int count) {
        setState(count);
    }

    int getCount() {
        return getState();
    }
	// state 等于0时返回1，由 await 方法调用
    protected int tryAcquireShared(int acquires) {
        return (getState() == 0) ? 1 : -1;
    }
	// countDown 方法开始，调用链为 countDown -> releaseShared -> tryReleaseShared。将 state 减1。返回 true 时会调用 doReleaseShared 去唤醒线程
    protected boolean tryReleaseShared(int releases) {
        // Decrement count; signal when transition to zero
        for (;;) {
            int c = getState();
            if (c == 0)
                return false;
            int nextc = c-1;
            if (compareAndSetState(c, nextc))
                return nextc == 0;
        }
    }
}
```



### await

```java
public void await() throws InterruptedException {
    sync.acquireSharedInterruptibly(1);
}

public final void acquireSharedInterruptibly(int arg)
    throws InterruptedException {
    if (Thread.interrupted())
        throw new InterruptedException();
    if (tryAcquireShared(arg) < 0)
        // 和 doAcquireShared 大致上一样，区别是在阻塞线程后如果中断状态被设置了，则抛出中断异常
        doAcquireSharedInterruptibly(arg);
}
```



### countDown

```java
public void countDown() {
    sync.releaseShared(1);
}
```



## CyclicBarrier

内部用 `ReentrantLock` 和 `Condition` 实现

```java
/** The lock for guarding barrier entry */
private final ReentrantLock lock = new ReentrantLock();
/** Condition to wait on until tripped */
private final Condition trip = lock.newCondition();
/** The number of parties 用于重置状态*/
private final int parties;
/* The command to run when tripped */
private final Runnable barrierCommand;
/** The current generation */
private Generation generation = new Generation();
```



### await

```java
/*
等待所有的线程到达屏障后，会打开屏障
*/
public int await() throws InterruptedException, BrokenBarrierException {
    try {
        return dowait(false, 0L);
    } catch (TimeoutException toe) {
        throw new Error(toe); // cannot happen
    }
}
```



### dowait

```java
/*
以下情况会将屏障的 broken 设置为 true，同时唤醒所有等待着的线程：
1）其他线程中断了当前线程或者中断了其他等待中的线程；
2）等待的线程因超时而苏醒；
3）执行 Runnable 时出现异常；
4）其他线程调用 reset 方法
*/
private int dowait(boolean timed, long nanos)
    throws InterruptedException, BrokenBarrierException,
TimeoutException {
    final ReentrantLock lock = this.lock;
    lock.lock();
    try {
        final Generation g = generation;

        if (g.broken)
            throw new BrokenBarrierException();
		// 线程中断时，将屏障的状态设置为 broken， 并抛出中断异常
        if (Thread.interrupted()) {
            breakBarrier();
            throw new InterruptedException();
        }
		// 最后一个到达的线程，在唤醒其他线程之前，会执行可选的 Runnable。它可以用于更新共享状态
        int index = --count;
        if (index == 0) {  // tripped
            boolean ranAction = false;
            try {
                final Runnable command = barrierCommand;
                if (command != null)
                    command.run();
                ranAction = true;
                // 唤醒其他等待的线程，并重置等待的线程数和屏障状态
                nextGeneration();
                return 0;
            } finally {
                if (!ranAction)
                    breakBarrier();
            }
        }

        // loop until tripped, broken, interrupted, or timed out
        for (;;) {
            try {
                if (!timed)
                    trip.await(); // 在 Condition 上等待
                else if (nanos > 0L)
                    nanos = trip.awaitNanos(nanos);
            } catch (InterruptedException ie) {
                if (g == generation && ! g.broken) {
                    breakBarrier();
                    throw ie;
                } else {
                    // We're about to finish waiting even if we had not
                    // been interrupted, so this interrupt is deemed to
                    // "belong" to subsequent execution.
                    Thread.currentThread().interrupt();
                }
            }

            if (g.broken)
                throw new BrokenBarrierException();
			// 当最后一个线程达到后，它重置了屏障，因此其他等待的线程在这里会发现屏障发生了变化，返回自己的 index，其中第一个到达的线程的 index 是 getParties() - 1
            if (g != generation)
                return index;
			// 设置了超时状态并且超时了
            if (timed && nanos <= 0L) {
                breakBarrier();
                throw new TimeoutException();
            }
        }
    } finally {
        lock.unlock();
    }
}
```



## 总结

- CountdownLatch用于等待事件，是一次性的；`countDown` 递减计数器，表示有一个事件已经发生；`await` 等待计数器达到0，表示所有需要等待的时间已经发生
- CyclicBarrier用于等待其他线程，可重复使用；线程到达栅栏位置将调用 `await` 方法，这个方法会阻塞直到所有线程都到达栅栏位置；还可以在构造函数中传入 `RUNNABLE`，最后到达栅栏的线程执行它

