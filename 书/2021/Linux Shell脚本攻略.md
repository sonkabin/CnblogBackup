## 基本知识

### 文件描述符

- 0（标准输入stdin）：`<`（从文件中读取数据）、`<<分界符`（出现在该行之后和**分界符行**之前的所有数据都会被当成stdin数据）
- 1（标准输出stdout）：`>`和`1>`（先清空文件再写入），`>>`和`1>>`（追加数据）
- 2（标准错误stderr）：`2>`（先清空文件再写入），`2>>`（追加数据）

`-`作为stdin文本的文件名

### `$`符号的用法

- 显示脚本参数（本质上是变量替换）

  `$0`：脚本名称

  `$1, $2, ...`：脚本的第一个参数，第二个参数...

  `$@`：会扩展成`$1 $2...`

  `$#`：传入脚本的参数个数

  `$$`：当前脚本的进程ID（PID）

  `$?`：上个命令的退出状态，0表示正常退出

- 获取变量值：如`val=2`，则`echo $val`或者`echo ${val}`显示`val`的值。

- 执行命令，一般同时将命令的结果赋值给变量

  ```shell
  cmd_output=$(command)
  cmd_output=`command`
  
  echo $cmd_output
  ```

- 数学计算

  `$((表达式))`、`$[表达式]`、`let 变量名=表达式`：表达式中的变量名可以不加`$`

**用`${}`获取变量值时，在`{`和`}`之间有特定的语法可以实现变量扩展功能。**

- 取子字符串：`${变量:startIndex:length}`，长度可以省略。索引允许是负数，表示从后向前计数，如`val="abc"; echo ${val:(-2):2}`

- 字符串长度：`${#变量}`

- 替换字符：`${变量/匹配字符串/替换字符串}`，替换字符串为空，可实现替换。有点像`sed`

- 根据状态返回结果

  `${变量-值}`：当变量未定义时，返回值作为结果

  `${变量:-值}`：当变量未定义或为空值时，返回值作为结果

  `${变量+值}`：当变量定义过时，返回值作为结果

  `${变量:+值}`：当变量为非空值时，返回值作为结果。可用于使用命令的非必须选项。

  `${变量=值}`：当变量未定义时，返回值作为结果，同时将值赋值给变量（变量可以使用了）

  `${变量:=值}`：当变量未定义或为空值时，返回值作为结果，同时将值赋值给变量

https://blog.csdn.net/rainforest_c/article/details/70173215

### 比较测试

**比较条件常常被放在封闭的中括号中`[]`，一定要注意在`[`或`]`与操作数之间有一个空格**

- if/elif/else

  ```shell
  if condition; then
  	commands
  elif conditon; then
  	commands
  else
  	commands
  fi
  # 可用逻辑运算符将if语句简化
  [ condition ] && commands # 如果condition为真，则执行commands
  [ condition ] || commands # 如果condition为假，则执行commands
  ```

- 算术比较

  `-eq`：等于

  `-ne`：不等于

  `-gt`：大于

  `-lt`：小于

  `-ge`：大于或等于

  `-le`：小于或等于

- 文件系统测试

  `[ -f $var ]`：如果变量是一个文件的绝对路径或相对路径，且文件存在，则返回真

  `[ -d $var ]`：如果变量对应的是目录，则返回真

  `[ -e $var ]`：如果变量对应的文件存在，则返回真

  `[ -c $var ]`：如果变量对应的是字符设备文件的路径，则返回真

  `[ -b $var ]`：如果变量对应的是块设备文件的路径，则返回真

  `[ -w $var ]`：如果变量对应的文件可写，则返回真

  `[ -r $var ]`：如果变量对应的文件可读，则返回真

  `[ -x $var ]`：如果变量对应的是可执行文件，则返回真

  `[ -L $var ]`：如果变量对应的是符号链接，则返回真

- 字符串比较

  最好用双中括号，它是Bash的一个扩展特性，ash和dash不能用该特性。

  `[[ $str1 = $str2 ]]`和`[[ $str1 == $str2 ]]`：相等为真

  `[[ $str1 != $str2 ]]`：不等为真

  `[[ $str1 > $str2 ]]`和`[[ $str1 < $str2 ]]`：根据ASCII码比较字符序大小

  `[[ -z $str ]]`：空串为真

  `[[ -n $str ]]`：非空串为真。如果`str`是空格组成的字符串，则是薛定谔的状态，空串和非空串判断都为真。

### 根据扩展名切分文件名

