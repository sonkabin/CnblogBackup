## 深入剖析class文件结构

### 使用javap查看类文件

javap默认情况下显示访问权限为public、protected和默认级别的方法和字段。

选项：

- `-p`：显示private方法和字段
- `-s`：输出类型描述符签名
- `-c`：反编译，显示方法内的字节码
- `-v`：显示更多内容，如版本号、类访问权限、常量池相关信息

### 字段描述符

| 描述符       | 类型                                                         |
| ------------ | ------------------------------------------------------------ |
| B            | byte                                                         |
| C            | char                                                         |
| D            | double                                                       |
| F            | float                                                        |
| I            | int                                                          |
| J            | long                                                         |
| S            | short                                                        |
| Z            | boolean                                                      |
| L ClassName; | 引用类型，`"L" + 对象类型的全限定名 + ";"`，如`Ljava/lang/String;` |
| [            | 一维数组                                                     |

## 字节码基础

### 字节码概述

字节码使用大端序表示，即高位在前、低位在后，如字节码`getfield 00 02`，表示的是`getfield 0x00 << 8 | 0x02(getfield #2)`。

根据字节码的不同用途，可以分为以下几类：

- 加载和存储指令，如iload将一个整型值从局部变量表加载到操作数栈
- 控制和转移指令，如条件分支ifeq
- 对象操作，如创建类实例指令new
- 方法调用，如invokevirtual指令用于调用对象实例方法
- 运算指令和类型转换，如加法指令iadd
- 线程同步，如monitorenter
- 异常处理，如athrow显示抛出异常

### Java虚拟机栈和栈帧

虚拟机有两种常见的实现方式，基于栈（如Hotspot JVM）和基于寄存器（如LuaVM）：

- 基于栈的指令集架构优点是移植性更好、指令更短、实现简单，但是不能随机访问堆栈中的元素，完成相同功能所需的指令数一般比寄存器架构多，需要频繁地入栈出栈，不利于代码优化。
- 基于寄存器的指令集架构优点是速度快，可充分利用寄存器，有利于程序做速度优化，但操作数需要显式指定，指令较长。

**栈帧**

每个栈帧拥有自己的局部变量表（Local Variable）、操作数栈（Operand Stack）和指向常量池的引用。

javac添加`-g`选项生成调试信息，再通过javap可以看局部变量表。

1. 局部变量表

   ```java
   public class MyJVMTest{
   	public void foo(int id, String name){
   		String tmp = "A";
   	}
   }
   ```

   使用`javac -g MyJVMTest.java`后，执行`javap -v MyJVMTest`查看字节码，可以发现：foo方法只有两个参数，但args_size等于3，当一个实例方法被调用时，第0个局部变量是调用这个实例方法的对象引用（即this），调用`foo(2022, "a")`实际上是调用`foo(this, 2022, "a")`。

   locals表示局部变量表的大小，它不是所有局部变量的数量之和，而是与局部变量的作用域与变量类型有关：

   - 当一个局部变量作用域结束时，它占用的位置（slot）可以被接下来的局部变量复用
   - 当局部变量为long或double时，这些变量会占用两个slot

2. 操作数栈

   整个JVM指令执行的过程就是局部变量表与操作数栈之间不断加载、存储的过程。

   栈的最大深度由整个执行过程中所有时间点的最大深度决定，也就跟方法调用时需要用到的参数数量有关。调用一个实例方法会将this和所有参数入栈，调用完毕this和参数都会出栈，如果方法有返回值，则返回值入栈。

### 字节码指令

**加载和存储指令**

分为load、store、常量加载三种：

- load。将局部变量表中的变量加载到操作数栈，如iload_0将局部变量表中下标为0的int类型辨别加载到操作数栈上，根据不同的变量类型还有lload、fload、dload、aload，分别表示加载局部变量表中long、float、double、引用类型的变量。
- store。将栈顶的数据存储到局部变量表中，如istore_0将操作数栈顶的元素存储到下边为0的位置，该位置的元素类型是int，根据不同的变量类型还有lstore、fstore、dstore、astore。
- 常量加载。常见的有const、push、ldc。const、push指令将常量值直接加载到栈顶，如iconst_0将整数0加载到操作数栈上，bipush 100将int型常量100加载到操作数栈顶。ldc指令从常量池加载对应的常量到栈顶，如ldc #10将常量池中下标为10的常量数据加载到栈顶。

对于同是int型常量，加载分为多种类型的原因是为了使字节码更加紧凑：

- 若n在[-1, 5]之间，使用iconst_n的方式。操作数和操作码加一起只占一个字节，如iconst_2对应十六进制0x05。-1比较特殊，对应指令为iconst_m1(0x02)。
- 若n在[-128, 127]之间，使用bipush n的方式，操作数和操作码加一起只占两个字节，如n值为100（0x64）时，对应的字节码为bipush 100（0x1064）。
- 若n在[-32768, 32767]之间，使用sipush n的方式，操作数和操作码加一起只占三个字节，如n值为1024（0x0400）时，对应的字节码为sipush 1024（0x110400）。
- 若n在其他范围内，使用ldc的方式。

存储指令列表

| 指令名                         | 字节码    | 描述                                                         |
| ------------------------------ | --------- | ------------------------------------------------------------ |
| aconst_null                    | 0x01      | 将null放到栈顶                                               |
| iconst_m1                      | 0x02      | 将int类型的-1放到栈顶                                        |
| iconst_n                       | 0x03~0x08 | 将int类型的n（0~5）放到栈顶                                  |
| lconst_n                       | 0x09~0x0A | 将long类型的n（0~1）放到栈顶                                 |
| fconst_n                       | 0x0B~0x0D | 将float类型的n（0~2）放到栈顶                                |
| dconst_n                       | 0x0E~0x0F | 将double类型的n（0~1）放到栈顶                               |
| bipush（byte immediate push）  | 0x10      | 将 -128~127 的int类型值放到栈顶                              |
| sipush（short immediate push） | 0x11      | 将 -32768~32767 的int类型值放到栈顶                          |
| ldc（load constant）           | 0x12      | 将int、float、String类型的常量值从常量池压到栈顶             |
| ldc_w                          | 0x13      | 作用与ldc相同，不同的是ldc操作码是一个字节，只能寻址255个常量池的索引，ldc_w的操作码是两个字节，能寻址2个字节长度，可以覆盖常量池所有的值 |
| ldc2_w                         | 0x14      | 将long或double类型常量值从常量池压入栈顶，其寻址范围为两个字节 |
| Tload                          | 0x15~0x19 | 将局部变量表中指定位置的类型为T的变量加载到栈顶，T可以为i、l、f、d、a，分别表示int、long、float、double、引用类型 |
| Tload_n                        | 0x1A~0x2D | 将局部变量表中下标为n（0~3）的类型为T的变量加载到栈顶，T可以为i、l、f、d、a |
| Taload                         | 0x2E~0x35 | 将指定数组中特定位置的类型为T的变量加载到栈上，T可以为i、l、f、d、a、b、c、s，分别表示int、long、float、double、引用类型、boolean或byte、char、short |
| Tstore                         | 0x36~0x3A | 将栈顶类型为T的数据存储到局部变量表的指定位置，T可以为i、l、f、d、a |
| Tstore_n                       | 0x3B~0x4E | 将栈顶类型为T的数据存储到局部变量表下标为n（0~3）的位置，T可以为i、l、f、d、a |
| Tastore                        | 0x4F~0x56 | 将栈顶类型为T的数据存储到数组的指定位置，T可以为i、l、f、d、a、b、c、s |

**操作数栈指令**

常见的操作数栈指令有pop、dup和swap。

| 指令名  | 字节码 | 描述                                                     |
| ------- | ------ | -------------------------------------------------------- |
| pop     | 0x57   | 将栈顶数据（非long和double）出栈                         |
| pop2    | 0x58   | 弹出栈顶一个long或double类型的数据或者两个其他类型的数据 |
| dup     | 0x59   | 复制栈顶数据并将复制的数据入栈                           |
| dup_x1  | 0x5A   | 复制栈顶数据并将复制的数据插入到栈顶第二个元素之下       |
| dup_x2  | 0x5B   | 复制栈顶数据并将复制的数据插入到栈顶第三个元素之下       |
| dup2    | 0x5C   | 复制栈顶两个数据并将复制的数据入栈                       |
| dup2_x1 | 0x5D   | 复制栈顶两个数据并将复制的数据插入到栈顶第二个元素之下   |
| dup2_x2 | 0x5E   | 复制栈顶两个数据并将复制的数据插入到栈顶第三个元素之下   |
| swap    | 0x5F   | 交换栈顶两个元素                                         |

**运算和类型转换指令**

两元运算符对栈顶的两个元素操作，一元运算符对栈顶的一个元素操作。

| 运算      | int  | long | float | double |
| --------- | ---- | ---- | ----- | ------ |
| +         | iadd | ladd | fadd  | dadd   |
| -         | isub | lsub | fsub  | dsub   |
| /         | idiv | ldiv | fdiv  | ddiv   |
| *         | imul | lmul | fmul  | dmul   |
| %         | irem | lrem | frem  | drem   |
| negate(-) | ineg | lneg | fneg  | dneg   |
| &         | iand | land |       |        |
| \|        | ior  | lor  |       |        |
| ^         | ixor | lxor |       |        |

在JVM层面，boolean、char、byte、short都被当成int处理，因此无需显式转换。

|        | int  | long | float | double | byte | char | short |
| ------ | ---- | ---- | ----- | ------ | ---- | ---- | ----- |
| int    |      | i2l  | i2f   | i2d    | i2b  | i2c  | i2s   |
| long   | l2i  |      | l2f   | l2d    |      |      |       |
| float  | f2i  | f2l  |       | f2d    |      |      |       |
| double | d2i  | d2l  | d2f   |        |      |      |       |

**控制转移指令**

控制转移指令包括：

- 条件转移
- 复合条件转移：tableswitch、lookupswitch
- 无条件转移：goto、goto_w、jsr、jsr_w、ret

| 指令名       | 字节码 | 描述                                          |
| ------------ | ------ | --------------------------------------------- |
| ifeq         | 0x99   | 如果栈顶int型变量等于0（等于false时），则跳转 |
| ifne         | 0x9A   | 如果栈顶int型变量不等于0，则跳转              |
| iflt         | 0x9B   | 如果栈顶int型变量小于0，则跳转                |
| ifge         | 0x9C   | 如果栈顶int型变量大于等于0，则跳转            |
| ifgt         | 0x9D   | 如果栈顶int型变量大于0，则跳转                |
| ifle         | 0x9E   | 如果栈顶int型变量小于等于0，则跳转            |
| if_icmpeq    | 0x9F   | 比较栈顶两个int型变量，如果相等则跳转         |
| if_icmpne    | 0xA0   | 比较栈顶两个int型变量，如果不相等则跳转       |
| if_icmplt    | 0xA1   | 比较栈顶两个int型变量，如果小于则跳转         |
| if_icmpge    | 0xA2   | 比较栈顶两个int型变量，如果大于等于则跳转     |
| if_icmpgt    | 0xA3   | 比较栈顶两个int型变量，如果大于则跳转         |
| if_icmple    | 0xA4   | 比较栈顶两个int型变量，如果小于等于则跳转     |
| if_acmpeq    | 0xA5   | 比较栈顶两个引用类型变量，如果相等则跳转      |
| if_acmpne    | 0xA6   | 比较栈顶两个引用类型变量，如果不相等则跳转    |
| goto         | 0xA7   | 无条件跳转                                    |
| tableswitch  | 0xAA   | switch条件跳转，case值紧凑时使用              |
| lookupswitch | 0xAB   | switch条件跳转，case值稀疏时使用              |

**switch-case底层实现原理**

switch-case底层有两种实现，分别是tableswitch和lookupswitch。当case的值比较“紧凑”（中间有少量断层或者没有断层），会使用tableswitch，对于断层生成虚假的case进行补齐，这样可以实现O（1）时间复杂度的查找（数组形式）；否则使用lookupswitch，其将键值进行排序，因此可以用二分进行查找。

tableswitch：

```java
int choose(int i) {
    switch (i) {
        case 100: return 0;
        case 101: return 1;
        case 104: return 4;
        default: return -1;
    }
}

// 对应的字节码
0: iload_1
1: tableswitch   { // 100 to 104
            100: 36
            101: 38
            102: 42
            103: 42
            104: 40
        default: 42
    }
36: iconst_0
37: ireturn
38: iconst_1
39: ireturn
40: iconst_4
41: ireturn
42: iconst_m1
43: ireturn
```

lookupswitch：

```java
int test(String name) {
    switch (name) {
        case "Java": return 100;
        case "Scala": return 1;
        case "Kotlin": return 2;
        default: return -1;
    }
}

// 对应的字节码，局部变量表长度为4，0是this，1是name，2是name的一份拷贝（记为tmpName），3是匹配索引值（记为matchIndex）
0: aload_1 // 加载name
1: astore_2 // 将name保存到tmpName
2: iconst_m1 // 加载-1
3: istore_3 // matchIndex置为-1
4: aload_2 // 加载tmpName，准备调用hashCode方法
5: invokevirtual #2             // Method java/lang/String.hashCode:()I
8: lookupswitch  { // 3 ，case的值断层较大，使用lookupswitch作为实现。在这里比较hash值
     -2041707231: 72 // 对应 Kotlin 的hash值
         2301506: 44 // 对应 Java 的hash值
        79698214: 58 // 对应 Scala 的hash值
         default: 83
    }
44: aload_2 // 加载tmpName
45: ldc           #3            // String Java，从常量池中加载 Java 字符串
47: invokevirtual #4            // Method java/lang/String.equals:(Ljava/lang/Object;)Z
50: ifeq          83 // 如果不相等，跳转到83。考虑到hash冲突，所以需要调用equals方法
53: iconst_0 // 相等则加载0
54: istore_3 // matchIndex置为0
55: goto          83 // 跳转到83
58: aload_2
59: ldc           #5            // String Scala
61: invokevirtual #4            // Method java/lang/String.equals:(Ljava/lang/Object;)Z
64: ifeq          83
67: iconst_1
68: istore_3
69: goto          83
72: aload_2
73: ldc           #6            // String Kotlin
75: invokevirtual #4            // Method java/lang/String.equals:(Ljava/lang/Object;)Z
78: ifeq          83
81: iconst_2
82: istore_3
83: iload_3 // 加载matchIndex的值
84: tableswitch   { // 0 to 2
               0: 112
               1: 114
               2: 116
         default: 118
    }
112: bipush        100
113: ireturn
114: iconst_1
115: ireturn
116: iconst_2
117: ireturn
118: iconst_m1
119: ireturn
```

但是，有一些情况和上述的规则并不一样：

```java
int choose(int i) {
    switch (i) {
        case 0: return 0;
        case 1: return 1;
        default: return -1;
    }
}

// 对应的字节码
0: iload_1
1: lookupswitch  { // 2
               0: 28
               1: 30
         default: 32
    }
28: iconst_0
29: ireturn
30: iconst_1
31: ireturn
32: iconst_m1
33: ireturn
```

可以发现，case值为0和1，但是使用的是lookupswitch，这与javac源码有关：

```java
long table_space_cost = 4 + ((long) hi - lo + 1);
long table_time_cost = 3;
long lookup_space_cost = 3 + 2 * (long) nlabels;
long lookup_time_cost = nlabels;
int opcode = nlabels > 0 && table_space_cost + 3 * table_time_cost <= lookup_space_cost + 3 * lookup_time_cost ? tableswitch : lookupswitch;
// nlabels等于case值的个数
// 对于上面的例子一，table_cost = 7 + 3 * 3 = 16, lookup_cost = 9 + 3 * 3 = 18，因此选择tableswitch
// 对于上面的例子二，table_cost非常大，因此选择lookupswitch
// 对于上面的例子三，table_cost = 7 + 2 * 3 = 13, lookup_cost = 7 + 3 * 3 = 16，因此选择tableswitch
```

**for循环、i++和++i的字节码原理**

```java
void loop() {
    int i = 0;
    for(int j = 0; j < 50; j++){
        i = i++;
    }
}

// 对应的字节码
0: iconst_0 // 加载0
1: istore_1 // 将i置为0
2: iconst_0
3: istore_2 // 将j置为0
4: iload_2 // 加载j
5: bipush        50 // 50入栈
7: if_icmpge     21 // 比较栈顶的j和50之间的大小
10: iload_1 // 加载i到栈顶
11: iinc          1, 1 // 对局部变量表slot=1的变量i直接加1
14: istore_1 // 将栈顶的i的值赋值给局部变量表slot=1的变量
15: iinc          2, 1 // 对j直接加1
18: goto          4 // 跳转到4
21: return
```

**try-catch-finally字节码原理**

```java
void foo() {
    try {
        int i = 1 / 0;
    } catch (ArithmeticException ex){
        System.out.println();
    } catch (Exception ex){
        System.out.println();
    }
}

// 对应的字节码
0: iconst_1
1: iconst_0
2: idiv
3: istore_1
4: goto          24
7: astore_1 // 将栈顶的异常对象存储到局部变量表中下标为1的位置
8: getstatic     #3                  // Field java/lang/System.out:Ljava/io/PrintStream;
11: invokevirtual #4                  // Method java/io/PrintStream.println:()V
14: goto          24
17: astore_1
18: getstatic     #3                  // Field java/lang/System.out:Ljava/io/PrintStream;
21: invokevirtual #4                  // Method java/io/PrintStream.println:()V
24: return
    Exception table:
       from    to  target type
           0     4     7   Class java/lang/ArithmeticException
           0     4    17   Class java/lang/Exception
```

当方法包含try-catch语句时，编译过程中会生成异常表，每个异常表项表示一个异常处理器，由from指针、to指针、target指针、所捕获的异常类型type四部分组成。这些指针的值是字节码索引，用于定位字节码。其含义是在`[from, to)`字节码范围内，如果抛出了异常类型为type的异常，就会跳转到target指针表示的字节码处继续执行，它会判断抛出的异常是否是想捕获的异常或其子类。当抛出异常时，JVM会自动将异常对象加载到栈顶。

```java
int foo() {
    try {
        int i = 1 / 0;
    } catch (ArithmeticException ex){
        return -1;
    } finally {
        return 1;
    }
}

// 对应的字节码
0: iconst_1
1: iconst_0
2: idiv
3: istore_1
4: iconst_1 // finally代码块
5: ireturn // finally代码块
6: astore_1
7: iconst_m1 // 加载catch代码块的return语句的-1
8: istore_2 // 暂存到局部变量表中
9: iconst_1 // finally代码块
10: ireturn // finally代码块
11: astore_3
12: iconst_1 // finally代码块
13: ireturn // finally代码块
Exception table:
       from    to  target type
           0     4     6   Class java/lang/ArithmeticException
           0     4    11   any
           6     9    11   any
```

Java编译器使用复制finally代码块的方式，将其内容插入到try和catch代码块中所有正常退出和异常退出之前。

虽然catch语句有return语句，但受finally语句return的影响，catch语句的return结果会被暂存到局部变量表中，没有机会执行返回。

```java
int foo() { // 结果为100
    int i = 100;
    try {
        return i;
    } finally {
        ++i;
    }
}

// 对应的字节码
0: bipush        100
2: istore_1
3: iload_1
4: istore_2
5: iinc          1, 1 // 对局部变量表slot=1的变量加1
8: iload_2 // 加载的是slot=2的变量
9: ireturn
10: astore_3
11: iinc         1, 1
14: aload_3
15: athrow
Exception table:
       from    to  target type
           3     5    10   any
```

**try-with-resources的字节码原理**

不使用try-with-resources时，在finally阶段调用close方法时有可能抛出异常，而该异常会先于try阶段的异常返回，导致重要的异常信息消失。因此try-with-resources的原理就是调用Throwable类的addSuppressed方法，将被抑制的异常记录下来，这样后续可以通过getSuppressed方法来获得这些异常。

**对象相关的字节码指令**

1. `<init>`方法

   该方法是对象初始化方法，类的构造方法、非静态变量的初始化、对象初始化代码块都会被编译进这个方法中

   ```java
   // 非静态变量的初始化
   private int a = 10;
   public Init(){ // 类构造方法
       int c = 30;
   }
   { // 对象初始化代码块
       int b = 20;
   }
   
   // 对应的字节码
   public Init();
     Code:
        0: aload_0
        1: invokespecial #1                  // Method java/lang/Object."<init>":()V
        4: aload_0
        5: bipush        10
        7: putfield      #2                  // Field a:I
       10: bipush        20
       12: istore_1
       13: bipush        30
       15: istore_1
       16: return
   ```

2. `new、dup、invokespecial`对象创建指令

   一个对象的创建需要三条指令，new、dup、init方法的invokespecial调用。在JVM中，调用new指令时，只是创建了一个类实例引用，将这个引用压入操作数栈，此时还没有调用初始化方法。中间的dup指令复制一份类实例引用，因为invokespecial会消耗操作数栈顶的类实例引用。使用invokespecial调用`<init>`后才真正调用了构造器方法，完成类的初始化。

   本质上来说要有dup指令的原因是`<init>`方法没有返回值，如果其将新建的引用对象作为返回值，也就需要dup指令了（因为可以将返回值入栈）。

3. `<client>`方法

   该方法是类的静态初始化方法，类静态初始化块、静态变量初始化都会被编译进这个方法中。

   ```java
   private static int a = 10;
   static {
       int b = 20;
   }
   
   // 对应的字节码
   static {}; // static {} 表示<client>方法
     Code:
        0: bipush        10
        2: putstatic     #2                  // Field a:I
        5: bipush        20
        7: istore_0
        8: return
   ```

   `<client>`方法不会被直接调用，只有在四个指令触发时被调用（`new`、`getstatic`、`putstatic`、`invokestatic`），比如下面的场景：

   - 创建类对象的实例，如`new`、反射、反序列化
   - 访问类的静态变量或者静态方法
   - 访问类的静态字段或者对静态字段赋值（final的字段除外）
   - 初始化某个类的子类

## 字节码进阶

### 方法调用指令

JVM的方法调用指令都以invoke开头：

- `invokestatic`：用于调用静态方法
- `invokevirtual`：用于调用非私有实例方法
- `invokespecial`：用于调用私有实例方法、构造器方法以及使用super关键字调用父类的实例方法
- `invokeinterface`：用于调用接口方法
- `invokedynamic`：用于调用动态方法

**invokestatic**

invokestatic调用的方法在编译器确定，且在运行期不会修改，属于静态绑定。调用invokestatic不需要将对象加载到操作数栈，只需要将所需要的参数入栈就可以执行了。

```java
Integer.valueOf("42");

// 对应的字节码
0: ldc           #2      // String 42
2: invokestatic  #3      // Method java/lang/Integer.valueOf (Ljava/lang/String;)Ljava/lang/Integer;
```

**invokevirtual**

invokevirtual调用的目标在运行时才能根据对象实际的类型确定，在编译器无法知道。调用invokestatic需要将对象引用、方法参数入栈，调用结束对象引用和方法参数都会出栈，如果方法有返回值。则返回值入栈。

invokevirtual根据对象的实际类型进行分派（虚方法分派），在运行时动态选择具体子类以执行对应方法。

**invokespecial**

有了invokevirtual还有invokespecial的原因是，可以提高效率，invokespecial调用的方法在编译期间可以确定，比如私有方法因为不会被子类重写，在编译器就可以确定。

**invokeinterface**

invokeinterface与invokevirtual一样，需要在运行时根据对象的类型确定目标方法，不用invokevirtual来实现invokeinterface的原因与Java的方法分派原理有关。

Java只支持单继承，其使用虚方法表实现多态，使用的是vtable结构，具体来说，子类的虚方法表保留父类中虚方法表的顺序，重写的方法会改变方法链接，新增的方法放在最后。

```java
class A {
    public void method1() {}
    public void method2() {}
    public void method3() {}
}
class B extends A {
    public void method2() {} // override
    public void method4() {}
}
```

类A的虚方法表：

| index | 方法引用  |
| ----- | --------- |
| 1     | A/method1 |
| 2     | A/method2 |
| 3     | A/method3 |

类B的虚方法表：

| index | 方法引用  |
| ----- | --------- |
| 1     | A/method1 |
| 2     | B/method2 |
| 3     | A/method3 |
| 4     | B/method4 |

如果这时要调用method2方法，invokevirtual只需要直接去找虚方法表位置2的方法引用就可以了。

Java的单继承看起来规避了C++多继承带来的复杂性，但支持实现多个接口与多继承没有本质上的区别。JVM提供itable（interface method table）的结构来支持多接口实现，itable由偏移量（offset table）和方法表（method table，类似于vtable）组成。在需要调用某个接口方法时，虚拟机会在itable的offset table中查找method table的偏移量位置，随后在method table中查找具体的方法实现。

```java
interface A {
    void method1();
    void method2();
}
interface B {
    void method3();
}
class C implements A, B {
    public void method1() {}
    public void method2() {}
    public void method3() {}
}
class D implements B {
    public void method3() {}
}
```

C类的itable：

| index | 方法引用 |
| ----- | -------- |
| 1     | method1  |
| 2     | method2  |
| 3     | method3  |

D类的itable：

| index | 方法引用 |
| ----- | -------- |
| 1     | method3  |

类C中method3在第三个位置，而类D中method3在第一个位置，使用invokevirtual调用method3不能直接从固定的索引位置取得对应的方法，而只能搜索整个itable来找到对应方法。

**invokedynamic**

方法句柄（MethodHandle，又称为方法指针），属于`java.lang.invoke`包，它是的Java可以像其他语言一样把函数作为参数进行传递，类似于反射中的Method类，但它比Method类更加灵活和轻量。

```java
import java.lang.invoke.*;

public class Foo{

	void print(String s){
		System.out.println("hello, " + s);
	}
	
	public static void main(String[] args) throws Throwable{
		Foo foo = new Foo();
        // 创建MethodType对象，MethodType表示方法签名，每个MethodHandle都有一个MethodType对象，用来指定方法的返回值类型和各个参数类型
		MethodType methodType = MethodType.methodType(void.class, String.class);
        // MethodHandles.lookup()返回MethodHandle.Lookup对象，这个对象表示查找的上下文，根据方法的不同类型，调用findStatic、findVirtual、findSpecial等方法查找方法签名为MethodType的方法句柄
		MethodHandle methodHandle = MethodHandles.lookup().findVirtual(Foo.class, "print", methodType);
        // 通过MethodHandle调用具体的方法，使用invoke或者invokeExact进行方法调用
		methodHandle.invokeExact(foo, "world");
	}

}
```

invokedynamic指令的调用流程为：

1. JVM首次执行invokedynamic指令时调用引导方法（Bootstrap Method）
2. 引导方法返回一个CallSite对象，CallSite内部根据方法签名进行目标方法的查找，其getTarget方法返回MethodHandle对象
3. 在CallSite没有变化的情况下，MethodHandle可以一直被调用，如果CallSite发生变化，则重新查找MethodHandle对象

### Lambda表达式原理

```java
public class InvokeDynamic{

    public static void main(String[] args) {
       Runnable r = () -> {
		   System.out.println("lambda");
	   };
	   r.run();
    }

}

// 对应的字节码
public static void main(java.lang.String[]);
  Code:
     0: invokedynamic #2,  0              // InvokeDynamic #0:run:()Ljava/lang/Runnable;
     5: astore_1
     6: aload_1
     7: invokeinterface #3,  1            // InterfaceMethod java/lang/Runnable.run:()V
    12: return
// 需要-p选项显示。生成了私有静态方法
private static void lambda$main$0();
  Code:
     0: getstatic     #4                  // Field java/lang/System.out:Ljava/io/PrintStream;
     3: ldc           #5                  // String lambda
     5: invokevirtual #6                  // Method java/io/PrintStream.println:(Ljava/lang/String;)V
     8: return
    
// main方法中出现了invokedynamic指令，#2表示常量池中#2的元素，这个元素又指向#0:#30
Constant pool:
	#2 = InvokeDynamic      #0:#30         // #0:run:()Ljava/lang/Runnable;
    #3 = InterfaceMethodref #31.#32        // java/lang/Runnable.run:()V
    ...
    #27 = MethodHandle       #6:#40         // invokestatic java/lang/invoke/LambdaMetafactory.metafactory:(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;
  	#28 = MethodType         #10            //  ()V
  	#29 = MethodHandle       #6:#41         // invokestatic InvokeDynamic.lambda$main$0:()V
    #30 = NameAndType        #42:#43        // run:()Ljava/lang/Runnable;

// #0是特殊查找，对应BootstrapMethods中的第0行，其对LambdaMetafactory.metafactory进行了调用，返回CallSite对象
InnerClasses:
     public static final #57= #56 of #60; //Lookup=class java/lang/invoke/MethodHandles$Lookup of class java/lang/invoke/MethodHandles
BootstrapMethods:
  0: #27 invokestatic java/lang/invoke/LambdaMetafactory.metafactory:(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;
    Method arguments:
      #28 ()V
      #29 invokestatic InvokeDynamic.lambda$main$0:()V
      #28 ()V
```

metafactory方法：

```java
public static CallSite metafactory(MethodHandles.Lookup caller, // JVM提供的查找上下文
                                   String invokedName, // 调用函数名，本例中为 run
                                   MethodType invokedType, 
                                   MethodType samMethodType, // 表示函数式接口定义的方法签名（参数类型和返回值类型），本例中run方法的签名为 ()void
                                   MethodHandle implMethod, // 表示编译时生成的Lambda表达式对应的静态方法 lambda$main$0()
                                   MethodType instantiatedMethodType // 一般和samMethodType一样或者是它的一个特例，本例中为 ()void
                                  ) throws LambdaConversionException {
    AbstractValidatingLambdaMetafactory mf;
    // 其在内部生成新的内部类，类名为 ClassName$$Lambda$n
    mf = new InnerClassLambdaMetafactory(caller, invokedType,
                                         invokedName, samMethodType,
                                         implMethod, instantiatedMethodType,
                                         false, EMPTY_CLASS_ARRAY, EMPTY_MT_ARRAY);
    mf.validateMetafactoryArgs();
    return mf.buildCallSite();
}
```

LambdaMetafactory类中有一个静态初始化方法块，其有一个开关可以决定是否把生成的类dump出来。使用方式为`java -Djdk.internal.lambda.dumpProxyClasses=. InvokeDynamic`，运行该类会发现在运行期间，生成了一个新的内部类`InvokeDynamic$$Lambda$1.class`，这个类是使用ASM字节码技术动态生成的，其实现Runnable接口，并在run方法中调用InvokeDynamic类的静态方法`lambda$main$0()`。

```java
final class InvokeDynamic$$Lambda$1 implements java.lang.Runnable {
  public void run();
    Code:
       0: invokestatic  #17                 // Method InvokeDynamic.lambda$main$0:()V
       3: return
}
```

Lambda表达式原理总结：

1. Lambda表达式声明的地方会生成一个invokedynamic指令，同时编译器生成一个对应的引导方法（Bootstrap Method）
2. 第一次执行invokedynamic指令时，会调用对应的引导方法，该引导方法会调用`LambdaMetafactory.metafactory`方法动态生成内部类
3. 引导方法返回一个动态调用CallSite对象，该对象会最终调用实现了Runnable接口的内部类
4. Lambda表达式中的内容会被编译成静态方法，由动态生成的内部类调用该静态方法
5. 真正执行lambda调用的还是invokeinterface指令

为什么Lambda表达式要基于invokedynamic指令而不是在编译期间生成匿名内部类的方式呢？因为这种方式可以实现两个目标：1）为未来的优化提供最大的灵活性；2）保持类文件字节码格式的稳定。其只暴露了invokedynamic指令，而把逻辑隐藏在JDK的实现中，后续如果要替换实现方法（如使用内部类、method handle、动态代理等）就非常容易。

### 反射的实现原理

反射的Method.invoke方法调用MethedAccessor.invoke方法，其实现类是一个委托类（DelegatingMethedAccessorImpl），将调用委托给真正的MethodAccessorImpl实现类。默认情况下，在第0～15次调用中，实现类是NativeMethodAccessorImpl，从第16次开始，实现类是MethodAccessorImpl。NativeMethodAccessorImpl的invoke方法会统计被调用次数，当超过默认阈值之后，将通过ASM生成新的类。0～15次使用native方法，而15次之后使用ASM新生成的类，这是基于性能来考虑的。JNI调用比动态生成类调用的方式慢20倍左右，但是由于ASM生成字节码的过程比较慢，如果反射仅调用一次，采用生成字节码的方式比native调用慢3～4倍。为了权衡两种方法的利弊，Java引入了inflation机制。

很多情况下，反射只会调用一两次，JVM设置了`sun.reflect.inflation.Threshold`阈值，默认等于15。除了该阈值之外，还有一个是否禁用inflation的属性`sun.reflect.noInflation`，默认值为false，如果设置为true，那么从第0次就是使用ASM动态生成类的方式来调用反射方法。

## ASM和Javassist字节码操作工具

### ASM

ASM核心包由Core API、Tree API、Commons、Util、XML组成，Core API中最重要的三个类如下：

- ClassReader：是字节码读取和分析引擎，负责解析class文件，每当有事件发生时，触发相应的ClassVisitor、MethodVisitor等做相应的处理。

- ClassVisitor：是一个抽象类，ClassReader的accept方法需要传入一个ClassVisitor对象，ClassReader在解析class文件的过程中遇到不同的节点时会调用ClassVisitor不同的visit方法，如visitAttribute、visitInnerClass、visitField、visitMethod、visitEnd方法等。在visit过程中还会产生一些子过程，如visitAnnotation会触发AnnotationVisitor的调用、visitMethod会触发MethodVisitor的调用，正是在这些visit的过程中，我们有机会修改各个子节点的字节码。

  visit方法按照以下的顺序被调用执行：

  ```
  以下是用正则的通配符表示的
  visit
  visitSource?
  visitOuterClass?
  [visitAnnotation | visitAttribute]*
  [visitInnerClass | visitField | visitMethod]*
  visitEnd
  ```

- ClassWriter：是ClassVisitor的一个实现类，在ClassVisitor的visit方法中可以对原始的字节码做修改，ClassWriter的toByteArray方法则把最终修改的字节码以byte数组的形式返回。

**访问类的字段和方法**

将下面的文件编译为class文件：

```java
public class MyMain{
	public int a = 0;
	public int b = 1;
	public void test1(){}
	public void test2(){}
}
```

使用ASM来输出类的方法和字段列表：

```java
import org.objectweb.asm.*;
import java.io.IOException;

public class ASMSimple{
    
	public static void main(String[] args) throws IOException{
		String className = "MyMain";
		ClassReader cr = new ClassReader(className);
		ClassWriter cw = new ClassWriter(0);
		ClassVisitor cv = new ClassVisitor(Opcodes.ASM5, cw) {
            @Override
			public FieldVisitor visitField(int access, String name, String desc, String signature, Object value){
				System.out.println("field: " + name);
				return super.visitField(access, name, desc, signature, value);
			}
			@Override
			public MethodVisitor visitMethod(int access, String name, String desc, String signature, String[] exception){
				System.out.println("method: " + name);
				return super.visitMethod(access, name, desc, signature, exception);
			}
		};
        /*ClassReader的accept方法第二个参数是一个位掩码，可以选择的组合有：
        SKIP_DEBUG：跳过类文件中的调试信息，如行号信息（LineNumberTable）等
        SKIP_CODE：跳过方法体中的Code属性（方法字节码、异常表等）
        EXPAND_FRAMES：展开StackMapTable属性
        SKIP_FRAMES：跳过StackMapTable属性
        本例只要求输出字段名和方法名，不需要解析方法Code属性和调试信息。
        */
		cr.accept(cv, ClassReader.SKIP_CODE | ClassReader.SKIP_DEBUG);
	}
    
}
```

执行（将asm-9.3.jar放在同一个目录下的lib文件夹下）：

```sh
javac -Djava.ext.dirs=./lib ASMSimple.java
java -Djava.ext.dirs=./lib ASMSimple
```

**新增字段和方法**

```java
public class MyMain{
}
```

使用ASM添加字段和方法：

```java
import org.objectweb.asm.*;
import java.io.IOException;
import java.io.*;

public class ASMSimple{

	public static void main(String[] args) throws IOException{
		String className = "MyMain";
		ClassReader cr = new ClassReader(className);
		ClassWriter cw = new ClassWriter(0);
		ClassVisitor cv = new ClassVisitor(Opcodes.ASM5, cw) {
			@Override
			public void visitEnd(){
				super.visitEnd();
                // 添加字段
				FieldVisitor fv = cv.visitField(Opcodes.ACC_PUBLIC, "a", "Ljava/lang/String;", null, null);
				if(fv != null)	fv.visitEnd();
                // 添加方法
				MethodVisitor mv = cv.visitMethod(Opcodes.ACC_PUBLIC, "test", "(Ljava/lang/String;)V", null, null);
				if(mv != null)	mv.visitEnd();
			}
		};
		cr.accept(cv, ClassReader.SKIP_CODE | ClassReader.SKIP_DEBUG);
		byte[] result = cw.toByteArray();
		try(FileOutputStream fos = new FileOutputStream("./MyMain.class")){
			fos.write(result);
		}
	}
}
```

执行：

```sh
javac MyMain.java
javac -Djava.ext.dirs=./lib ASMSimple.java
java -Djava.ext.dirs=./lib ASMSimple
javap -c -v MyMain
```

**移除字段和方法**

```java
public class MyMain{
	public int a = 0;
	public int b = 1;
	public void test1(){}
	public void test2(){}
}
```

使用ASM移除字段和方法：

```java
import org.objectweb.asm.*;
import java.io.IOException;
import java.io.*;

public class ASMSimple{
    
	public static void main(String[] args) throws IOException{
		String className = "MyMain";
		ClassReader cr = new ClassReader(className);
		ClassWriter cw = new ClassWriter(0);
		ClassVisitor cv = new ClassVisitor(Opcodes.ASM5, cw) {
            @Override
			public FieldVisitor visitField(int access, String name, String desc, String signature, Object value){
				if("a".equals(name)){
					return null; // 返回null
				}
				return super.visitField(access, name, desc, signature, value);
			}
			@Override
			public MethodVisitor visitMethod(int access, String name, String desc, String signature, String[] exception){
				if("test1".equals(name)){
					return null;
				}
				return super.visitMethod(access, name, desc, signature, exception);
			}
		};
		cr.accept(cv, ClassReader.SKIP_CODE | ClassReader.SKIP_DEBUG);
	}
    
}
```

执行：

```sh
javac MyMain.java
javac -Djava.ext.dirs=./lib ASMSimple.java
java -Djava.ext.dirs=./lib ASMSimple
javap -c -v MyMain
```

**修改方法内容**

MethodVisitor类有很多visiti方法，这些visit方法有一定的调用顺序，顺序如下：

```
visitParameter*
visitAnnotationDefault?
[visitAnnotation | visitParameterAnnonation | visitAttribute]*
(
visitCode 
	[visitFrame | visit<i>X</i>Insn | visitLabel | visitInsnAnnotation | visitTryCatchBlock | visitTryCatchAnnotation | visitLocalVariable | 	visitLocalVariableAnnotation | visitLineNumber]*
visitMaxs
)?
visitEnd
```

其中visitCode和visitMaxs可以作为方法体中字节码的开始和结束，visitEnd是MethodVisitor所有事件的结束。

```java
public class MyMain{
	public int foo(int a){
		return a; // 修改为 return a + 100;
	}
}
```

方法一，先移除方法，再增加方法，实现修改：

```java
import org.objectweb.asm.*;
import java.io.IOException;
import java.io.*;

public class ASMSimple{
    
	public static void main(String[] args) throws IOException{
		String className = "MyMain";
		ClassReader cr = new ClassReader(className);
        // 如果stack和locals都为0，则JVM不能加载和存储操作数。通过指定构造参数，让ASM自动计算
		ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS | ClassWriter.COMPUTE_FRAMES);
        // 换成了ASM7，原因是？？？ASM5生成的字节码不能执行，它将main方法修改了。
		ClassVisitor cv = new ClassVisitor(Opcodes.ASM7, cw) {
			@Override
			public MethodVisitor visitMethod(int access, String name, String desc, String signature, String[] exception){
				if("foo".equals(name)){
					return null;
				}
				return super.visitMethod(access, name, desc, signature, exception);
			}
			@Override
			public void visitEnd(){
				MethodVisitor mv = cv.visitMethod(Opcodes.ACC_PUBLIC, "foo", "(I)I", null, null);
				mv.visitCode();
				mv.visitVarInsn(Opcodes.ILOAD, 1); // 加载a
				mv.visitIntInsn(Opcodes.BIPUSH, 100); // 加载100
				mv.visitInsn(Opcodes.IADD);
				mv.visitInsn(Opcodes.IRETURN);
                // 触发操作数栈和局部变量表大小的计算
				mv.visitMaxs(0, 0);
				mv.visitEnd();
			}
		};
		cr.accept(cv, 0);
		byte[] result = cw.toByteArray();
		try(FileOutputStream fos = new FileOutputStream("./MyMain.class")){
			fos.write(result);
		}
	}
    
}
```

`ClassWriter`可以指定构造参数：

- `new ClassWriter(0)`：不会自动计算操作数栈和局部变量表的大小，需要手动指定。
- `new ClassWriter(ClassWriter.COMPUTE_MAXS)`：自动计算操作数栈和局部变量表大小，*前提是需要调用visitMaxs方法*来触发计算上面两个值，visitMaxs的参数值可以随便指定。
- `new ClassWriter(ClassWriter.COMPUTE_FRAMES)`：不仅会计算操作数栈和局部变量表大小，还会自动计算StackMapFrames。Java6之后在class文件的Code属性中引入了StackMapTable属性，为了提高JVM在类型检查时验证过程的效率，其里面记录的是一个方法中操作数栈与局部变量区的类型在一些特定位置的状态。

执行：

```sh
javac MyMain.java
javac -Djava.ext.dirs=./lib ASMSimple.java
java -Djava.ext.dirs=./lib ASMSimple
javap -c -v MyMain
```

**AdviceAdapter使用**

AdviceAdapter是一个抽象类，继承自MethodVisitor，可以方便地在方法的开始和结束前插入代码。位于`org.objectweb.asm.commons`包下，因此需要将`asm-commons-9.3.jar`放在lib目录下。

```java
public class MyMain{
	public void foo(){
		System.out.println("Hello, world");
	}
	public static void main(String[] args){
		new MyMain().foo();
	}
}
```

使用AdviceAdapter：

```java
import org.objectweb.asm.*;
import org.objectweb.asm.commons.AdviceAdapter;
import java.io.*;

public class ASMSimple{
    
	public static void main(String[] args) throws IOException{
		String className = "MyMain";
		ClassReader cr = new ClassReader(className);
		ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS | ClassWriter.COMPUTE_FRAMES);
		ClassVisitor cv = new ClassVisitor(Opcodes.ASM7, cw) {
			@Override
			public MethodVisitor visitMethod(int access, String name, String desc, String signature, String[] exception){
				MethodVisitor mv = super.visitMethod(access, name, desc, signature, exception);
				if(!"foo".equals(name))	return mv;
				return new AdviceAdapter(Opcodes.ASM7, mv, access, name, desc) {
					@Override
					protected void onMethodEnter() { // 方法开始或构造器方法中父类的构造器调用以后被返回
						super.onMethodEnter();
						// 新增 System.out.println("enter " + name);
						mv.visitFieldInsn(GETSTATIC, "java/lang/System", "out", "Ljava/io/PrintStream;");
						mv.visitLdcInsn("enter " + name);
						mv.visitMethodInsn(INVOKEVIRTUAL, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);
					}
					@Override
					protected void onMethodExit(int opcode) { // 正常退出和异常退出时被调用
						// 新增 System.out.println("exit " + name);
						super.onMethodExit(opcode);
						mv.visitFieldInsn(GETSTATIC, "java/lang/System", "out", "Ljava/io/PrintStream;");
						if(opcode == Opcodes.ATHROW) {
							mv.visitLdcInsn("err exit " + name);
						}else {
							mv.visitLdcInsn("normal exit " + name);
						}
						mv.visitMethodInsn(INVOKEVIRTUAL, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);
					}
				};
			}
		};
		cr.accept(cv, 0);
		byte[] result = cw.toByteArray();
		try(FileOutputStream fos = new FileOutputStream("./MyMain.class")){
			fos.write(result);
		}
	}
    
}
```

执行：

```sh
javac MyMain.java
javac -Djava.ext.dirs=./lib ASMSimple.java
java -Djava.ext.dirs=./lib ASMSimple
javap -c -v MyMain
```

**给方法添加try-catch**

```java
public class MyMain{
	public void foo(){
		System.out.println("step1");
		int a = 1 / 0;
		System.out.println("step2");
	}
	public static void main(String[] args){
		new MyMain().foo();
	}
}
```

使用ASM添加try-catch（为了给整个方法包裹try-catch语句，start Label需要放在visitCode之后，end Label则放在visitMaxs调用之前）：

```java
import org.objectweb.asm.*;
import org.objectweb.asm.commons.AdviceAdapter;
import java.io.*;

public class ASMSimple{
    
	public static void main(String[] args) throws IOException{
		String className = "MyMain";
		ClassReader cr = new ClassReader(className);
		ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS | ClassWriter.COMPUTE_FRAMES);
		ClassVisitor cv = new ClassVisitor(Opcodes.ASM7, cw) {
			@Override
			public MethodVisitor visitMethod(int access, String name, String desc, String signature, String[] exception){
				MethodVisitor mv = super.visitMethod(access, name, desc, signature, exception);
				if(!"foo".equals(name))	return mv;
				return new AdviceAdapter(Opcodes.ASM7, mv, access, name, desc) {
					Label startLabel = new Label();
					
					@Override
					protected void onMethodEnter() {
						super.onMethodEnter();
						// startLabel需要放在visitCode之后
						mv.visitLabel();
						// 新增 System.out.println("enter " + name);
						mv.visitFieldInsn(GETSTATIC, "java/lang/System", "out", "Ljava/io/PrintStream;");
						mv.visitLdcInsn("enter " + name);
						mv.visitMethodInsn(INVOKEVIRTUAL, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);
					}
					
					@Override
					public void visitMaxs(int maxStack, int maxLocals) {
						// 生成异常表
						Label endLabel = new Label();
						// visitTryCatchBlock的四个参数：start, end表示异常表开始和结束的位置，handler表示异常发生后需要跳转到哪里继续执行，type表示异常类型
						mv.visitTryCatchBlock(startLabel, endLabel, endLabel, null);
						mv.visitLabel(endLabel);
						
						// 生成异常处理代码块
						finallyBlock(Opcodes.ATHROW);
						mv.visitInsn(Opcodes.ATHROW);
						super.visitMaxs(maxStack, maxLocals);
						
					}
					
					private void finallyBlock(int opcode) {
						// 新增 System.out.println("exit " + name);
						mv.visitFieldInsn(GETSTATIC, "java/lang/System", "out", "Ljava/io/PrintStream;");
						if(opcode == Opcodes.ATHROW) {
							mv.visitLdcInsn("err exit " + name);
						}else {
							mv.visitLdcInsn("normal exit " + name);
						}
						mv.visitMethodInsn(INVOKEVIRTUAL, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);
					}
					
					@Override
					protected void onMethodExit(int opcode) {
						super.onMethodExit(opcode);
						// 处理正常返回的场景
						if(opcode != Opcodes.ATHROW)	finallyBlock(opcode);
					}
				};
			}
		};
		cr.accept(cv, 0);
		byte[] result = cw.toByteArray();
		try(FileOutputStream fos = new FileOutputStream("./MyMain.class")){
			fos.write(result);
		}
	}
    
}
```

执行：

```sh
javac MyMain.java
javac -Djava.ext.dirs=./lib ASMSimple.java
java -Djava.ext.dirs=./lib ASMSimple
javap -c -v MyMain 或者 java MyMain
```

### Javassist介绍

Javassist是一个性能比ASM稍差但使用起来简单得多的字节码操作库，无需掌握字节码指令。

**核心API**

在Javassist中，每个需要编辑的类都对应一个CtClass（表示编译时的类）实例，ClassPool会存储多个CtClass。

Javassist的API与反射API相似，Java类包含的字段、方法在Javassist中分别对应CtField、CtMethod，通过CtClass对象可以给类新增字段、修改方法了。

**新增字段和方法**

```java
public class MyMain{
}
```

使用Javassist添加字段和方法：

```java
import javassist.*;
import java.io.*;

public class JavassistSimple{
    
	public static void main(String[] args) throws IOException, NotFoundException, CannotCompileException{
		ClassPool cp = ClassPool.getDefault();
		cp.insertClassPath("./MyMain.class");
		CtClass ct = cp.get("MyMain");
		CtMethod method = new CtMethod(CtClass.voidType, "foo", new CtClass[]{CtClass.intType, CtClass.intType}, ct);
		method.setModifiers(Modifier.PUBLIC);
		ct.addMethod(method);
		CtField f = new CtField(CtClass.intType, "a", ct);
		f.setModifiers(Modifier.PRIVATE);
		ct.addField(f);
		ct.writeFile(".");
	}
    
}
```

执行：

```sh
javac MyMain.java
javac -Djava.ext.dirs=./lib JavassistSimple.java
java -Djava.ext.dirs=./lib JavassistSimple
javap -c -p MyMain
```

**修改方法内容**

CtMethod提供几个方法来修改方法体：

- `setBody`：替换整个方法体，接收一段源代码字符串，Javassist会将这段源代码字符串编译为字节码，替换原来的方法体。
- `insertBefore/insertAfter`：在方法开始和结束的地方插入语句。

```java
public class MyMain{
	public int foo(int a, int b) {
		return a + b; // 修改为 a * b
	}
}
```

需要注意的是，源代码在经过javac编译后，局部变量的名字会被抹去，因此在Javassist中访问方法的参数使用`$0、$1`而不是直接使用变量名：

```java
import javassist.*;
import java.io.*;

public class JavassistSimple{
    
	public static void main(String[] args) throws IOException, NotFoundException, CannotCompileException{
		ClassPool cp = ClassPool.getDefault();
		cp.insertClassPath("./MyMain.class");
		CtClass ct = cp.get("MyMain");
		CtMethod method = ct.getMethod("foo", "(II)I");
		method.setBody("return $1 * $2;");
		ct.writeFile(".");
	}
    
}
```

执行：

```sh
javac MyMain.java
javac -Djava.ext.dirs=./lib JavassistSimple.java
java -Djava.ext.dirs=./lib JavassistSimple
java MyMain
```

Javassist的特殊标识符

- `$0, $1, $2`：`$0`在非静态方法中表示this，在静态方法中不使用，`$1`开始是方法参数

- `$args`：所有方法参数的数组，是一个Object数组，如果有原始类型，会被转换为包装类型，如上面的foo方法对应的是`new Object[]{new Integer(a), new Integer(b)}`

  ```java
  method.setBody("{System.out.println(java.util.Arrays.toString($args)); return $1 * $2;}");
  ```

- `$$`：表示所有参数的展开，参数用逗号分隔，`foo($$)`相当于`foo($1, $2)`

- `$cflow`：control flow的缩写，是一个只读属性，表示某方法的递归调用深度，比如可以记录最顶层调用的时间

  ```java
  public long fibonacci(int n) {
      if (n <= 1)	return n;
      else return fibonacci(n - 1) + fibonacci(n - 2);
  }
  
  CtMethod method = ct.getMethod("fibonacci", "(I)J");
  method.useCflow("fibonacci");
  method.insertBefore(
      "if ($cflow(fibonacci) == 0) {" + 
      "System.out.println(\"fibonacci init\" + $1);" + 
      "}"
  );
  ```

- `$_`：insertAfter方法在目标方法的末尾插入一段代码，而`$_`用于表示方法的返回值

  ```java
  public class MyMain{
  	public int foo(int a, int b) {
  		return a + b;
  	}
  }
  
  method.insertAfter("System.out.println(\"result: \" + $_);");
  ```

  如果返回之前抛出了异常则无法执行插入语句，为了能顺利执行，需要将insertAfter的第二个参数asFinally设置为true。

## Java Instrumentation

### 介绍

开发者通过`java.lang.instrument`包可以实现字节码增强，核心功能由`java.lang.instrument.Instrumentation`提供，该接口的方法提供注册类文件转换器、获取所有已加载的类等功能，允许我们在对已加载和未加载的类进行修改，实现AOP、性能监控等功能。

Instrumentation接口常用的方法：

- `addTransformer`：给Instrumentation注册一个类型为ClassFileTransformer的类文件转换器。注册之后，后续所有的JVM加载类都会被它的transform方法拦截，这个方法接收原类文件的字节数组，对类文件进行修改后，返回转换过的字节数组，由VM加载这个修改过的类文件。如果transform方法返回null，则表示不对此类做处理，否则会将返回的字节数组替换原来的字节数组。
- `retransformClasses`：对JVM已经加载的类重新触发类加载。
- `getAllLoadedClasses`：用于获取当前JVM加载的所有类对象。
- `isRetransformClassesSupported`：表示当前JVM配置是否支持类重新转换的特性。

Instrumentation有两种使用方式：1）使用启动参数；2）使用Attach API远程加载。

### -javaagent启动参数

JDK5开始，开发人员可以在JVM启动时指定一个javaagent，使用方式为`java -javaagent:myagent.jar MyMain`。为了能让JVM识别Agent的入口类，需要在jar包的MANIFEST.MF文件中指定Premain-Class等信息，一个例子如下：

```
Premain-Class: AgentMain
Agent-Class: AgentMain
Can-Redefine-Classes: true
Can-Retransform-Classes: true
```

其中，AgentMain需要定义一个静态的premain方法，JVM在类加载时会先执行AgentMain类的premain方法，再执行Java程序本身的main方法。在premain方法中可以对class文件做修改，实现类的动态修改和增强，这种机制可以认为是虚拟机级别的AOP。

```java
/*
1. agentArgument是agent的启动参数，可以在JVM启动时指定，如 java -javaagent:<jarfile>=appId:agent-demo,agentType:singleJar test.jar 的agentArgument值为"appId:agent-demo,agentType:singleJar"
2. instrumentation是一个java.lang.instrument.Instrumentation实例
*/
public static void premain(String agentArgument, Instrumentation instrumentation) throws Exception
```

**使用**

目标：在每个方法进入和结束的地方都打印一行日志。

```java
public class MyTest{
	public void foo() {
		bar1();
		bar2();
	}
	public void bar1() {}
	public void bar2() {}
	public static void main(String[] args){
		new MyTest().foo();
	}
}
```

添加ASM相关的类：

```java
import org.objectweb.asm.*;
import org.objectweb.asm.commons.AdviceAdapter;

public class MyMethodVisitor extends AdviceAdapter{
	
	public MyMethodVisitor(MethodVisitor mv, int access, String name, String desc) {
		super(Opcodes.ASM7, mv, access, name, desc);
	}
    
	@Override
	protected void onMethodEnter() {
		mv.visitFieldInsn(GETSTATIC, "java/lang/System", "out", "Ljava/io/PrintStream;");
		mv.visitLdcInsn("<<enter " + this.getName());
		mv.visitMethodInsn(INVOKEVIRTUAL, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);
		super.onMethodEnter();
	}
	@Override
	protected void onMethodExit(int opcode) {
		super.onMethodExit(opcode);
		mv.visitFieldInsn(GETSTATIC, "java/lang/System", "out", "Ljava/io/PrintStream;");
		mv.visitLdcInsn(">> exit " + this.getName());
		mv.visitMethodInsn(INVOKEVIRTUAL, "java/io/PrintStream", "println", "(Ljava/lang/String;)V", false);
	}
    
}
```

```java
import org.objectweb.asm.*;

public class MyClassVisitor extends ClassVisitor{
    
	public MyClassVisitor(ClassVisitor classVisitor) {
		super(Opcodes.ASM7, classVisitor);
	}
	
	@Override
	public MethodVisitor visitMethod(int access, String name, String desc, String signature, String[] exception){
		MethodVisitor mv = super.visitMethod(access, name, desc, signature, exception);
		if("<init>".equals(name)){
			return mv;
		}
        // 返回自定义的MethodVisitor
		return new MyMethodVisitor(mv, access, name, desc);
	}
    
}
```

```java
import org.objectweb.asm.*;
import java.lang.instrument.*;
import java.security.ProtectionDomain;

public class MyClassFileTransformer implements ClassFileTransformer{
	
    // className表示当前加载类的类名，bytes表示待加载类文件的字节数组
	@Override
	public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined, ProtectionDomain protectionDomain, byte[] bytes) throws IllegalClassFormatException {
		if(!"MyTest".equals(className))	return bytes;
		ClassReader cr = new ClassReader(bytes);
		ClassWriter cw = new ClassWriter(cr, ClassWriter.COMPUTE_FRAMES);
		ClassVisitor cv = new MyClassVisitor(cw);
		cr.accept(cv, ClassReader.SKIP_FRAMES | ClassReader.SKIP_DEBUG);
		return cw.toByteArray();
	}
    
}
```

```java
// 新建AgentMain，实现premain方法
import java.lang.instrument.*;

public class AgentMain{
	public static void premain(String agentArgs, Instrumentation inst) throws ClassNotFoundException, UnmodifiableClassException {
		inst.addTransformer(new MyClassFileTransformer(), true);
	}
}
```

执行：

```sh
javac -Djava.ext.dirs=./lib  -d ./out ./*.java
cd out

# 在当前目录下将class文件打成jar包
jar -cvf agent.jar *
# 将前面的MANIFEST.MF文件替换在META-INF下的同名文件

# 查看结果
java -Djava.ext.dirs=../lib -javaagent:agent.jar MyTest
```

### JVM Attach API

JDK5中，开发人员只能在JVM启动时指定一个javaagent，在premain中操作字节码，这种Instrumentation方式仅限于main方法执行之前，存在很大的局限性。从JDK6开始，通过动态Attach Agent的方案，可以在JVM启动之后任意时刻通过Attach API远程加载Agent的jar包。`jps、jstack、jmap`工具都是利用Attach API实现的。

**Attach API基本使用（测试不通过，还未解决）**

目标：测试代码中有一个main方法，每3秒输出foo方法的返回值100，接下来动态Attach上该进程，修改foo方法使其返回50。

```java
public class MyTest{
	public static void main(String[] args) throws InterruptedException{
		while(true){
			System.out.println(foo());
			Thread.currentThread().sleep(3000);
		}
	}
	public static int foo() {
		return 100;
	}
}
```

步骤一：自定义ClassFileTransformer，通过ASM对foo方法做注入

```java
// MyMethodVisitor类
import org.objectweb.asm.*;
import org.objectweb.asm.commons.AdviceAdapter;

public class MyMethodVisitor extends AdviceAdapter{
	
	public MyMethodVisitor(MethodVisitor mv, int access, String name, String desc) {
		super(Opcodes.ASM7, mv, access, name, desc);
	}
    
	@Override
	protected void onMethodEnter() {
		// 在方法开始插入 return 50;
		mv.visitIntInsn(BIPUSH, 50);
		mv.visitInsn(IRETURN);
	}
    
}


// MyClassVisitor类
import org.objectweb.asm.*;

public class MyClassVisitor extends ClassVisitor{
    
	public MyClassVisitor(ClassVisitor classVisitor) {
		super(Opcodes.ASM7, classVisitor);
	}
	
	@Override
	public MethodVisitor visitMethod(int access, String name, String desc, String signature, String[] exception){
		MethodVisitor mv = super.visitMethod(access, name, desc, signature, exception);
		// 只转换foo方法
		if("foo".equals(name)){
			return new MyMethodVisitor(mv, access, name, desc);
		}
		return mv;
	}
    
}

// MyClassFileTransformer类
import org.objectweb.asm.*;
import java.lang.instrument.*;
import java.security.ProtectionDomain;

public class MyClassFileTransformer implements ClassFileTransformer{
	
	@Override
	public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined, ProtectionDomain protectionDomain, byte[] bytes) throws IllegalClassFormatException {
		if(!"MyTest".equals(className))	return bytes;
		ClassReader cr = new ClassReader(bytes);
		ClassWriter cw = new ClassWriter(cr, ClassWriter.COMPUTE_FRAMES);
		ClassVisitor cv = new MyClassVisitor(cw);
		cr.accept(cv, ClassReader.SKIP_FRAMES | ClassReader.SKIP_DEBUG);
		return cw.toByteArray();
	}
    
}
```

步骤二：实现agentmain方法。动态Attach的agent会执行agentmain方法，方法参数和含义和premain类似。

```java
import java.lang.instrument.*;

public class AgentMain{
	public static void agentmain(String agentArgs, Instrumentation inst) throws ClassNotFoundException, UnmodifiableClassException {
		System.out.println("agentmain called");
		inst.addTransformer(new MyClassFileTransformer(), true);
		Class[] classes = inst.getAllLoadedClasses();
		for(Class clazz : classes) {
			if(clazz.getName().equals("MyTest")) {
				System.out.println("Reloading: " + clazz.getName());
				inst.retransformClasses(clazz);
				break;
			}
		}
	}
}
```

步骤三：因为跨进程通信，Attach的发起端是一个独立的进程，这个Java程序会调用VirtualMachine.attach方法开始和目标JVM进行跨进程通信。

```java
import com.sun.tools.attach.VirtualMachine;

public class MyAgentMain{
	public static void main(String[] args) throws Exception {
		VirtualMachine vm = VirtualMachine.attach(args[0]);
		try {
			vm.loadAgent("agent.jar");
		} finally {
			vm.detach();
		}
	}
}
```

执行：

```sh
javac -Djava.ext.dirs=./lib;"C:\Program Files\Java\jdk1.8.0_121\lib"  -d ./out ./*.java
cd out

java MyTest

# 查询MyTest的进程pid
jps
# WindowsAttachProvider could not be instantiated
java -Djava.ext.dirs=./lib;"C:\Program Files\Java\jdk1.8.0_121\lib" MyAgentMain pid
# Linux中， ; 要改成 : 

```

**Attach API底层原理**

Unix域套接字（Unix Domain Socket），可以实现同一主机上的进程之间的的通信，其与普通套接字的区别是：

- Unix域套接字更高效，它不用进行协议处理，不需要计算序列号，也不需要发送确认报文，只需要读写数据。
- Unix域套接字是可靠的，不会丢失数据，普通套接字是为不可靠通信设计的。
- Unix域套接字的代码可以非常简单地修改为普通套接字。

`VirtualMachine.attach`底层调用sendQuitTo方法，其是一个native方法，底层发送SIGQUIT信号给目标JVM进程，JVM对SIGQUIT的默认行为是dump当前的线程堆栈，但调用`VirtualMachine.attach`没有输出调用堆栈的原因在于其过程（假设目标进程为1234）：

1. Attach端检查临时文件目录是否有`.java_pid1234`文件：`.java_pid1234`文件是一个Unix域套接字文件，由Attach成功以后的目标JVM进程生成， 如果存在该文件，则说明正在Attach，可以用其进行socket通信。
2. Attach端若发现没有`.java_pid1234`文件，则创建`.attach_pid1234`，然后发送SIGQUIT信号给目标JVM，接下来每隔200ms检查一次`.java_pid1234`文件是否生成，如果生成则进行socket通信，5秒后还没有生成则退出。
3. 目标JVM的Signal Dispatcher线程收到SIGQUIT信号后，会检查`.attach_pid1234`文件是否存在：
   - 如果不存在，则认为这不是一个attach操作，执行默认行为，即输出当前所有线程的堆栈。
   - 如果存在，则认为这是一个attach操作，会启动Attach Listener线程，负责处理Attach请求，同时创建`.java_pid1234`文件

## JSR 269插件化注解处理原理

JDK6引入JSR 269，允许开发者在编译旗舰对注解进行处理，可以读取、修改、添加抽象语法树中的内容。开发者可以利用JSR 269完成很多Java不支持的特性，甚至创造新的语法糖。

javac的前两个阶段parse和enter生成抽象语法树（AST），接下来进入annotation parse阶段，JSR 269发生在该阶段，经过注解处理后输出一个修改过的AST，交给下游阶段继续处理。

### 抽象语法树操作API

- Names：提供访问标识符的方法
- JCTree：是语法树元素的基类
- TreeMaker：封装创建语法树节点的方法

**Names介绍**

最常用的方法是`fromString`，表示从一个字符串获取Name对象。如使用`names.fromString("this")`获取this名字标识符。

**JCTree介绍**

JCTree实现了Tree接口，两个核心字段为pos和type，pos表示当前节点在语法树中的位置，type表示节点的类型。JCTree有多个子类，如JCStatement、JCExpression、JCMethodDecl和JCModifiers：

- JCStatement类用来声明语句，常见的子类有JCReturn、JCBlock、JCClassDecl、JCVariableDecl、JCTry、JCIf等。

  JCReturn用于表示return语句：

  ```java
  public static class JCReturn extends JCTree.JCStatement implements ReturnTree {
      public JCTree.JCExpression expr; // 表示return语句的内容
  }
  ```

  JCBlock表示一个代码块：

  ```java
  public static class JCBlock extends JCTree.JCStatement implements BlockTree {
      public long flags; // 表示代码块的访问标记
      public List<JCTree.JCStatement> stats; // 一个列表，表示代码块中的所有语句
  }
  ```

  JCClassDecl表示类定义语法树节点：

  ```java
  public static class JCClassDecl extends JCTree.JCStatement implements ClassTree {
      public JCTree.JCModifiers mods; // 访问修饰符，如public
      public Name name; // 类名
      public List<JCTree.JCTypeParameter> typarams; // 泛型参数列表
      public JCTree.JCExpression extending; // 继承的父类信息
      public List<JCTree.JCExpression> implementing; // 实现的接口列表
      public List<JCTree> defs; // 所有的变量和方法列表
      public ClassSymbol sym; // 包名和类名
  }
  ```

  JCVariableDecl表示变量语法树节点：

  ```java
  public static class JCVariableDecl extends JCTree.JCStatement implements VariableTree {
      public JCTree.JCModifiers mods; // 变量的访问修饰符，如public
      public Name name; // 变量名
      public JCTree.JCExpression vartype; // 变量类型
      public JCTree.JCExpression init; // 变量初始化语句，可能是一个固定值，可能是一个表达式
      public VarSymbol sym;
  }
  ```

  JCTry表示try-catch-finally语句：

  ```java
  public static class JCTry extends JCTree.JCStatement implements TryTree {
      public JCTree.JCBlock body; // try语句块
      public List<JCCatch> catches; // 多个catch语句块
      public JCTree.JCBlock finalizer; // finally语句块
  }
  ```

  JCIf表示if-else语句：

  ```java
  public static class JCIf extends JCTree.JCStatement implements IfTree {
      public JCTree.JCExpression cond; // 条件语句
      public JCTree.JCStatement thenpart; // if部分
      public JCTree.JCStatement elsepart; // else部分
  }
  ```

  JCForLoop表示for循环语句：

  ```java
  public static class JCForLoop extends JCTree.JCStatement implements ForLoopTree {
      public List<JCTree.JCStatement> init; // 循环初始化语句
      public JCTree.JCExpression cond; // 条件语句
      public List<JCTree.JCExpressionStatement> step; // 每次循环后的操作表达式
      public JCTree.JCStatement body; // 循环体
  }
  ```

- JCExpression类用来表示表达式语法树节点，常见的子类有JCAssign、JCIdent、JCBinary、JCLiteral。

  JCAssign是赋值语句表达式：

  ```java
  public static class JCAssign extends JCTree.JCExpression implements AssignmentTree {
      public JCTree.JCExpression lhs; // 赋值语句的左边表达式
      public JCTree.JCExpression rhs; // 赋值语句的右边表达式
  }
  ```

  JCIdent表示标识符语法树节点，可以表示类、变量和方法：

  ```java
  public static class JCIdent extends JCTree.JCExpression implements IdentifierTree {
      public Name name; // 标识符的名字
      public Symbol sym; // 标识符的其他标记，如表示类时，sym表示类的包名和类名
  }
  ```

  JCBinary表示二元操作符，包括加减乘除等：

  ```java
  public static class JCBinary extends JCTree.JCExpression implements BinaryTree {
      public JCTree.Tag opcode; // 表示二元操作符的运算符，由枚举类Tag表示
      public JCTree.JCExpression lhs; // 二元操作符的左半部分
      public JCTree.JCExpression rhs; // 二元操作符的右半部分
  }
  ```

  JCLiteral表示字面量运算符表达式：

  ```java
  public static class JCLiteral extends JCTree.JCExpression implements LiteralTree {
      public TypeTag typetag; // 常量的类型，由枚举类TypeTag表示
      public Object value; // 常量的值
  }
  ```

- JCMethodDecl类用来表示方法的定义：

  ```java
  public static class JCMethodDecl extends JCTree.JCExpression implements MethodTree {
      public JCTree.JCModifiers mods; // 访问修饰符，如public、static、synchronized
      public Name name; // 方法名
      public JCTree.JCExpression restype; // 返回类型
      public List<JCTree.JCTypeParameter> typarams; // 泛型参数列表
      public List<JCTree.JCVariableDecl> params; // 方法参数列表
      public List<JCTree.JCExpression> thrown; // 异常列表
      public JCBlock body; // 方法体
      public JCTree.JCExpression defaultValue; // 默认值
      public MethodSymbol sym;
  }
  ```

- JCModifiers类表示访问标记语法树节点：

  ```java
  public static class JCModifiers {
      public long flags; // 表示访问标记，可以由com.sun.tools.javac.code.Flags定义的常量来表示，多个flag可以组合使用，如Flags.PUBLIC + Flags.STATIC + Flags.FINAL
      public List<JCTree.JCAnnotation> annotations;
  }
  ```

**TreeMaker介绍**

开发者需要使用包含语法树上下文的TreeMaker对象构造JCTree。常用的方法有：

- `TreeMaker.Modifiers`方法用于生成一个JCModifiers。

  ```java
  public JCModifiers Modifiers(long flags) {}
  // 以对于下面的int变量为例
  public static final int x = 1;
  // 对应的访问标记为
  JCTree.JCModifiers modifier = treeMaker.Modifiers(Flags.PUBLIC + Flags.STATIC + Flags.FINAL);
  ```

- `TreeMaker.Binary`方法用于生成一个JCBinary。

  ```java
  // 以1 + 2为例
  JCTree.JCBinary addJCBinary = treeMaker.Binary(
  	JCTree.Tag.PLUS,
      treeMaker.Literal(1),
      treeMaker.Literal(2)
  );
  ```

- `TreeMaker.Ident`方法用于创建类、变量、方法的标识符语法树节点JCIdent。

  ```java
  Names names = Names.instance(context);
  treeMaker.Ident(names.fromString("x"));
  ```

- `TreeMaker.Select`方法用于创建一个字段或方法访问JCFieldAccess。

  ```java
  public JCFieldAccess Select(JCExpression selected, // . 号左边的表达式
                              Name selector // . 号右边的表达式
  )
  // 以 this.id 为例
  treeMaker.Select(
  	treeMaker.Ident(names.fromString("this")), // this
      jcVariableDecl.getName() // id
  );
  ```

- `TreeMaker.Return`方法用于生成一个JCReturn。

  ```java
  public JCReturn Return(JCExpression expr) {}
  // 以 return this.id; 为例
  Names names = Names.instance(context);
  JCTree.JCReturn returnStatement = treeMaker.Return(
      treeMaker.Select(
          treeMaker.Ident(
              names.fromString("this"), names.fromString("id")
          )
  );
  ```

- `TreeMaker.Assign`方法用于生成一个JCAssign。

  ```java
  // 以 x= 0; 为例
  JCAssign assign = treeMaker.Assign(
  	treeMaker.Ident(names.fromString("x")), // 等式左边
      treeMaker.Literal(0) // 等式右边
  );
  ```

- `TreeMaker.Block`方法用于生成一个JCBlock。

  ```java
  public JCBlock Block(long flags, List<JCStatement> stats) {}
  // 常见用法
  JCTree.JCStatement statement = // ...
  ListBuffer<JCTree.JCStatement> statements = new ListBuffer<JCTree.JCStatement>().append(returnStatement);
  JCTree.JCBlock body = treeMaker.Block(0, statements.toList());
  ```

- `TreeMaker.Exec`方法用于生成一个JCExpressionStatement。

  ```java
  public JCExpressionStatement Exec(JCExpression expr) {}
  // 前面介绍的Assign返回一个JCAssign对象，一般对其包装一层Exec方法调用，使其返回一个JCExpressionStatement对象
  JCTree.JCExpressionStatement statement = treeMaker.Exec(assign);
  ```

- `TreeMaker.VarDef`方法用于生成一个JCVariableDecl。

  ```java
  public JCVariableDecl VarDef(
  	JCModifiers mods, // 访问标记
      Name name, // 变量名
      JCExpression vartype, // 变量类型
  	JCExpression init // 变量初始化表达式
  )
  // 以 private int x = 1; 为例
  JCTree.JCVariableDecl var = treeMaker.VarDef(
  	treeMaker.Modifiers(Flags.PRIVATE),
      names.fromString("x"),
      treeMaker.TypeIdent(TypeTag.INT),
  	treeMaker.Literal(1)
  )
  ```

- `TreeMaker.MethodDef`方法用于生成一个JCMethodDecl。

  ```java
  public JCMethodDecl MethodDef(
      JCModifiers mods, // 方法访问级别修饰符
      Name name, // 方法名
      JCExpression restype, // 返回值类型
      List<JCTypeParameter> typarams; // 泛型参数列表
      List<JCTree.JCVariableDecl> params; // 方法参数列表
      List<JCTree.JCExpression> thrown; // 异常列表
      JCBlock body; // 方法体
      JCTree.JCExpression defaultValue; // 默认值
  );
  ```

### 实战

目标：使用JSR 269为类中的字段自动生成get、set方法。

自定义注解类：

```java
import java.lang.annotation.*;

@Target({ElementType.TYPE})
@Retention(RetentionPolicy.SOURCE)
public @interface Data{
}
```

新建一个AbstractProcessor的子类DataAnnotationProcessor，实现init和process方法：

```java
import java.lang.annotation.*;
import javax.lang.model.*;
import javax.lang.model.element.TypeElement;
import javax.lang.model.element.Element;
import javax.annotation.processing.*;
import java.util.Set;
import com.sun.source.tree.Tree;
import com.sun.tools.javac.api.JavacTrees;
import com.sun.tools.javac.processing.*;
import com.sun.tools.javac.code.Type;
import com.sun.tools.javac.tree.*;
import com.sun.tools.javac.util.*;
import com.sun.tools.javac.code.Flags;

@SupportedAnnotationTypes("Data") // 处理类全限定名为Data的注解
@SupportedSourceVersion(SourceVersion.RELEASE_8) // 最高支持JDK8编译出来的文件
public class DataAnnotationProcessor extends AbstractProcessor{
	
	private JavacTrees javacTrees;
	private TreeMarker treeMarker;
	private Names names;
    // 用于初始化JavacTrees，TreeMarker，Names等关键类
	@Override
	public synchronized void init(ProcessingEnvironment processingEnv) {
		super.init(processingEnv);
		Context context = ((JavacProcessingEnvironment) processingEnv).getContext();
		javacTrees = JavacTrees.instance(processingEnv);
		treeMaker = TreeMaker.instance(context);
		names = Names.instance(context);
	}
	
	@Override
	public boolean process(Set<? extends TypeElement> annotations, RoundEnvironment roundEnv) {
        // 获取被Data注解的类的集合
		Set<? extends Element> set = roundEnv.getElementsAnnotatedWith(Data.class);
        // 处理这些被Data注解类
		for (Element element : set) {
			JCTree tree = javacTrees.getTree(element); // 获取当前处理类的抽象语法树
            // 传入TreeTranslator，重写visitClassDef方法，在遍历抽象语法树的过程中遇到相应的事件就调用该方法
			tree.accept(new TreeTranslator() {
				@Override
				public void visitClassDef(JCTree.JCClassDecl jcClassDecl) {
					jcClassDecl.defs.stream()
									.filter(it -> it.getKind().equals(Tree.Kind.VARIABLE)) // 只处理变量类型
									.map(it -> (JCTree.JCVariableDecl) it)
									.forEach(it -> {
										jcClassDecl.defs = jcClassDecl.defs.prepend(genGetterMethod(it));
										jcClassDecl.defs = jcClassDecl.defs.prepend(genSetterMethod(it));
									});
					super.visitClassDef(jcClassDecl);
				}
			});
		}
		return true;
	}
    
	private JCTree.JCMethodDecl genGetterMethod(JCTree.JCVariableDecl jcVariableDecl) {
        // 生成返回语句 return this.xxx;
		JCTree.JCReturn returnStatement = treeMaker.Return(
			treeMaker.Select(treeMaker.Ident(names.fromString("this")), jcVariableDecl.getName())
		);
		
		ListBuffer<JCTree.JCStatement> statements = new ListBuffer<JCTree.JCStatement>().append(returnStatement);
        // public修饰符
		JCTree.JCModifiers modifiers = treeMaker.Modifiers(Flags.PUBLIC);
        // 方法名，getXxx
		Name getMethodName = getMethodName(jcVariableDecl.getName());
        // 返回值类型与字段类型相同
		JCTree.JCExpression returnMethodType = jcVariableDecl.vartype;
        // 生成方法体
		JCTree.JCBlock body = treeMaker.Block(0, statements.toList());
        // 泛型列表参数
		List<JCTree.JCTypeParameter> methodGenericParamList = List.nil();
        // 参数值列表
		List<JCTree.JCVariableDecl> parameterList = List.nil();
        // 异常列表
		List<JCTree.JCExpression> thrownCauseList = List.nil();
		
		return treeMaker.MethodDef(
			modifiers, // 方法修饰符
			getMethodName, // 方法名
			returnMethodType, // 返回值类型
			methodGenericParamList, // 泛型列表参数
			parameterList, // 参数值列表
			thrownCauseList, // 异常列表
			body, // 方法体
			null // 默认值
		);
	}
	
	private JCTree.JCMethodDecl genSetterMethod(JCTree.JCVariableDecl jcVariableDecl) {
		// this.xxx = xxx
		JCTree.JCExpressionStatement statement = treeMaker.Exec(
			treeMaker.Assign(
				treeMaker.Select(
					treeMaker.Ident(names.fromString("this")),
					jcVariableDecl.getName()
				), // lhs 
				treeMaker.Ident(jcVariableDecl.getName()) // rhs
			)
		);
		
		ListBuffer<JCTree.JCStatement> statements = new ListBuffer<JCTree.JCStatement>().append(statement);
		
        // set方法参数
		JCTree.JCVariableDecl param = treeMaker.VarDef(
			treeMaker.Modifiers(Flags.PARAMETER, List.nil()), // 访问修饰符
			jcVariableDecl.name, // 变量名
			jcVariableDecl.vartype, // 变量类型
			null // 变量初始值
		);
		JCTree.JCModifiers modifiers = treeMaker.Modifiers(Flags.PUBLIC);
		Name setMethodName = setMethodName(jcVariableDecl.getName());
		JCTree.JCExpression returnMethodType = treeMaker.Type(new Type.JCVoidType());
		JCTree.JCBlock body = treeMaker.Block(0, statements.toList());
		List<JCTree.JCTypeParameter> methodGenericParamList = List.nil();
		List<JCTree.JCVariableDecl> parameterList = List.of(param);
		List<JCTree.JCExpression> thrownCauseList = List.nil();
		
		return treeMaker.MethodDef(
			modifiers,
			setMethodName,
			returnMethodType,
			methodGenericParamList,
			parameterList,
			thrownCauseList,
			body,
			null
		);
	}
	
	private Name getMethodName(Name name) {
		String fieldName = name.toString();
		return names.fromString("get" + fieldName.substring(0, 1).toUpperCase() + fieldName.substring(1, name.length()));
	}
	private Name setMethodName(Name name) {
		String fieldName = name.toString();
		return names.fromString("set" + fieldName.substring(0, 1).toUpperCase() + fieldName.substring(1, name.length()));
	}
}
```

新建User测试类：

```java
@Data
public class User{
	private int id;
	private String name;
	
	public void set(int a){
		System.out.println(a);
	}
	
	public static void main(String[] args){
		User user = new User();
		user.setId(18);
		user.setName("bob");
		System.out.println(user.getId() + ", " + user.getName());
	}
}
```

使用：

```sh
# 先编译注解类
javac -Djava.ext.dirs="C:\Program Files\Java\jdk1.8.0_121\lib" DataAnnotationProcessor.java
# 编译User类，-cp表示classpath，-processor表示注解处理类
javac -cp . -processor DataAnnotationProcessor User.java
java User
```


