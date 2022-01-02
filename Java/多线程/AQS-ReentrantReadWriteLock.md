# ReentrantReadWriteLock

## 引言
面试时被问到读写锁，根据名字我还以为是基于ReentrantLock来实现的，其实并不然，它是基于 AQS 实现的，**Reentrant**表示的是读锁、写锁是可重入的。

## Javadoc的简单翻译

1. 支持非公平模式和公平模式

   非公平模式：吞吐量高于非公平锁，后面的线程可能早于前面的线程获得锁（例子1，读锁被占用，reader 在 writer 之后到达，writer 还未进入 CLH 队列时，后到的 reader 可以获得读锁；例子2，锁释放时，一个 writer 在队首等待，另一个 writer 同时过来了，新到的 writer 有机会获得写锁）

   公平模式：reader 能获得读锁的前提是，写锁没有被占用，且没有 writer 在等待；writer 能获得写锁的前提是，写锁和读锁没有被占用（意味着没有 reader 或者 writer 在等待）

   **读锁和写锁的 tryLock 方法和 ReentrantLock 的 tryLock 方法一致，是非公平抢锁**

2. 重入

   reader 和 writer 都支持重入

   writer 可以获得读锁，但 reader 不能获得写锁

3. 锁降级：写锁降级为读锁

   获得写锁后，再次获得读锁然后释放写锁。不支持锁升级，即读锁升级为写锁

   ```java
   class CachedData {
       Object data;
       volatile boolean cacheValid;
       final ReentrantReadWriteLock rwl = new ReentrantReadWriteLock();
   	// 重入和锁降级示例
       void processCachedData() {
           rwl.readLock().lock();
           if (!cacheValid) {
               // reader 不能获得写锁
               // Must release read lock before acquiring write lock
               rwl.readLock().unlock();
               rwl.writeLock().lock();
               try {
                   // Recheck state because another thread might have
                   // acquired write lock and changed state before we did.
                   if (!cacheValid) {
                       data = ...
                           cacheValid = true;
                   }
                   // Downgrade by acquiring read lock before releasing write lock
                   rwl.readLock().lock();
               } finally {
                   rwl.writeLock().unlock(); // Unlock write, still hold read
               }
           }
   
           try {
               use(data);
           } finally {
               rwl.readLock().unlock();
           }
       }
   }
   ```

   

4. 可中断

5. 写锁支持 Condition

6. 提供方法来判断锁的持有和竞争状态

## Sync类

### 属性

```java
// 因为 AQS 中的 state 是 int 类型的，因此在Sync中，低16位表示写锁的重入次数，高16位表示 reader 的总共重入次数
static final int SHARED_SHIFT   = 16;
static final int SHARED_UNIT    = (1 << SHARED_SHIFT);
static final int MAX_COUNT      = (1 << SHARED_SHIFT) - 1;
static final int EXCLUSIVE_MASK = (1 << SHARED_SHIFT) - 1;

// 记录 reader 的重入次数
static final class HoldCounter {
    int count = 0;
    // Use id, not reference, to avoid garbage retention
    final long tid = getThreadId(Thread.currentThread());
}

static final class ThreadLocalHoldCounter
    extends ThreadLocal<HoldCounter> {
    public HoldCounter initialValue() {
        return new HoldCounter();
    }
}

// 当前线程读锁的重入次数，放在 ThreadLocal 中，当次数为0时，会调用 remove 
private transient ThreadLocalHoldCounter readHolds;

// HoldCounter 的缓存，它缓存的是上一次获得读锁的那个线程的重入次数。为何缓存的原因：普遍存在的情况是，上一个获得锁的线程马上会释放锁，通过缓存减少了去 ThreadLocal 里查找的开销
private transient HoldCounter cachedHoldCounter;

// 第一个获得读锁的线程，以及它的重入次数
private transient Thread firstReader = null;
private transient int firstReaderHoldCount
```



### tryAcquire（独占模式，writer 调用）