文件名的格式一般是`file_name.extension`，通过`%/%%`可提取`file_name`，通过`#/##`可提取`extension`

```shell
file="sample.jpg"
file_name=${file%.*} # file_name为sample。原理是删除%右边的通配符所匹配的字符串（这里的通配符是.*，会从右往左匹配）。%是非贪婪操作，而%%是贪婪操作，比如file="source.list.bak"，使用%匹配到的是.bak，而使用%%匹配到的是.list.bak
extension=${file#*.} # extension为jpg。原理与%类似，通配符匹配方向是从左往右，对应的贪婪操作是##，比如file="source.list.bak"，使用#匹配到的是source.，而使用%%匹配到的是1source.list.
```

### 目录与文件的权限

`r`：可读；`w`：可写；`x`：可执行（对目录来说，是可进入目录的权限）

目录有一个叫做粘滞位的特殊权限，如果目录设置了粘滞位，只有创建该目录的用户才有权删除目录中的文件，就算用户组和其他用户有`w`权限，也不能删除文件。粘滞位出现在其他用户的`x`位置，如果目录没有设置`x`权限，但设置了粘滞位，则用`T`；如果同时设置了`x`和粘滞位，则使用`t`。`/tmp`是一个设置了目录粘滞位的典型例子。

### 通配符和正则表达式

通配符用于匹配文件名，而正则表达式用于匹配文件里的字符串。

通配符由shell解析，常用的通配符有：

- `*`：匹配任意多个字符（正则表达式中表示匹配前一个字符任意次）
- `?`：匹配任意一个字符（正则表达式中表示匹配前一个字符0次或1次）
- `[...]`：匹配中括号中出现的任意一个字符（正则表达式中相同）
- `[!...]`：不匹配中括号中出现的任意一个字符（正则表达式中无该用法）

