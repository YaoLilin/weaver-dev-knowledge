## 场景

建模查询批量编辑保存时需要做必填校验

![](Pasted%20image%2020260421152032.png)
## 思路

需要重写按钮的点击事件的逻辑，在事件内先执行自定义的逻辑，再执行原逻辑，也就是代理的操作

## 重写顶部按钮点击事件

这个没有包括下拉菜单

![](Pasted%20image%2020260421152148.png)

1.获取 WeaTop 组件参数

2.从组件参数中遍历 buttons 属性，找到批量保存按钮的参数，可以根据元素的 props.id 或 props.ecId 进行判断，有时 props.id 会不存在

3.替换的 props 的 onClick

```javascript
ecodeSDK.overwritePropsFnQueueMapSet('WeaTop', {
    fn: (props) => {
        if (isTargetSearchPage()) {
            const saveButtonProps = findBatchSaveButtonProps(props);
            if (!saveButtonProps) {
                return
            }
            const handleClick = saveButtonProps.onClick;
            saveButtonProps.onClick = (e) => {
                if (verifyEditField()) {
                    // 执行原动作，进行提交
                    handleClick(e);
                }
            }
            if (isShowRequiredFlag()) {
                // 添加必填标识
                addRequiredFlag();
            }
        }
    }
});
function findBatchSaveButtonProps(props) {
    if (props.buttons) {
        const button = props.buttons.find(i => i.props && i.props.id && i.props.id === 'doBatchStorage' || (i.props.ecId && i.props.ecId.includes("doBatchStorage")));
        if (button) {
            return button.props;
        }
    }
    return null;
}
```

## 重写顶部下拉菜单和右键菜单逻辑

这个重写已经包括顶部下拉菜单和右键菜单

在点击批量保存时先进行自定义校验，通过后再执行原逻辑

![](Pasted%20image%2020260421152207.png)
![](Pasted%20image%2020260421152215.png)
```javascript
// 重写顶部下拉按钮中的保存按钮逻辑
ecodeSDK.overwritePropsFnQueueMapSet('Menu.Item', {
    fn: (props) => {
        if (isTargetPage()) {
          const {eventKey} = props;
          if(eventKey){
            if(eventKey === 'doBatchStorage'){
              function proxyFunction(originalFunc){
                return function(...args){
                  showComfirm(()=> originalFunc.apply(this,args));
                }
              }
              props.onClick = proxyFunction(props.onClick);
            }
          }
        }
    }
});
```

虽然也可以重写 WeaTop 组件的 dropMenuDatas 参数中的按钮点击事件，但是原先是没有这个点击事件的，按钮的点击事件是在 Menu.Item 组件中，如果在dropMenuDatas 参数中添加点击事件的话就和 Menu.Item 点击事件重复了

## 重写右键菜单点击事件

![Pasted image 20260413085610.png](./files/Pasted_image_2026040713085610.png)
1.获取 WeaRightMenu 组件参数

2.替换参数中的 onClick 函数，该函数通过点击菜单触发，函数中有个参数用来判断是点击哪个菜单

```javascript
ecodeSDK.overwritePropsFnQueueMapSet('WeaRightMenu', {
    fn: (props) => {
        if (isTargetSearchPage()) {
            if(props.datas){
              const handleClick = props.onClick;
              props.onClick = (e)=>{
                if(e === 'doBatchStorage'){
                  if(verifyEditField()){
                    handleClick(e);
                  }
                  return;
                }
                handleClick(e);
              }
            }
        }
    },
    desc:'右键菜单中的批量保存按钮事件重写，点击时先进行必填校验再提交'
});
```

## 示例：批量修改点批量保存时弹出一个对话框，点击确定后再提交

![Pasted image 20260413085719.png](./files/Pasted_image_2026040713085719.png)

```javascript
// 重写顶部保存按钮逻辑
ecodeSDK.overwritePropsFnQueueMapSet('WeaTop', {
    fn: (props) => {
        if (isTargetPage()) {
            const saveButtonProps = findBatchSaveButtonProps(props);
            if (!saveButtonProps) {
                return
            }
            const handleClick = saveButtonProps.onClick;
            saveButtonProps.onClick = (e) => {
                if(isShowComfirm()){
                  showComfirm(()=> handleClick(e));
                }else{
                  handleClick(e);
                }
            };
        }
    }
});

// 重写顶部下拉按钮和右键菜单中的保存按钮逻辑
ecodeSDK.overwritePropsFnQueueMapSet('Menu.Item', {
    fn: (props) => {
        if (isTargetPage()) {
          const {eventKey} = props;
          if(eventKey){
            if(eventKey === 'doBatchStorage'){
              function proxyFunction(originalFunc){
                return function(...args){
                  if(isShowComfirm()){
                    showComfirm(()=> originalFunc.apply(this,args));
                  }else{
                    originalFunc.apply(this,args);
                  }
                }
              }
              props.onClick = proxyFunction(props.onClick);
            }
          }
        }
    }
});

function isTargetPage(){
  const url = location.href;
  const config = ecodeSDK.getCom('${appId}','config');
  if(!config){
    return false;
  }
  if(url.includes('main/cube/search')){
    const customId = ModeList.getCustomID();
    return customId == config.searchId
  }
  return false;
}

function findBatchSaveButtonProps(props) {
    if (props.buttons) {
        const button = props.buttons.find(i => i.props && i.props.id && i.props.id === 'doBatchStorage' || (i.props.ecId && i.props.ecId.includes("doBatchStorage")));
        if (button) {
            return button.props;
        }
    }
    return null;
}

function isShowComfirm(){
  const {stateFieldName} = ecodeSDK.getCom('${appId}','config');
  const data = ModeList.getBatchEditDatas();
  let result = false;
  data.forEach(i =>{
    if(i[stateFieldName] === '0'){
      result = true;
    }
  });
  return result;
}

function showComfirm(onClickOk) {
  const text = "按公司规定，未经发布的文件无效，请确保完成以下2个步骤：</br>"+
                "1、打开文件添加“文档共享”，建议按照公司或部门设置（含下级），确保需要执行的相关区域能查看文件；</br>"+
                "2、对适用范围内人员，通过邮件等方式通知文件发布信息，发布模板参考如下。"
  ModeList.showConfirm(text, onClickOk, null, {
    title: "提示",       //弹确认框的title，仅PC端有效     
    okText: "确定",          //自定义确认按钮名称    
    cancelText: "返回"     //自定义取消按钮名称 
  })
}

```