```java
protected final boolean tryAcquire(int acquires) {
    /*
     * Walkthrough:
     * 1. If read count nonzero or write count nonzero
     *    and owner is a different thread, fail.
     * 2. If count would saturate, fail. (This can only
     *    happen if count is already nonzero.)
     * 3. Otherwise, this thread is eligible for lock if
     *    it is either a reentrant acquire or
     *    queue policy allows it. If so, update state
     *    and set owner.
     */
    Thread current = Thread.currentThread();
    // 获得 state 和 writer 的重入次数
    int c = getState();
    int w = exclusiveCount(c);
    if (c != 0) {
        // (Note: if c != 0 and w == 0 then shared count != 0)，即有 reader 获得了读锁
        // if c != 0 and w != 0，表示有 writer 获得了写锁，如果不是当前线程获得了写锁，则失败
        if (w == 0 || current != getExclusiveOwnerThread())
            return false;
        if (w + exclusiveCount(acquires) > MAX_COUNT)
            throw new Error("Maximum lock count exceeded");
        // Reentrant acquire，增加重入次数
        setState(c + acquires);
        return true;
    }
    // c == 0的情况，表示资源空闲
    // writerShouldBlock()对于非公平锁来说，资源空闲就应该去抢锁，而不会管你 CLH 队列队首是 writer 还是 reader。因此它直接返回false，CAS 抢锁
    // writerShouldBlock()对于公平锁来说，如果 CLH 队列中没有线程在排队，才会 CAS 抢锁
    if (writerShouldBlock() ||
        !compareAndSetState(c, c + acquires))
        return false;
    setExclusiveOwnerThread(current);
    return true;
}
```



### tryRelease（writer 释放资源）

```java
protected final boolean tryRelease(int releases) {
    if (!isHeldExclusively())
        throw new IllegalMonitorStateException();
    int nextc = getState() - releases;
    // 减去重入次数后如果为0，可以释放写锁
    boolean free = exclusiveCount(nextc) == 0;
    if (free)
        setExclusiveOwnerThread(null);
    setState(nextc);
    return free;
}
```



### tryAcquireShared（共享模式，reader 调用）

```java
protected final int tryAcquireShared(int unused) {
    /*
     * Walkthrough:
     * 1. If write lock held by another thread, fail.
     * 2. Otherwise, this thread is eligible for
     *    lock wrt state, so ask if it should block
     *    because of queue policy. If not, try
     *    to grant by CASing state and updating count.
     *    Note that step does not check for reentrant
     *    acquires, which is postponed to full version
     *    to avoid having to check hold count in
     *    the more typical non-reentrant case.
     * 3. If step 2 fails either because thread
     *    apparently not eligible or CAS fails or count
     *    saturated, chain to version with full retry loop.
     */
    Thread current = Thread.currentThread();
    // 获得 state
    int c = getState();
    // 如果 writer 的重入次数不为0，有 writer 获得了写锁，因为 writer 可以重入读锁，因此要判断是否是同一个线程，如果不是同一个线程则失败，否则获得写锁的线程和请求获得读锁的线程是同一个线程，可以去获得读锁
    if (exclusiveCount(c) != 0 &&
        getExclusiveOwnerThread() != current)
        return -1;
    // 步骤2
    int r = sharedCount(c);
    // readerShouldBlock()对于非公平锁来说，判断在 CLH 队列队首的线程是否是独占模式，如果是独占模式则 reader 去排队，否则的话 reader 可以获得读锁
    // readerShouldBlock()对于公平锁来说，只需判断 CLH 队列是否有线程在等待
    if (!readerShouldBlock() &&
        r < MAX_COUNT &&
        compareAndSetState(c, c + SHARED_UNIT)) {
        // r == 0表示没有其他 reader 获得读锁，或者是当前线程已经获得了写锁
        if (r == 0) {
            firstReader = current;
            firstReaderHoldCount = 1;
        } else if (firstReader == current) {
        	// 重入
            firstReaderHoldCount++;
        } else {
            // 有其他 reader 获得了读锁
            HoldCounter rh = cachedHoldCounter;
            if (rh == null || rh.tid != getThreadId(current))
                cachedHoldCounter = rh = readHolds.get();
            // 当上一次 rh.count == 0 时会调用 ThreadLocal 的 remove 方法移除 rh，所以需要重新设置
            else if (rh.count == 0)
                readHolds.set(rh);
            rh.count++;
        }
        return 1;
    }
    // 重试
    return fullTryAcquireShared(current);
}
```