基础正则表达式和扩展正则表达式的区别：基础正则表达式中，`?, +, {, |, (, )`失去了特殊的含义，需要搭配转义字符`\`让它们拥有特殊的含义，即`\?, \+, \{, \|, \(, \) `。举例来说，`grep "[a-k]\+" file`等价于`egrep "[a-k]+" file`

正则表达式中，如果字符在`[]`中出现，那么字符会失去它的特殊意义（比如`.,*`等）

### 单引号和双引号的区别

单引号不会对其内部的字符做任何解释，而双引号允许shell解释字符串中出现的特殊字符。

### 日志文件

| 日志文件          | 描述                     |
| ----------------- | ------------------------ |
| /var/log/boot.log | 系统启动信息             |
| /var/log/httpd    | Apache Web服务器启动日志 |
| /var/log/messages | 内核启动信息             |
| /var/log/auth.log | 用户认证日志（sshd等）   |
| /var/log/secure   |                          |
| /var/log/dmesg    | 系统启动信息             |

### Bash运行模式

Bash运行模式，包括login与non-login shell、interactive与non-interactive shell（比如部分shell脚本）。两种分类方法是交叉的，一个login shell可能是一个interactive shell，也可能是个non-interactive shell。

- login shell只读取两个文件：

  1. /etc/profile
  2. ~/.bash_profile或者~/.bash_login或者~/.profile，按照顺序读取，如果读到一个就结束

- non-login shell只读取~/.bashrc文件，并且会继承上一个进程的部分环境变量

- non-login且non-interactive的shell其实是会读取~/.bashrc，但没有读完整就退出了，原因在于~/.bashrc中有这么一段代码

  ```sh
  # If not running interactively, don't do anything
  case $- in
      *i*) ;;
        *) return;;
  esac
  ```

  最后查找环境变量BASH_ENV，读取并执行BASH_ENV指向的文件中的命令

  [where-is-bash-env-usually-set](https://serverfault.com/questions/593472/where-is-bash-env-usually-set)

## 命令

### tee

`tee`从stdin中读取，将输入数据重定向到stdout以及一个或多个文件中。

`command | tee FILE1 FILE2 | otherCommand`

例子：

```bash
echo a1 > a1.txt && echo a2 > a2.txt && echo a3 > a3.txt; chmod 000 a1.txt;
# 接收来自stdin的数据，将一份副本写入out.txt，同时将另一份副本作为后续命令的stdin。cat -n为数据添加行号
cat a*.txt | tee out.txt | cat -n # out.txt中的内容为 a2 \n a3。
```



### cat

`cat`能够显示或拼接文件内容，也能将stdin与文件数据组合在一起。

`cat FILE1 FILE2`

例子：

```bash
echo "abc" | cat - a1.txt # 将stdin与文件数据组合在一起
```



### find

`find`沿着文件层次结构向下遍历，匹配符合条件的文件，执行相应的操作。

`find base_path`

使用花括号`{}`表示文件名或目录名



选项：

- `-a/-and/-o/-or`：执行逻辑与、逻辑或
- `-name/-iname`：以通配符的方式指定待查找文件名的模式。如`'*.txt'`匹配所有名字以`.txt`结尾的文件或目录。`-iname`忽略字母大小写
- `-regex/-iregex`：以正则表达式的方式指定待查找文件名的模式。如`'.*\.\(py|sh\)$'`表示以`.py`或者`.sh`结尾的文件或目录
- `!`：否定参数，排除匹配到的模式
- `-mindepth/-maxdepth`：指定开始查找的最小目录深度和最大目录深度。应把它们放在选项的最前面，提高查找效率
- `-type`：根据文件类型搜索
- `-atime/-mtime/-ctime`：时间选项。分别表示用户最近一次访问文件的时间/文件内容最后一次被修改的时间/文件元数据（例如权限或者所有权）最后一次改变的时间。可以用整数值`x`来指定天数，`x`前加`-`表示最近`x`天内，`x`前加`+`表示时间超过`x`天，不加表示恰好`x`天
- `-amin/-mmin/-cmin`：以分钟为单位的时间选项
- `-newer`：指定一个用于比较修改时间的参考文件，然后找出比参考文件更加新的所有文件和目录。如`find . -type f -newer file.txt`：找出比`file.txt`修改时间更近的所有文件。
- `-size`：基于文件大小搜索
- `-perm/-user`：基于权限或者所有权搜索
- `-delete`：删除匹配文件
- `-exec`：结合其他命令。如`find . -type f -user uucp -exec chown skb {} \;`，将`{}`替换为相应的文件名并更改文件的所有权，最后的`\;`表示的是`chown`命令的结束，如果不加转义符，shell会将分号视为`find`的结束。如果指定的命令接受多个参数（如`chown`、`cat`，它们可以接受多个文件），可以用`+`作为命令的结尾，这样`find`会生成一份包含所有搜索结果的列表，然后将其作为指定命令的参数，一次性执行，这样开销会小很多。
- `-prune`：排除某些文件或目录。如`find devel/source_path -name '.git' -prune -o -type -f`，排除`.git`目录
- `-print0`：用null分隔而不是使用默认的换行符来分隔，常和`xargs`搭配使用

例子：

```bash
# 删除当前文件夹下以a开头且不是以sh结尾的所有文件，其中\(和\)将它们中间的内容视为一个整体
find . -maxdepth 1 \( -name "a*" -a ! -name "*sh" \) -delete
# 多个命令组合实现上述功能
find . -maxdepth 1 -name "a*" | grep -v "sh$" | xargs rm -f

