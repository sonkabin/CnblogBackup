## 背景

Windows 上配置了 git ，支持部分 Linux 命令，也存在不支持的 Linux 命令，比如 rsync 。我想要用 rsync 实现文件的同步，因此耗费了一个上午进行搜索和配置，把过程记录下，下次有需要可以按图索骥。

## 过程

### 下载安装包并解压

[peazip下载](https://peazip.github.io/peazip-64bit.html)：用于解压 zst 压缩文件

[package下载](http://www2.futureware.at/~nickoe/msys2-mirror/msys/x86_64/)：下载 rsync-3.2.3-2-x86_64.pkg.tar.zst 、 libzstd-1.4.9-1-x86_64.pkg.tar.zst （可选）、 libxxhash-0.8.0-1-x86_64.pkg.tar.zst （可选）、 liblz4-1.9.3-1-x86_64.pkg.tar.zst （可选）

### 配置

1. rsync 文件夹里的 bin 和 lib 的内容分别复制到 Git/usr/bin 和 Git/usr/lib 下
2. 打开 Git Bash ，运行 `rsync -v` ，如果报 `msys-zstd-1.dll not found` ，则将 libzstd 文件夹里的 bin 的内容复制到 Git/usr/bin 下
3. 重新运行，如果报 `msys-xxhash-0.dll not found` ，则将 libxxhash 文件夹里的 bin 的内容复制到 Git/usr/bin 下，并将其重命名为 `msys-xxhash-0.dll`
4. 重新运行，如果报 `msys-lz4-1.dll not found` ，则将 liblz4 文件夹里的 bin 的内容复制到 Git/usr/bin 下
5. 重新运行，如果报 `msys-crypto-1.1.dll not found` ，则将 Git/usr/bin 文件夹里的 msys-crypto-1.0.0.dll 复制到当前目录，并重命名为 `msys-crypto-1.1.dll`

## 参考

https://blog.csdn.net/Blazar/article/details/109710997

https://shchae7.medium.com/how-to-use-rsync-on-git-bash-6c6bba6a03ca

https://www.zhihu.com/question/351137392