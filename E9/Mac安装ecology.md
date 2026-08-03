# Mac系统安装Ecology本地Demo教程

官方没有mac系统安装本地demo的教程，实际上苹果电脑是可以安装本地demo的，我来分享一下方法。

适用于M1、M2、英特尔的苹果电脑

前面的一版教程没有对数据库参数进行设置，导致系统运行中会出现一点问题，在这一版添加了数据库参数的设置，可以直接初始化数据库了，另外还增加了解决授权丢失的解决方法。

## 下载Ecology以及Resin

- 可以到这个地址下载本地demo，这个是官方给出的下载地址

链接: https://pan.baidu.com/s/1GHAPg4AASJ-3u\_YcciQWtQ

密码: sl3i

- 选择resin
![image1](files/image1.png)

- 选择linux
![image2](files/image2.png)

- 然后我们只需要下载这个就可以了
![image3](files/image3.png)

- Resin也是在同一个目录里面下载
- ecology和resin都下载好之后，你找个地方创建weaver文件夹，然后把ecology和resin都解压到weaver文件夹里
![image4](files/image4.png)

## 下载JDK

E9只能用8u151这个版本的jdk运行，否则启动会报错

- 到这个地址下载jdk，选择8u151

JDK8 下载 - 编程宝库 (codebaoku.com)
![image5](files/image5.png)

- 再选择mac系统的安装包
![image6](files/image6.png)

- 下载之后直接安装就可以了

## 配置Resin

- 编辑resin目录下的conf/resin.xml文件，修改应用程序路径，改成你的ecology路径
![image7](files/image7.png)

- 编辑conf/resin.xml，修改编译器路径，改成你java安装路径里的javac目录
![image8](files/image8.png)

- 默认http端口是80，如果你的http端口被占用，则需要修改Resin/conf/resin.properties文件，将端口改为其它的
![image9](files/image9.png)

- 修改resin 运行JDK，用文本编辑器打开resin/bin/resin.sh 文件，将JAVA\_HOME改为刚才安装的JDK路径
![image10](files/image10.png)

## 安装数据库

下面以mysql为例

- 到mysql官网下载mysql

MySQL :: Download MySQL Community Server

- 点第二个标签页，然后选择一个比较旧的版本，我选择的是16版本，当然你也可以尝试选择26版本，从26版本开始适配了ARM架构
![image11](files/image11.png)

- 选择第一个安装版，进行下载
![image12](files/image12.png)

- 下载之后安装，安装时选择第一项，他会让你设置root用户的密码，至少是密码+数字的组合，请记住你设置的密码
![image13](files/image13.png)

## 设置数据库

- 我们要在etc目录下新建一个mysql的配置文件，打开终端并输入命令 sudo vim /etc/my.cnf ，然后输入你的开机密码
- 按a进入插入模式，粘贴以下内容

```ini
[mysqld]
datadir=/Users/yaolilin/weaver/mysql/data
basedir=/Users/yaolilin/weaver/mysql
character-set-server=utf8
innodb_buffer_pool_size=512M
log_bin_trust_function_creators=1
lower_case_table_names=1
max_connections=5000
sql_mode=NO_ENGINE_SUBSTITUTION,STRICT_TRANS_TABLES
transaction_isolation=READ-COMMITTED
group_concat_max_len=102400
```

- 把datadir和basedir换成你的实际目录，这两个参数可以在系统设置中打开mysql设置查看
![image14](files/image14.png)

- 按esc键退出插入模式，然后按:键并输入wq保存并退出
![image15](files/image15.png)

- 打开mysql设置，点击初始化数据库，输入root密码
![image16](files/image16.png)

![image17](files/image17.png)

- 打开mysql设置然后点击安装路径，在访达中进入bin目录并在此目录中用终端打开
![image18](files/image18.png)

![image19](files/image19.png)

- 连接mysql数据库，终端输入 mysql -uroot -p'youpassword'
- 将youpassword换成你root密码，密码要在引号内
- 链接到数据库后执行 CREATE DATABASE ecology;

## 初始化数据库可能的错误

Mysql 初始化问题可以查看 MySQL常见问题汇总 (e-cology.com.cn)

## 运行Ecology

- 启动与停止服务：在Resin/bin文件夹中打开终端，执行sh resin.sh start 就是启动服务，执行sh resin.sh stop就是停止服务，此外你还可以执行 sh startresin.sh 和 sh stopresin.sh 来启动和停止服务，不过要修改startresin.sh和stopresin.sh这两个文件，将里面的resin.sh路径改为你的实际路径，并在路径前面加上 sh，例如：
- sh /Users/yaolilin/weaver/Resin/bin/resin.sh start
- 启动resin服务
- 等待服务启动成功，你可以到resin/log/jvm-app-0.log 里查看日志，如果你看到这句就说明服务已经启动成功了，http listening to \*:80是Http端口，即系统访问路径的端口
![image20](files/image20.png)

- 服务启动后，进入ecology，提示初始化数据库，数据库类型选择mysql，输入你的数据库用户名和密码，然后点击初始化数据库。
![image21](files/image21.png)

验证码：ecology/WEB-INF/code.key 文件中

## 登陆系统

进入到登陆页面
![image22](files/image22.png)

恭喜，你已经成功安装了本地Demo，如果在安装过程中有什么困难，可以和我交流

## 打入非标包

- 非标包可以在这里下载
- 链接: https://pan.baidu.com/s/1O4wt9dYp0f7TYhoKiZbP\_A?pwd=bi00 提取码: bi00
- 下载后解压非标包，然后将解压出来的ecology覆盖到weaver/ecology
- 重启服务，终端执行sh resin.sh stop ，再执行sh resin.sh start

## 解决授权丢失问题

可能你会发现刚刚授权没多久，重启服务后又说授权过期了，我查看了下代码，它是默认根据你的mac地址去识别你的身份的，可能由于跟mac的环境有关，获取到的mac地址不一样，导致无法找到以前的授权。

可以把身份识别方式改为通过数据库获取，这样就能保证每次获取到的身份一样了。

- 修改ecology/WEB-INF/prop/weaver.propertie，添加参数：
- LicensePolicy = db
- 2.重启服务后再进行重新授权