# 搜索时排除.git目录
find devel/source_path -name '.git' -prune -o -type f
```



### xargs

`xargs`重新格式化stdin接收到的数据，再将其作为参数提供给指定命令。默认执行`echo`命令，使用空白字符分隔元素。

`command | xargs otherCommand`



选项：

- `-n`：限制每次调用命令的参数个数
- `-d`：指定自定义分隔符。`-0`表示null，可以和`find`命令的`-print0`搭配食用
- `-I {}`：指定替换的字符串。为该命令提供的各个参数会通过stdin读取并依次替换字符串`{}`

例子：

```bash
# 统计源代码目录下所有C程序文件的行数
find src -type f -name "*.c" -print0 | xargs -0 wc -l
```



### tr

`tr`可以对来自stdin的内容进行字符替换、删除以及压缩，只能通过stdin接收输入（无法通过命令行参数接收）

`tr [option] set1 set2`，来自stdin的字符会按照位置从set1映射到set2（set1的第一个字符映射到set2的第一个字符，以此类推），然后将输出写入到stdout。如果set1长度大于set2长度，则set2会不断复制自己最后一个字符，如果set1长度小于set2，则set2多余部分会被忽略。

字符集中，如果是一串连续的字符序列，可以使用`起始字符-终止字符`，如`a-ce-z`。如果该形式不是有效的连续字符序列，则会被视为3个元素的集合（`起始字符、-、终止字符`）。也可以是`'\t'、'\n'`这些特殊字符或者其他ASCII字符



选项：

- `-d`：删除`set1`指定的字符集合，`set2`不用指定
- `-c`：补集。如果只给出`set1`，且和`-d`搭配，则删除不在`set1`中的字符；如果给出`set2`，则将不在`set1`中的字符转换为`set2`中的字符
- `-s`：将连续的多个重复字符替换为一个字符。比如`echo "Hello ,  I am  Ajax  " | tr -s ' '`可以去掉多个空格。

可以使用字符类作为集合，如`[:lower:], [:digit:]`

例子：

```bash
echo -e "1\n2\n3\n4\n5" > sum.txt # -e表示进行转义
# 将文件中的数字进行相加
cat sum.txt | echo $[ $(tr '\n' '+') 0 ]
```



### sort

`sort`可以对文本文件和stdin进行排序，`uniq`需要依赖`sort`，因为它的前提是要求输入数据必须排序。

`sort file1.txt file2.txt`



 选项：

- `-n`：按照数字排序

- `-r`：逆序排序

- `-M`：按照月份排序

- `-m`：合并多个已排序过的文件

- `-c/-C`：检查文件是否排序，`-C`是quiet模式

- `-k`：指定排序所依据的字符。如果是单个数字，则指的是列号。如果要用数字顺序排序，一定要给出`-n`

  如果需要列中的部分字符作为键，则用点号分隔两个整数来定义一个位置，然后将该范围内的第一个字符和最后一个字符用逗号连接，如`sort -k 2.3,2.4 data.txt`表示按第2列的第3～4个字符进行排序（从第1列开始数）

- `-d`：按照字典序进行排序

- 和`uniq`一起使用

  统计各行在文件中出现的次数：`sort unsorted.txt | uniq -c`

  找出重复读行：`sort unsorted.txt | uniq -d`

  使用`-s`指定跳过前N个字符，使用`-w`指定比较的字符长度。如`sort -k 2 data.txt | uniq -s 2 -w 2`表示跳过第2列的前2个字符，并用后续的2个字符进行重复性比较

  使用`-z`以null分割结果

例子：

```bash
echo -e "1\tmac\t2000\n2\twinxp\t4000\n3\tbsd\t1000\n4\tlinux\t1000" > data.txt;
# 依据第1列，以逆序的形式排序
sort -nrk 1 data.txt
# 依据第2列进行排序
sort -k 2 data.txt
```



### comm

`comm`比较两个已排序的文件，显示结果为：第一列是第一个文件独有的行，第二列是第二个文件独有的行，第三列是两个文件共有的行。支持`-`作为命令行参数，通过它可实现多个文件的比较。



选项：`-1`禁止第一列输出，`-2`禁止第二列输出，`-3`禁止第三列输出

例子：

```bash
echo -e "apple\norigin\ngold" > A.txt; echo -e "origin\ngold\ncarrot" > B.txt; sort A.txt -o A.txt; sort B.txt -o B.txt;
# 打印交集
comm -1 -2 A.txt B.txt;
```



### chattr

`chattr +i/-i file`可以将文件设置为不可修改/撤销不可修改属性。只有`root`用户才允许执行该命令。



### diff

`diff`可以生成两个文件之间的差异对比

`diff -u file1 file2`：生成一体化输出。

可以将`diff`的结果输出到文件`file.patch`，然后用`patch`命令将输出结果应用到任意一个文件，当应用于`file1`时，可以得到`file2`；当应用于`file2`时，可以得到`file1`。如`patch file1 < file.patch`。



### pushd/popd

`pushd/popd`可以用于在多个目录之间切换而无需重新输入目录（两个目录之间的切换可以用`cd -`）

`pushd directory`：将目录压入栈中，并切换到目录

`pushd +N`：按从左往右的顺序旋转栈，第N个目录处于栈顶，然后切换到该目录（下标从0开始）

`pushd -N`：按从右往左的顺序旋转栈，第N个目录处于栈顶，然后切换到该目录（下标从0开始）

`dirs`：显示目录栈

`popd`：移除栈顶目录，同时切换到新栈顶的目录

`popd +N/-N`：按从左往右的顺序或右往左的顺序移除第N个目录



例子：

```bash
pwd # 初始目录为~
pushd /project # 切换到/project目录，栈中包含/project ~
pushd output # 切换到/project/output目录，栈中包含/project/output /project ~
pushd +1 # 切换到/project目录，栈中目录为/project ~ /project/output
popd # 切换到~，栈中目录为~ /project/output
```



### wc

`wc`用于统计文件的行数、单词数、字符数。默认打印这三者。

`wc file`



选项：

- `-l`：打印行数
- `-w`：打印单词数
- `-c`：打印字符数
- `-L`：打印文件中最长一行的长度



### grep

`grep`用于文本搜索，可接受基础的正则表达式。`egrep`接受扩展的正则表达式，等同于用`grep -e`

`grep "pattern" file1 file2`



选项：

- `--color=auto`：标记出匹配到的文本
- `-o`：只输出匹配到的文本
- `-v`：输出不匹配的所有行
- `-c`：统计出匹配的行数（如果一行中有多次匹配，只统计一次）
- `-n`：结果加上匹配行所在的行号
- `-b`：结果加上匹配内容的偏移量（文件的开头作为0）
- `-l/-L`：返回匹配模式所在的文件名/返回没有匹配的文件名
- `-R/-r`：递归搜索指定的目录
- `-i`：忽略大小写
- `-e/-f`：使用多个`-e`可以指定多个模式；将多个模式定义在文件中（一个模式一行），使用`-f`指定该文件
- `--include/--exclude`：使用通配符指定或排除某些文件。如`grep "main()" . -r --include *.{c, cpp} `，它会在目录中递归搜索所有的`.c和.cpp`文件（`some{string, string2}`会被扩展为`somestring somestring2`）。`--exclude-dir`可以排除目录，`--exclude-from file`从文件中读取需要排除的文件列表
- `-Z`：用null分割结果
- `-q`：静默输出
- `-A/-B/-C N`：打印匹配结果之后的N行/打印匹配结果之前的N行/打印匹配结果之前和之后的N行

例子：

```bash
# 统计文件中匹配项的数量
echo -e "1 2 3 4\nhello\n 5 6" | egrep -o "[0-9]" | wc -l
```



### cut

`cut`根据分隔符按列切分文件，默认使用制表符作为分隔符。

`cut -f FIELD_LIST file`，`-f`指定要提取的字段，`FIELD_LIST`是需要显示的列号，由逗号分隔。如：`cut -f 2,3 file`



选项：

- `-s`：禁止没有用分隔符的行输出
- `--complement`：`-f`指定列的补集
- `-d`：设置分隔符。如`cut -f1 -d ":" /etc/passwd`

例子：

```bash
# 打印用户名和他使用的Shell
cut -f1,7 -d":" /etc/passwd --output-delimiter ","
```



### sed

`sed`可进行文本替换。

`sed 's/pattern/replace_string/' file`，替换每行中首次匹配的内容，如果用`'s/././g'`的话，表示全局替换。如果在`g`之前有数字的话，表示该行执行几次替换，如`sed 's/././2g'`表示替换前2次出现的匹配。其中`pattern`是基础正则表达式，如果要用扩展正则表达式，需要加`-E`

`sed`会将s之后出现的字符作为命令分隔符，因此`sed s:text:replace`表示以`:`为分隔符，如果分隔符出现在模式中，需要用`\`转义。

`sed /^$/d`：删除空行，`/d`告诉`sed`不执行替换操作，而是执行删除操作。

用`&`表示模式匹配到的字符串，也可以用`\1, \2`等表示在匹配的过程中出现在括号中的内容。

`sed`一般用单引号来引用，不过也可以用双引号，在调用`sed`之前会先扩展双引号中的内容。



选项：

- `-i`：修改后的数据替换原始文件。可以使用`-i.bak`的方式，替换原始文件的同时，生成一个原始文件的副本
- `-e`：使用多个`-e`可以指定多个模式

例子：

```bash
# 将digit 8替换为8
echo this is digit 8 in a number | sed 's/digit \([0-9]\)/\1/'
```



### awk

`awk 'BEGIN{ statements } pattern { statements } END { statements }' file`：这三部分是可选的，`awk`逐行处理文件，先执行`BEGIN`后的命令，接着对于匹配`pattern`的每一行，会执行命令，最后处理完整个文件之后，执行`END`后的命令。`pattern`可以是正则表达式、条件语句、行范围，如果提供了`pattern`但没有提供它后面的语句，则默认执行`print`（能接受参数，参数之间以逗号分隔，打印时会变成空格，可以用双引号作为拼接符使用）。

```bash
echo | awk '{var1="v1"; var2="v2"; var3="v3"; print var1 "-" var2 "-" var3}'
# 结果为v1-v2-v3
```

`awk`脚本可以放在单引号或者双引号中。

`awk`提供很多的内建字符串处理函数，如`split, substr`等。



特殊变量：

- `NR`：表示记录编号，当`awk`将行作为记录时，该变量相当于当前行号。
- `NF`：表示字段数量，默认的字段分隔符是空格。`$NF`是最后一个字段，`$(NF-1)`是倒数第二个字段。
- `$0`：当前记录的文本内容。
- `$1`：当前记录第一个字段的文本内容。
- `$2`：当前记录第二个字段的文本内容。

传递外部变量：

```bash
var=1000; echo | awk -v var=$var '{print var}' # 将外部值传递给awk
var1=100;var2=200; echo | awk '{print var1, var2}' var1=$var1 var2=$var2 # 另一种传递外部值的方法。当输入来自文件时，也可以使用该方法。
```

过滤模式：

```bash
awk 'NR < 5' # 行号小于5的行
awk 'NR==1, NR==4' # 行号在1～5之间的行
awk '/linux/' # 包含模式为linux的行（扩展正则表达式，写在//之间）
awk '!/linux/' # 不包含模式为linux的行
awk '/start_pattern/, /end_pattern/' # 在两个模式之间的文本
```

设置字段分隔符：

```shell
awk -F: '{ print $(NF-1) }' /etc/passwd
# 等价于
awk 'BEGIN{ FS=":" } { print $(NF-1) }' /etc/passwd
```



例子：

```bash
# 对于print，双引号作为拼接符，逗号分隔参数
echo -e "line1 f2 f3\nline2 f4 f5\nline3 f6 f7" | awk '{ print "Line no:"NR", No of fileds:"NF, "$0="$0, "$1="$1, "$2="$2, "$3="$3 }'
```



### paste

`paste`实现按列合并数据。

`paste file1 file2 file3`，默认的分隔符是制表符，可通过`-d`指定分隔符。



例子：

```bash
echo -e "1\n2\n3\n4\n5" > file1.txt; echo -e "gnu\nbash\ndash" > file2.txt; echo -e "linux" | paste file1.txt file2.txt -
```



### curl

`curl`的功能包括下载、发送各种HTTP请求以及指定HTTP头部。



选项：

- `--output`：指定输出文件名
- `--silent`：静默输出
- `--progress`：显示形如`#`的进度条
- 断点续传：`-C offset`，从offset开始下载；`-C - URL`，由`curl`推断正确的续传位置
- `-H`：设置HTTP头部
- `--limit-rate`：限制下载速度（可用单位`k、m`）
- 认证：`-u username:password`，为了安全起见一般password不写，等出现提示后再输入密码
- `-I/--head`：只打印HTTP头部信息

