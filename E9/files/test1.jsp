
<%@ page language="java" contentType="text/html; charset=UTF-8" %>

<%
    out.println("user.country="+System.getProperty("user.country")+";");
    out.println("user.language="+System.getProperty("user.language")+";");
    out.println("file.encoding="+System.getProperty("file.encoding")+";");
    out.println("sun.jnu.encoding="+System.getProperty("sun.jnu.encoding")+";");

%>