### fullTryAcquireShared（reader 重试）

```java
final int fullTryAcquireShared(Thread current) {
    /*
     * This code is in part redundant with that in
     * tryAcquireShared but is simpler overall by not
     * complicating tryAcquireShared with interactions between
     * retries and lazily reading hold counts.
     */
    HoldCounter rh = null;
    for (;;) {
        int c = getState();
        if (exclusiveCount(c) != 0) {
            if (getExclusiveOwnerThread() != current)
                return -1;
            // 当前线程获得了写锁，可以 CAS 抢读锁
            // else we hold the exclusive lock; blocking here
            // would cause deadlock.
        } else if (readerShouldBlock()) {
            // Make sure we're not acquiring read lock reentrantly
            // 当前 reader 是第一个获得读锁的线程，有机会重入读锁
            if (firstReader == current) {
                // assert firstReaderHoldCount > 0;
            } else {
                // 当前 reader 不是第一个 reader，需要查看自己的重入次数，如果等于0则让 reader 准备进 CLH 队列，否则还有机会重入读锁
                if (rh == null) {
                    rh = cachedHoldCounter;
                    if (rh == null || rh.tid != getThreadId(current)) {
                        rh = readHolds.get();
                        if (rh.count == 0)
                            readHolds.remove();
                    }
                }
                if (rh.count == 0)
                    return -1;
            }
        }
        if (sharedCount(c) == MAX_COUNT)
            throw new Error("Maximum lock count exceeded");
        // CAS 重试，类似于 tryAcquireShared
        if (compareAndSetState(c, c + SHARED_UNIT)) {
            if (sharedCount(c) == 0) {
                firstReader = current;
                firstReaderHoldCount = 1;
            } else if (firstReader == current) {
                firstReaderHoldCount++;
            } else {
                if (rh == null)
                    rh = cachedHoldCounter;
                if (rh == null || rh.tid != getThreadId(current))
                    rh = readHolds.get();
                else if (rh.count == 0)
                    readHolds.set(rh);
                rh.count++;
                cachedHoldCounter = rh; // cache for release
            }
            return 1;
        }
    }
}
```



### tryReleaseShared（reader 释放资源）

```java
protected final boolean tryReleaseShared(int unused) {
    Thread current = Thread.currentThread();
    // 第一个获得读锁的线程是当前线程的话，要么将重入次数减1，要么将 firstReader 置为 null
    if (firstReader == current) {
        // assert firstReaderHoldCount > 0;
        if (firstReaderHoldCount == 1)
            firstReader = null;
        else
            firstReaderHoldCount--;
    } else {
        // 其他线程是第一个 reader，则获得当前线程的计数，将其减1，若减完后为0，则调用 ThreadLocal的 remove 
        HoldCounter rh = cachedHoldCounter;
        if (rh == null || rh.tid != getThreadId(current))
            rh = readHolds.get();
        int count = rh.count;
        if (count <= 1) {
            readHolds.remove();
            if (count <= 0)
                throw unmatchedUnlockException();
        }
        --rh.count;
    }
    // CAS 重试释放资源
    for (;;) {
        int c = getState();
        int nextc = c - SHARED_UNIT;
        if (compareAndSetState(c, nextc))
            // Releasing the read lock has no effect on readers,
            // but it may allow waiting writers to proceed if
            // both read and write locks are now free.
            return nextc == 0;
    }
}
```



### tryWriteLock（非公平）

```java
/**
 * Performs tryLock for write, enabling barging in both modes.
 * This is identical in effect to tryAcquire except for lack
 * of calls to writerShouldBlock.
 */
final boolean tryWriteLock() {
    Thread current = Thread.currentThread();
    int c = getState();
    if (c != 0) {
        int w = exclusiveCount(c);
        if (w == 0 || current != getExclusiveOwnerThread())
            return false;
        if (w == MAX_COUNT)
            throw new Error("Maximum lock count exceeded");
    }
    // 和 tryAcquire 的区别是，这里没有调用 writerShouldBlock()。非公平模式
    if (!compareAndSetState(c, c + 1))
        return false;
    setExclusiveOwnerThread(current);
    return true;
}
```