例子：

```bash
# 开发者工具，链接上右键，复制为cURL命令
curl 'https://www.baidu.com/' -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:89.0) Gecko/20100101 Firefox/89.0' -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8' -H 'Accept-Language: zh-CN,zh;q=0.8,zh-TW;q=0.7,zh-HK;q=0.5,en-US;q=0.3,en;q=0.2' --compressed -H 'Referer: https://www.baidu.com' -H 'Connection: keep-alive' -H 'Cookie:***' -H 'Upgrade-Insecure-Requests: 1' -H 'Cache-Control: max-age=0' --output index.html
```

https://gwliang.com/2020/05/26/linux-control-download-onedrive-files/



### ssh

能够访问远程主机上的shell，从而在其上执行交互命令并接收结果，或者是启动交互会话。

如果ssh只是在远程主机上执行交互命令并接收结果，那么是一个non-login且non-interactive的shell，无法访问环境变量，解决方法：

- 手动设置环境变量

  ```sh
  ssh user@host "export PATH=$PATH; command"
  ```



选项：

- `-C`：启用压缩
- `-p`：指定端口

例子：

```sh
# 登录远程主机
ssh user@host
# 在远程主机中执行多条命令
ssh user@host "command1; command2; command3"
# 本地系统的命令输出作为远程主机的输入，比如实现将本机的文件以tar的传给远程主机
tar -zcf LOCALFOLDER | ssh user@host "tar -zxvf -C path"
```



