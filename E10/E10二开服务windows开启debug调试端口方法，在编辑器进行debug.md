开启调试端口后就能在编辑器中进行代码 debug 调试

## Windows 调试端口打开方法

1.打开运行，输入 regedit 打开注册表

2.在注册表内找到 `HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Apache Software Foundation\Procrun 2.0\weaver_weaver-secondev`，或者使用查找搜索 `weaver_weaver-secondev`

![](files/Pasted%20image%2020260709113046.png)

![](files/Pasted%20image%2020260709113055.png)

3.修改 Options 选项，添加以下参数，注意行后不要有空格，其中9088是调试端口，可以改成你想要的

```
-server
-Xdebug
-Xnoagent
-Djava.compiler=NONE
-Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=9088
```

![](files/Pasted%20image%2020260709113157.png)

![](files/Pasted%20image%2020260709113211.png)

4.重启二开服务

5.使用 idea 配置jvm调试

![](files/Pasted%20image%2020260709113232.png)

![](files/Pasted%20image%2020260709113256.png)

host 为 e10 所在的ip，如果是本机就是 localhost ，port 填你刚才在jvm参数中添加的调试端口

![](files/Pasted%20image%2020260709113325.png)

6.点击 debugger 图标进行调试
![](files/Pasted%20image%2020260709113348.png)

![](files/Pasted%20image%2020260709113403.png)

## Linux 调试端口打开方法

如果你是 linux ,可以在编辑 `weaver\weaver-secondev-service\bin\catalina.sh` 文件，在上面添加 jvm 参数：

```
export JAVA_OPTS='-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=9088'
```

![](files/Pasted%20image%2020260709113643.png)

## 注意

禁止在客户生产环境上添加调试端口，调试只是为了方便二次开发