### tryReadLock（非公平）

```java
/**
 * Performs tryLock for read, enabling barging in both modes.
 * This is identical in effect to tryAcquireShared except for
 * lack of calls to readerShouldBlock.
 */
final boolean tryReadLock() {
    Thread current = Thread.currentThread();
    // 区别1：如果 CAS 失败则不断重试
    for (;;) {
        int c = getState();
        if (exclusiveCount(c) != 0 &&
            getExclusiveOwnerThread() != current)
            return false;
        int r = sharedCount(c);
        // 区别2：不调用 readerShouldBlock()。非公平模式
        if (r == MAX_COUNT)
            throw new Error("Maximum lock count exceeded");
        if (compareAndSetState(c, c + SHARED_UNIT)) {
            if (r == 0) {
                firstReader = current;
                firstReaderHoldCount = 1;
            } else if (firstReader == current) {
                firstReaderHoldCount++;
            } else {
                HoldCounter rh = cachedHoldCounter;
                if (rh == null || rh.tid != getThreadId(current))
                    cachedHoldCounter = rh = readHolds.get();
                else if (rh.count == 0)
                    readHolds.set(rh);
                rh.count++;
            }
            return true;
        }
    }
}
```





## 总结

1. 每个 reader 的重入次数通过 ThreadLocal 由其自身维护

2. 读锁总的重入次数由 state 的高16位维护，写锁的重入次数由 state 的低16位维护

3. 锁分为公平和非公平两种方式

   **对于公平模式来说，只要 CLH 队列中有线程在等待，如果 reader 和 writer 重入次数为0，则都会去队列中排队**

   **对于非公平模式来说，当资源可用时，writer 不会看队列中是否有线程在等待，执行 CAS 抢锁，CAS 失败后会进入等待队列；reader 会看 CLH 队列中的第一个线程是否是独占模式，是的话且自己的重入次数为0，才会去排队，否则只要 CAS 成功就可以设置为工作线程**

4. 考个小问题：现在有一个读线程 reader 和一个写线程 writer，他们分别申请读锁和写锁，过程会是怎样的？

   reader 先获得 state 和写锁的重入次数，如果写锁的重入次数不等于0且当前线程和获得写锁的线程不是同一个线程，则 reader 进 CLH 队列；接着，如果满足三个条件：`readerShouldBlock`是 false 、总的重入次数小于最大值（65535）、CAS 获得读锁成功，则更新自身的重入次数；以上有一个条件不满足则调用`fullTryAcquireShared`。

   对于`readerShouldBlock`，如果是非公平模式，它会去看 CLH 队列中的第一个线程是否是独占模式，如果是的话返回 true；如果是公平模式，只要队列中有线程在等待就返回 true。

   对于`fullTryAcquireShared`，如果写锁被占用且不是当前线程占用，那么 reader 进入 CLH 队列；如果写锁没被占用但是`readerShouldBlock`返回 true，如果当前线程的重入次数为0，则进入 CLH 队列；如果没有进入 CLH 队列，则调用 CAS 抢读锁，CAS 成功的话就更新自身的重入状态，否则的话重新执行这些步骤。
   
   
   
   writer 先获得 state 和写锁的重入次数，如果 state 不为0但是重入次数为0，表示有读锁占用资源，writer 进入 CLH 队列；如果 state 不为0且重入次数也不为0，如果占用写锁的线程和当前线程不是同一个线程，则 writer 进入 CLH 队列，是同一个线程的话就更新重入次数。如果 state 为0，表示读锁和写锁都没有被占用，如果`writerShouldBlock`返回 true 的话，则 writer 进入 CLH 队列，否则进行 CAS 抢写锁，失败进入 CLH 队列，成功则设置当前线程为工作线程。
   
   对于`writerShouldBlock`，如果是非公平模式，它直接返回 false，因为当前资源空闲，writer 有资格抢写锁；如果是公平模式，只要队列中有线程在等待就返回 true。