### scp

可以理解为基于ssh的cp命令，用于本地、远程复制。



选项：

- `-r`：以递归形式复制目录

例子：

```sh
scp -r /src /src2 user@host:/dest
```



### rsync

支持本地拷贝，远程数据传输和加密。和`cp`不同的是，会比较文件修改日期，仅复制新的文件。



选项：

- `-a`：归档操作
- `-t`：保留修改时间
- `-v`：打印细节信息
- `-z`：压缩
- `--exclude PATTERN`：通过通配符指定排除的文件
- `--exclude-from FILE`：通过文件列表指定排除的文件
- `--delete`：在目标主机处删除源端不存在的文件（默认是不会删除的）

例子：

```sh
# 复制所有的.c文件到远程主机的src目录下
rsync -t *.c user@host:/src/

rsync -avz /src/foo /dest # 与 rsync -avz /src/foo/ /dest/foo 等价，都表示把目录同步到另一个目录下，有无斜杠的区别是，有斜杠表示将进入源文件夹里面，将所有文件和文件夹复制到目标目录中，无斜杠表示在源文件夹外面，将整个源文件夹及其内部复制到目标目录中。
```



### which、whereis、whatis

`which`用于找出某个命令的位置。

`whereis`与`which`类似，不仅返回命令的路径，还能打印出命令手册及源代码的位置。

