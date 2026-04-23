该工具不能 debug 调试

工具主页：[chii/README_CN.md at master · liriliri/chii · GitHub](https://github.com/liriliri/chii/blob/master/README_CN.md)
## 效果

![](Pasted%20image%2020260421152315.png)

![](Pasted%20image%2020260421152322.png)

## 使用方法

需要在电脑上启动调试服务，按照主页的方法进行安装即可

### 安装

```
npm install chii -g
```

### 运行

```
chii start -p 8080
```

### 在移动端页面上连接调试

在移动端进入到页面时，需要连接到电脑上的调试地址，手机和电脑需要在同一局域网内，因此需要在页面进入后执行一段 js ，你可以使用 ecode 把这段 js 加进去

```javascript
function loadJS(url, callback) {
  var script = document.createElement('script'),
    fn = callback || function () { };
  script.type = 'text/javascript';
  //IE
  if (script.readyState) {
    script.onreadystatechange = function () {
      if (script.readyState == 'loaded' || script.readyState == 'complete') {
        script.onreadystatechange = null;
        fn();
      }
    };
  } else {
    //其他浏览器
    script.onload = function () {
      fn();
    };
  }
  script.src = url;
  document.getElementsByTagName('head')[0].appendChild(script);
}

if(location.href.includes('requestid=3079608')){
  // 显示调试工具，使用了eruda进行调试
  loadJS('http://192.168.110.11:8888/target.js',function(){
  });
}
```

http://192.168.110.11:8888 为电脑的调试服务地址