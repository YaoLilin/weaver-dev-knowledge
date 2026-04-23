## 需求描述

第三方通过标准功能的统一待办推送把待办流程推送到OA，推送后在待办里可以显示第三方的流程，但流程只是个第三方地址的链接，需要点击该链接后单点到第三方，进入第三方系统的流程页面。

## 实现逻辑

可以在统一待办中配置跳转的中转地址，当在 OA 点击待办进行跳转时，就会跳转到这个地址，我们可以创建 JSP 文件或接口来实现单点跳转到第三方系统，在中转地址中系统会传入一些参数，可以获取到当前环境信息。

	如果想 PC 和移动端公用跳转逻辑，可以使用同一个中转地址，使用参数区分是 pc 端还是移动端

![](Pasted%20image%2020260421151709.png)

下面是使用 JSP 进行单点跳转的示例：

```java
<%@ page import="weaver.hrm.User" %>
<%@ page import="weaver.hrm.HrmUserVarify" %>
<%@ page import="weaver.integration.logging.Logger" %>
<%@ page import="weaver.integration.logging.LoggerFactory" %>
<%@ page import="weaver.conn.RecordSet" %>
<%@ page import="java.util.Map" %>
<%@ page import="java.util.List" %>
<%@ page import="java.util.ArrayList" %>
<%@ page import="java.util.HashMap" %>
<%@ page import="java.util.stream.Collectors" %>
<%@ page import="weaver.ofs.service.OfsSysInfoService" %>
<%@ page import="weaver.general.Util" %>
<%@ page import="weaver.ofs.bean.OfsSysInfo" %>
<%@ page import="weaver.ofs.manager.utils.OfsTodoDataUtils" %>
<%@ page import="weaver.ofs.bean.OfsTodoData" %>
<%@ page import="weaver.ofs.dao.OfsRequestBaseDao" %>
<%@ page import="java.net.URLEncoder" %>
<%@ page language="java" contentType="text/html; charset=UTF-8" %>

<%
    Logger logger = LoggerFactory.getLogger("test.jsp");
    RecordSet rs = new RecordSet();
    User user = HrmUserVarify.getUser(request,response);
    int userId = user.getUID();
    String sysId = request.getParameter("sysId") ;
    String workflowId = request.getParameter("workflowId") ;
    String flowId = request.getParameter("flowId") ;
    String type = request.getParameter("type");

	// 获取当前第三方系统待办的原始跳转地址
    OfsSysInfoService ofsSysInfoService = new OfsSysInfoService() ;
    OfsSysInfo ofsSysInfo = ofsSysInfoService.getOneBean(Util.getIntValue(sysId , 0)) ;
    OfsTodoDataUtils todoDataUtils = new OfsTodoDataUtils() ;
    OfsRequestBaseDao ofsRequestBaseDao = new OfsRequestBaseDao() ;
    String requestId = ofsRequestBaseDao.getRequestid(ofsSysInfo.getSyscode() , Util.getIntValue(workflowId , 0) , flowId , rs.getDBType()) ;
    OfsTodoData todoData = todoDataUtils.getTodoData(requestId , Util.null2String(userId)) ;
    logger.info("todoData:"+todoData);
    String url ;
    if ("pc".equals(type)){
        url = todoData.getPcurl();
        logger.info("pc跳转链接："+url);
    }else {
        url = todoData.getAppurl();
        logger.info("移动端跳转链接："+url);
    }
    url = URLEncoder.encode(url,"UTF-8");
    url = "/jsp/workflow/ssoHlyPage.jsp?type="+type+"&url="+url;
    logger.info("最终跳转地址："+url);
%>
<script>
    location.href="<%=url%>"
</script>
```

通过 `OfsSysInfoService` 可获取当前待办的信息
