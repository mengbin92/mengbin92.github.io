# 使用boot.iso镜像安装OL8  

本文记录使用boot.iso镜像安装Oracle Linux 8。  

## 镜像下载  

Oracle Linux 8 boot镜像可以从[这里](http://yum.oracle.com/oracle-linux-isos.html)下载。  

## 安装  

Oracle Linux 8 boot镜像安装系统跟使用全镜像安装过程基本一样，除了需要自己手动配置**软件源**，我这里使用的时Oracle官方提供的yum源：  

| 名称          | 地址                                                             | 类型           |
| :------------ | :--------------------------------------------------------------- | :------------- |
| baseos        | https://yum.oracle.com/repo/OracleLinux/OL8/baseos/latest/x86_64 | Repository URL |
| ol8_AppStream | https://yum.oracle.com/repo/OracleLinux/OL8/appstream/x86_64/    | Repository URL |
| ol8_UEKR6     | https://yum.oracle.com/repo/OracleLinux/OL8/UEKR6/x86_64/        | Repository URL |

---

> 声明：本作品采用[署名-非商业性使用-相同方式共享 4.0 国际 (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh)进行许可，使用时请注明出处。
> Author: MonsterMeng92

---  
