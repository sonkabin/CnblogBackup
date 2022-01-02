## 前言

有一个需求，将局域网中的一台Windows和一台Ubuntu的时间进行同步，Ubuntu作为主服务器，Windows去同步Ubuntu的时间。版本是Ubuntu20.04、Windows10。

## Ubuntu配置

1. 安装chronyc

   ```shell
   sudo apt install chronyc
   # 如果有冲突，解决不了的话，用 aptitude 代替 apt
   ```

2. 配置chronyc

   ```shell
   sudo vim /etc/chronyc/chronyc.conf
   # 添加以下内容
   allow 111.111.111.0/24 # 配置允许访问的IP，这里配置为111.111.111网段下的所有IP
   local stratum 10 # 当server中提供的公网NTP服务器不可用时，采用本地时间作为同步标准
   ```

3. 重启chronyc

   ```shell
   sudo service chronyc restart
   ```

4. 查看chronyc信息

   ```shell
   chronyc tracking # 显示系统时间信息
   ```

5. 新版的Ubuntu使用timedatectl，替代了老旧的ntpd和ntpdate

   ```shell
   sudo timedatectl set-ntp yes # 开始自动时间同步到远程NTP服务器
   
   timedatectl # 查看详细信息
   ```

参考：

https://blog.csdn.net/Rengar_Yang/article/details/107078711

https://www.cnblogs.com/pipci/p/12871993.html

https://developer.aliyun.com/article/86789

## Windows配置

1. 配置Windows服务自启动。服务名为Windows Time

2. 编辑注册表

   1）输入Regedit打开注册表

   2）进入HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\W32Time\TimeProviders\NtpClient

   3）SpecialPollInterval的值更改为900（单位是秒，可根据实际情况设置）

   4）新建DWORD，数值名称为SpecialInterval，数值数据为1

3. 配置时间服务器

   控制面板->时钟、语言和区域->时间和日期->Internet时间->更改设置，将Ubuntu的IP地址输入服务器中

4. 重启Windows Time服务

参考：

https://zhuanlan.zhihu.com/p/372441634