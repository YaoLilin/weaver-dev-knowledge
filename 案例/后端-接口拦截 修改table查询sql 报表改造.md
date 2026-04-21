## 用法

在后端做一个接口拦截

![Pasted image 20260407095957.png](./files/Pasted_image_2026040707095957.png)

我们可以获取接口的请求参数，来进行业务判断，判断是不是我们要修改的表格

![Pasted image 20260407100028.png](./files/Pasted_image_2026040707100028.png)

```java
String  wid = Util.null2String(params.get("wfid"));
String  fieldId = Util.null2String(params.get("fieldid"));
```

- 获取到dataKey，然后获取DefaultWeaTable对象，获取到sql

```java
DefaultWeaTable table = WeaTableTools.checkTableStringConfig(dataKey,DefaultWeaTable.class);
String sqlWhere = table.getSqlwhere();
String sqlForm = table.getSqlform();
String backFields = table.getBackfields();
```

- 修改sql后要进行刷新

```java
// 刷新dataKey中的旧table对象
WeaTableTools.setTableStringVal(dataKey,WeaTableTools.toTableString(table));
```

- 可以获取到列，来对列进行修改，比如列宽什么的

![Pasted image 20260407100150.png](./files/Pasted_image_2026040707100150.png)

## 示例-修改文档浏览框的sql，限制只能浏览到某个文档

```java
@WeaReplaceAfter(value = "/api/public/browser/data/9",order = 1,description = "")
public String after(WeaAfterReplaceParam param) throws Exception {
    Map<String ,Object> params = param.getParamMap();
    // 获取接口中的请求参数
    String  wid = Util.null2String(params.get("wfid"));
    String  fieldId = Util.null2String(params.get("fieldid"));
    JSONObject result = JSONObject.parseObject(param.getData());
    String dataKey = result.getString("datas");
    if (!"63".equals(wid) && !"7019".equals(fieldId)){
        return param.getData();
    }

    // 取得DefaultWeaTable
    DefaultWeaTable table = WeaTableTools.checkTableStringConfig(dataKey,DefaultWeaTable.class);
    String sqlWhere = table.getSqlwhere();
    String sqlForm = table.getSqlform();
    String backFields = table.getBackfields();

    sqlWhere += " AND t1.id =25 ";
    table.setSqlwhere(sqlWhere);

    // 刷新dataKey中的旧table对象
    WeaTableTools.setTableStringVal(dataKey,WeaTableTools.toTableString(table));

    return param.getData();
}
```

## 示例 - 在流程待办列表添加创建人部门一列

思路：

接口拦截获取到sql，添加查询创建人部门的查询sql，创建新的列对象作为创建人部门列，添加到table的列里，添加创建人部门查询列

效果：

![Pasted image 20260407100246.png](./files/Pasted_image_2026040707100246.png)

代码：

```java
package com.engine.interfaces.demo.intercept.service.impl;

import com.alibaba.fastjson.JSONObject;
import com.weaverboot.frame.ioc.anno.classAnno.WeaIocReplaceComponent;
import com.weaverboot.frame.ioc.anno.methodAnno.WeaReplaceAfter;
import com.weaverboot.frame.ioc.handler.replace.weaReplaceParam.impl.WeaAfterReplaceParam;
import com.weaverboot.tools.componentTools.table.WeaTableTools;
import com.weaverboot.tools.enumTools.weaComponent.WeaAlignEnum;
import com.weaverboot.tools.enumTools.weaComponent.WeaBooleanEnum;
import com.weaverboot.weaComponent.impl.weaTable.column.inte.AbstractWeaTableColumn;
import com.weaverboot.weaComponent.impl.weaTable.table.impl.DefaultWeaTable;
import weaver.general.Util;

import java.util.List;
import java.util.Map;

/**
 * @author 姚礼林
 * @desc TODO
 * @date 2023/9/14
 */
@WeaIocReplaceComponent("TodoTableIntercept")
public class TodoTableIntercept {

    /**
     * 在流程待办列表添加创建人部门列
     */
    @WeaReplaceAfter(value = "/api/workflow/reqlist/splitPageKey", order = 1, description = "")
    public String after(WeaAfterReplaceParam param) throws Exception {
        Map<String, Object> params = param.getParamMap();
        JSONObject result = JSONObject.parseObject(param.getData());
        String dataKey = result.getString("sessionkey");
        String viewScope = Util.null2String(params.get("viewScope"));
        // 判断是否为流程待办列表
        if (!"doing".equals(viewScope)) {
            return param.getData();
        }

        DefaultWeaTable table = WeaTableTools.checkTableStringConfig(dataKey, DefaultWeaTable.class);
        String sqlForm = table.getSqlform();
        String backFields = table.getBackfields();

        int splitIndex = " from (select  requestid,".length() - 1;
        String frontSql = sqlForm.substring(0, splitIndex + 1);
        String rearSql = sqlForm.substring(splitIndex+1);

        // 在sql查询里添加一个查询创建人部门
        String addSql = "(SELECT d.departmentname from hrmdepartment d,hrmresource h where d.id = h.DEPARTMENTID and h.id = t1.creater) dep1 ,";
        sqlForm = frontSql + addSql + rearSql;
        table.setSqlform(sqlForm);

        // 创建一个列对象，作为创建人部门的列
        DepColumn depColumn = new DepColumn();
        depColumn.setHide(WeaBooleanEnum.FALSE);
        // dep1就是sql里的列名
        depColumn.setColumn("dep1");
        depColumn.setText("创建人部门");
        depColumn.setDataalign(WeaAlignEnum.LEFT);
        depColumn.setWidth("9%");

        // 将列对象添加到表格的列里
        List<AbstractWeaTableColumn> cols = table.getColumns();
        cols.add(2,depColumn);
        table.setColumns(cols);

        // 添加查询字段
        backFields+=",dep1";
        table.setBackfields(backFields);

        // 刷新dataKey中的旧table对象
        WeaTableTools.setTableStringVal(dataKey, WeaTableTools.toTableString(table));

        return param.getData();
    }

    static class DepColumn extends AbstractWeaTableColumn{

    }
}
```

## 抛出空指针问题

对某些表格进行拦截修改时可能会抛出空指针异常的问题（如下方标出的代码）

原因是在调用 WeaTableTools.parseWeaTableBasic() 方法时 root 对象缺少了 tabletype 属性，导致报错

![Pasted image 20260407100346.png](./files/Pasted_image_2026040707100346.png)

解决方法是获取 WeaTableTools 类的源码，将类复制到自己的路径中，并修改源码如下图，在获取 DefaultWeaTable 对象时使用该类

![Pasted image 20260407100401.png](./files/Pasted_image_2026040707100401.png)

```java
DefaultWeaTable table = com.customization.yll.liuzhousteel.intercept.impl.WeaTableTools.
        checkTableStringConfig(dataKey,DefaultWeaTable.class);
```

## 参考

[E9标准报表组件后端改造场景培训录屏-陈昌岭.mp4_免费高速下载|百度网盘-分享无限制 (baidu.com)](https://pan.baidu.com/s/1q0KCzck8Ad7Q7jDIAVLW0Q)

密码：leof

