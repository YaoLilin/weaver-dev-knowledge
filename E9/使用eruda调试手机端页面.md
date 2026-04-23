该工具可以在移动端页面显示控制台
效果：

![339](Pasted%20image%2020260421152359.png)

该工具不支持断点调试

github 地址：[eruda/README_CN.md at master · liriliri/eruda · GitHub](https://github.com/liriliri/eruda/blob/master/README_CN.md)

可以通过嵌入js的方式加载调试工具

## 使用方法

需要在进入页面后加载外部js ，js 地址：`//cdn.bootcdn.net/ajax/libs/eruda/2.3.3/eruda.js`

示例：

使用 ecode 在页面进入后加载 js

```javascript
// 动态加载js
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
// 显示调试工具，使用了eruda进行调试
loadJS('//cdn.bootcdn.net/ajax/libs/eruda/2.3.3/eruda.js',function(){
    eruda.init();
});
```
