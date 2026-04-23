## 整体思路

将表单容器元素改为横向排列，然后再右边新建一个元素，把流程签字意见元素移动到新元素中

![](Pasted%20image%2020260421172248.png)

![697](Pasted%20image%2020260421172256.png)

## 代码

使用ecode开发

```javascript
import { regOvProps } from '@weapp/utils';

let isAppendNewDiv = false;
let isMove = false;
// 获取签字意见组件参数，不对其修改，只是作为执行逻辑的时机
regOvProps('weappWorkflow', 'WFFPSignList', (props) => {
  if (props.weId.endsWith('_j21eon') && location.href.includes('sp/ebdfpage/card')) {
    // 获取表单容器元素，设置布局为flex横向排列
    const container = document.querySelector('.wffp-frame-full-body');
    container.style.display = 'flex';
    document.querySelector('.wffp-right-menus').style.flex = '3';
    let newDev;
    if (!isAppendNewDiv) {
      // 在表单右侧添加一个元素，用来存放签字意见
      container.appendChild(createNewDiv());
      isAppendNewDiv = true;
    } else {
      newDev = document.getElementById('new-signature');
    }
    if (!isMove) {
      // 将签字意见元素移动到新添加的元素中
      const signatureEle = document.querySelector('.weapp-workflow-comment-list');
      if (signatureEle) {
        newDev.appendChild(signatureEle);
        isMove = true;
      }
    }

  }
  return props;
}, 1);

function createNewDiv() {
  const newDev = document.createElement('div');
  newDev.id = 'new-signature';
  newDev.style.flex = '1';
  newDev.style.padding = '10px 0px 0px 20px';
  return newDev;
}
```