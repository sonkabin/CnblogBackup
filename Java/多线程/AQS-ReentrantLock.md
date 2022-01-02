# AQS-ReentrantLock

## 基类锁Sync

```java
abstract static class Sync extends AbstractQueuedSynchronizer {
    private static final long serialVersionUID = -5179523762034025860L; 
    
    // 由子类实现公平和非公平的锁
    abstract void lock();

    // 非公平抢锁方式
    final boolean nonfairTryAcquire(int acquires) {
        final Thread current = Thread.currentThread();
        int c = getState();
        if (c == 0) {
            // 锁没有被占用，则 CAS 抢锁
            if (compareAndSetState(0, acquires)) {
                setExclusiveOwnerThread(current);
                return true;
            }
        }
        // 增加重入次数
        else if (current == getExclusiveOwnerThread()) {
            int nextc = c + acquires;
            if (nextc < 0) // overflow
                throw new Error("Maximum lock count exceeded");
            setState(nextc);
            return true;
        }
        return false;
    }

    protected final boolean tryRelease(int releases) {
        // 减去重入次数
        int c = getState() - releases;
        if (Thread.currentThread() != getExclusiveOwnerThread())
            throw new IllegalMonitorStateException();
        boolean free = false;
        // 状态为0时释放锁
        if (c == 0) {
            free = true;
            setExclusiveOwnerThread(null);
        }
        setState(c);
        return free;
    }

    protected final boolean isHeldExclusively() {
        // While we must in general read state before owner,
        // we don't need to do so to check if current thread is owner
        return getExclusiveOwnerThread() == Thread.currentThread();
    }
	// AQS 提供的 Condition 实现
    final ConditionObject newCondition() {
        return new ConditionObject();
    }

    // Methods relayed from outer class

    final Thread getOwner() {
        return getState() == 0 ? null : getExclusiveOwnerThread();
    }
	// 重入次数
    final int getHoldCount() {
        return isHeldExclusively() ? getState() : 0;
    }

    final boolean isLocked() {
        return getState() != 0;
    }

    private void readObject(java.io.ObjectInputStream s)
        throws java.io.IOException, ClassNotFoundException {
        s.defaultReadObject();
        setState(0); // reset to unlocked state
    }
}
```



## 非公平锁NonfairSync

```java
static final class NonfairSync extends Sync {
    private static final long serialVersionUID = 7316153563782823691L;

    final void lock() {
        // 如果锁没有被占用，CAS 抢锁
        if (compareAndSetState(0, 1))
            setExclusiveOwnerThread(Thread.currentThread());
        else
            // CAS 失败进入 acquire
            acquire(1);
    }
	// acquire 方法会调用 tryAcquire
    protected final boolean tryAcquire(int acquires) {
        return nonfairTryAcquire(acquires);
    }
}
```



## 公平锁FairSync

```java
static final class FairSync extends Sync {
    private static final long serialVersionUID = -3000897897090466540L;

    final void lock() {
        acquire(1);
    }

    /**
     * Fair version of tryAcquire.  Don't grant access unless
     * recursive call or no waiters or is first.
     */
    protected final boolean tryAcquire(int acquires) {
        final Thread current = Thread.currentThread();
        int c = getState();
        if (c == 0) {
            // 尽管锁没有占用，还要先判断 CLH 队列中是否有等待的线程，如果有则不抢锁，没有则 CAS 抢锁
            if (!hasQueuedPredecessors() &&
                compareAndSetState(0, acquires)) {
                setExclusiveOwnerThread(current);
                return true;
            }
        }
        // 增加重入次数
        else if (current == getExclusiveOwnerThread()) {
            int nextc = c + acquires;
            if (nextc < 0)
                throw new Error("Maximum lock count exceeded");
            setState(nextc);
            return true;
        }
        return false;
    }
}
```



## 总结

1. 默认是非公平锁

2. 非公平锁的过程是：

   1. 直接 CAS 抢锁，成功则设置自己为工作线程，否则进入 `acquire` 方法，再进到 `tryAcquire` 方法；
   2. 如果锁没有被占用，则 CAS 抢锁，成功则设置自己为工作线程；
   3. 如果锁被占用且自己是锁的拥有者，则增加重入次数；
   4. 不满足以上情况则进入 CLH 队列中

3. 公平锁的过程是：

   1. 如果锁没有被占用，且 CLH 队列中没有阻塞的线程，则 CAS 抢锁，成功则设置自己为工作线程；
   2. 如果锁被占用且自己是锁的拥有者，则增加重入次数；
   3. 不满足以上情况则进入 CLH 队列中

4. `tryLock` 方法的特殊性

   ```
   public boolean tryLock() {
       return sync.nonfairTryAcquire(1);
   }
   ```

   可知，它用的是非公平方式抢锁，即使是在公平锁模式下，一个线程调用该方法，仍然是非公平抢锁。要想让公平锁实现公平。如果想让公平锁执行公平行为，则可以用 `tryLock(0, TimeUnit.SECONDS)`

   