`whatis`输出命令的简短描述。



例子：

```sh
which scp # /usr/bin/scp
whereis scp # scp: /usr/bin/scp /usr/share/man/man1/scp.1.gz
whatis scp # scp (1)              - OpenSSH secure file copy
```



### lsof、netstat

列出端口以及在端口上的服务



例子：

```sh
# 列出已经打开的网络连接
lsof -i
# 列出TCP连接，并显示对应的IP、PID、程序名
netstat -ntp
```



### ps

`ps`报告活跃进程的相关信息。



选项：

- `-e/-ef/-ax/axu`：显示所有进程信息
- `-o param1,param2`：指定显示哪些信息（逗号与接下来的参数之间没有空格）
- `ps [options] e`：显示进程的环境信息（包括环境变量）。如想要确定GUI应用需要哪些环境变量，可以先手动运行GUI应用，然后用命令`ps -C xxx -eo cmd e`
- `--sort -param1,+param2,param3`：对输出进行排序，`+`表示按照升序，`-`表示按照降序
- `-C COMMAND_NAME`：找出特定命令对应的进程ID
- `-u user1,user2...`：根据有效用户列表过滤

例子：

```bash
# 杀死特定命令(如java)的进程
ps -C java -o pid | grep -v "PID" | xargs kill -9
# 或者
ps aux | grep java | grep -v "grep" | xargs kill -9
```



### cron/crontab

`cron`用于调度系统维护任务、定时任务。

```bash
minute(0~59) hour(0~23) day(1~31) month(1~12) dayOfWeek(0~6) command
```

cron表中每一行都由6个字段组成，前5个字段指定命令开始执行的时间，多个值之间用逗号分隔（不要有空格），`*`表示任意时间段，`/`表示调度的时间间隔。如：

```bash
0-40/20 5,6 * * 0 /home/dummy/script.sh # 在周日的时候，第5和第6个小时，前40分钟内，每隔20分钟执行一次脚本
```

如果需要自定义的环境变量，需要在cront表中定义（`var=value`的形式）



选项：

- `crontab -e`：编辑cron表
- 用新的cron表替换原有的：`crontab task.cron`
- `crontab -l`：查看当前用户的cron表
- `crontab -r`：删除当前用户的cron表



## 脚本实例

### 生成目录的树状视图

```bash
# 1. {}是find找到的文件名或目录名
# 2. echo的-n参数表示不输出换行符
# 3. 第一个tr删除所有的字母、下划线_、小数点.、连线符-（因为连线符在tr中有特殊的意义，因此需要转义）。经过第一个tr处理后，会把路径中的/传给第二个tr
# 4. 第二个tr将/转换为制表符\t
# 5. basename命令会去掉文件名前面的路径部分
# 6. \; 表示 basename命令结束
find . -exec sh -c 'echo -n {} | tr -d "[:alnum:]_.\-" | tr "/" "\t"; basename {}' \;
```

### 生成数据

```bash
#!/bin/bash
# 作用：生成图片

for i in {1..4}
do
        touch $i.jpg
        let j=i+20 # 用let不需要用$
        touch $j.png
done
```

### 批量重命名图片

```bash
#!/bin/bash
# 用途：重命名.jpg和.png文件
# 使用方式：rename.sh directory prefix

# 如果参数个数不等于2，打印消息并退出
if [ $# -ne 2 ]; then
        echo "Usage: $0 directory prefix"
        exit 0
fi

count=1
# 找到directory下所有的jpg和png文件，并将结果赋值给变量，然后循环遍历
for img in `find $1 -maxdepth 1 -iname '*.png' -o -iname '*.jpg' -type f`
do
		# 执行补0操作，并将结果赋值给cnt
        cnt=$(printf "%05d" $count)
        # 用贪婪的方式拿到文件扩展名，然后拼接成新的文件名
        new=$2$cnt.${img##*.}

        echo "renameing $img to $new"
        mv "$img" "$new"
        let count++
done
```

