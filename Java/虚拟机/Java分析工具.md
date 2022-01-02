## jps

列出正在运行的虚拟机进程，并显示主类名和进程id

## jstat

**运行时定位虚拟机性能问题的首选工具。**可以显示本地或远程虚拟机进程中的类装载、内存、垃圾收集、JIT编译等运行时数据

## jinfo

实时地查看和调整虚拟机的各项参数

## jmap

生成堆转储快照。也可以查询finalize执行队列、Java堆和永久代的详细信息，如空间使用率、当前用的收集器

## jstack

生成虚拟机当前时刻的线程快照（线程快照指当前虚拟机内每一条线程正在执行的方法堆栈的集合），目的是定位线程出现长时间停顿的原因（如死锁、死循环、请求外部资源长时间等待）。

## HSDIS

反汇编JIT生成的代码

## 频繁Full GC如何处理

1. `top -c`：加上`-c`显示运行该进程的命令行或者程序名。找到CPU占用量高的进程

   ```shell
   PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
   4486 skb      20   0 2682164  23004  15888 S 100.0   1.0   0:10.26 java Loop
   996 mysql     20   0 1741080 358960  35260 S   0.3  15.5   0:08.21 /usr/sbin/mysqld
   ```

   键入`1`，表示在单CPU和多行CPU之间切换显示。多行CPU显示的方式`%Cpu0, %Cpu1,`。切换成单行的表示将所有的CPU信息汇总成一行

   ```shell
   %Cpu0  :  0.0 us,  0.0 sy,  0.0 ni,100.0 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st
   %Cpu1  :  0.3 us,  0.0 sy,  0.0 ni, 99.7 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st
   # input 1
   %Cpu(s):  0.0 us,  0.0 sy,  0.0 ni,100.0 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st
   ```

   键入`P`，表示按CPU利用率从大到小排序

2. 找到最耗CPU的线程

   `top -H -p[pid]`：`-H`表示线程模式，`-p`表示监视`pid`

   `-pN1 -pN2...`

   ```shell
   top -H -p4025 -p996
   1030 mysql     20   0 1741080 358960  35260 S   0.7  15.5   0:01.29 mysqld
   4025 skb       20   0   13924   6328   4740 S   0.0   0.3   0:01.84 sshd
   996 mysql     20   0 1741080 358960  35260 S   0.0  15.5   0:02.12 mysqld
   999 mysql     20   0 1741080 358960  35260 S   0.0  15.5   0:00.19 mysqld
   1000 mysql     20   0 1741080 358960  35260 S   0.0  15.5   0:00.19 mysqld
   # ...其他线程
   ```

3. 线程id转化为16进制

   `printf "%x\n" [线程id]`

4. 生成虚拟机当前时刻的线程快照，定位线程

   `jstack PID | grep -A10 '0x[线程id]'`

   `grep`的`-A`表示匹配行后再打印`NUM`行

5. 查看GC信息

   `jstat -gcutil PID [毫秒] [打印次数]`

6. 生成堆转储快照

   `jmap -dump:format=b,file=x.bin PID`（生成当前时刻的堆转储快照）

### 实战

1. 写死循环

   ```java
   import java.util.*;
   public class Loop{
           public static void main(String...args){
                   Map<Integer, Integer> map = new HashMap<>();
                   while(true){
                           for(int i = 0; i <= 1000000; i++)
                                   map.put(i, i);
                   }
           }
   }
   ```

2. 找到对应的进程pid

   ```shell
   5748 skb       20   0 2682164 295420  16092 S 132.9  12.8   0:10.16 java Loop
   ```

3. 找到线程的id

   ```shell
    5749 skb       20   0 2682164 297708  16092 R  70.3  12.9   0:12.29 java
    5751 skb       20   0 2682164 297708  16092 S  28.9  12.9   0:07.93 java
    5750 skb       20   0 2682164 297708  16092 S  28.5  12.9   0:07.93 java
   ```

4. 线程id转化为16进制

   ```shell
   > printf "%x\n" 5748
   > 1675
   ```

5. 查看堆栈信息

   ```shell
   "main" #1 prio=5 os_prio=0 tid=0x00007fcc5c009800 nid=0x1675 runnable [0x00007fcc62b52000]
      java.lang.Thread.State: RUNNABLE
           at Loop.main(Loop.java:6)
   
   "VM Thread" os_prio=0 tid=0x00007fcc5c072800 nid=0x1678 runnable
   
   "GC task thread#0 (ParallelGC)" os_prio=0 tid=0x00007fcc5c01e800 nid=0x1676 runnable
   
   "GC task thread#1 (ParallelGC)" os_prio=0 tid=0x00007fcc5c020000 nid=0x1677 runnable
   
   "VM Periodic Task Thread" os_prio=0 tid=0x00007fcc5c0bc000 nid=0x167f waiting on condition
   ```

6. GC查看

   ```shell
     S0     S1     E      O      M     CCS      YGC     YGCT    FGC   FGCT     GCT
     0.00   0.00   0.00  52.50  51.22  52.17    446   25.771     3    1.049   26.819
     0.00  98.79  34.00  52.50  51.22  52.17    457   26.361     3    1.049   27.409
    98.79   0.00  60.00  52.50  51.22  52.17    468   26.957     3    1.049   28.006
     0.00  98.59  70.00  52.50  51.22  52.17    479   27.544     3    1.049   28.593
    98.79   3.23 100.00  52.50  51.22  52.17    491   28.140     3    1.049   29.189
   ```

   