### 根据需要将部分文件移到到目标文件夹

```bash
#!/bin/bash
#用途：根据参数，将部分文件从源文件夹移动到目标文件夹
#使用方式：move_part_files.sh origin_folder dest_folder suffix file

if [ $# -ne 4 ]; then
        echo "Usage: $0 origin_folder dest_folder suffix file"
        exit 0
fi

# 1.用:替换默认的分隔符/，因此不用对/进行转义
# 2.给出的原始目录和目标目录字符串，末尾可能带有/，如 origin/，因此要把/去掉。用sed将最后的/去掉
# 3.将匹配的内容放在括号中，用\1表示该内容
origin=$(echo $1 | sed 's:\(.*\)/$:\1:g')
dest=$(echo $2 | sed 's:\(.*\)/$:\1:g')
# 读取file文件中的内容（多行数据），将origin下的目标文件移动到dest下。xargs重新格式化输入数据，并将数据所表示的数据替换成带扩展名的文件名
cat $4 | xargs -I {} mv $origin/{}.$3 $dest/{}.$3
# 如果上个命令正常退出，$?返回0
if [ $? == 0 ]; then
        echo "move success"
else
        echo "move fail"
fi
```

### 提取kindle的剪贴板至每个单独的文件

```bash
# Kindle的内容5行为一条笔记，-A表示在匹配行之后再显示4行，每条笔记以========结尾。在Windows上，这样操作完成后，笔记提取出来了，但是每条笔记中都存在--，因此用sed删除。
book="娱乐至死"
cat "My Clippings.txt" | grep "$book" -A 4 | grep "========" -B 1 | grep -v "==========" > "$book".txt; sed -i '/--/d' "$book".txt
```

### 在所有主机上同时执行相同的命令

```bash
#!/bin/bash
if [ $# -ne 1 ]; then
        echo "Usage: $0 command"
        exit 0
fi

# 遍历主机
for target in namenode datanode1 datanode2
do
        echo "---------$target----------"
        ssh -C $target "export PATH=${PATH}; $@"
done
```

`xcall.sh`脚本如上，为了方便使用，可以使用别名`alias xcall=xcall.sh`

### 将文件同步到所有主机上

```bash
#!/bin/bash
if [ $# -ne 1 ]; then
        echo "Usage: $0 folder"
        exit 0
fi

absolute_path=$(realpath $1)

for target in datanode1 datanode2
do
        echo "---------$target------------"
        rsync -avzq ${absolute_path}/ ${target}:${absolute_path}
done
```

`xsync.sh`脚本如上，为了方便使用，可以使用别名`alias xsync=xsync.sh`


### 批量移动文件

背景：为了做ETL，在load之后还有计算逻辑，两者用消息队列解耦。由于计算逻辑复杂，如果数据量太大，一次性全量灌库会导致队列堵住，所以要分批次进行灌库。

```bash
#!/bin/bash
# 跳过行数，比如可以指定0。每个批次有50个文件
# 文件名类似00001.txt, 00002.txt这种

if [ $# -ne 1 ]; then
    echo "Usage: $0 skip_rows"
    exit 1
fi

DEST=~/var/data/***/data_export
SRC=~/var/data/***/backup_data_export

if [ -d ${DEST} ]; then
    moved_files=$(ls ${DEST})
    file_number=$(ls ${DEST} | wc -l)
    if [ ${file_number} -gt 0 ]; then
        cd ${DEST}
        mv ${moved_files} ${SRC}/
    fi
else
    mkdir -p "${DEST}"
fi

skip_rows=$1
(( skip_rows += 1 ))
files=$(ls ${SRC} | sort -d | tail -n +${skip_rows} | head -50 | xargs echo)
for file in ${files[@]}; do
    mv "${SRC}/${file}" "${DEST}"
done
```

### 处理 Mongo 导出的数组

根据需要导出 Mongo 中的数据如：`68aaa2baa90a1faaa6aaa3b6c4605d522e630761,"[""111111111111"",""111111111112""]",2018-06-16`，需要将数组形式的数据切分成多条数据。

```bash
awk -F '""' '{ split($1, arr, ","); id=arr[1]; split($NF, arr, ","); date=arr[2]; for(i=2;i<NF;i++) { if (length($i) == 12) { print id","$i","date; } } }' a.txt > processed_a.txt
```