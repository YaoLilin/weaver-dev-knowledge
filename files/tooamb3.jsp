<%@page import="com.westvalley.util.LogUtil"%>
<%@page import="weaver.conn.RecordSet"%>
<%@page import="org.apache.http.impl.client.HttpClientBuilder"%>
<%@page import="org.apache.http.entity.StringEntity"%>
<%@page import="weaver.general.WHashMap"%>
<%@page import="weaver.general.Util"%>
<%@page import="weaver.hrm.OnLineMonitor"%>
<%@page import="weaver.hrm.UserManager"%>
<%@page language="java" import="java.util.*" pageEncoding="UTF-8"%>
<%@page import="org.apache.http.client.methods.HttpPost"%>
<%@page import="org.apache.http.util.EntityUtils"%>
<%@page import="org.apache.http.client.methods.CloseableHttpResponse"%>
<%@page import="org.apache.http.impl.client.CloseableHttpClient"%>
<%@page import="org.apache.commons.lang3.StringUtils"%>
<%@page import="java.net.URLEncoder"%>
<%@page import="java.nio.charset.StandardCharsets"%>
<%@page import="java.security.MessageDigest"%>
<%@page import="com.alibaba.fastjson.JSON"%>
<%@page import="com.alibaba.fastjson.JSONObject"%>
<%@page import="weaver.hrm.User"%>
<%
	LogUtil log = LogUtil.log("yzy", "login");
	log.info("--------------yzy-----------------");
	String signature = request.getHeader("x-tif-signature");
	String timestamp = request.getHeader("x-tif-timestamp");
	String nonce = request.getHeader("x-tif-nonce");
	String uid = request.getHeader("x-tif-uid");
	String uinfo = request.getHeader("x-tif-uinfo");
	String ext = request.getHeader("x-tif-ext");
	String code1 = request.getHeader("code");
	String code = request.getParameter("code");
	String query = request.getQueryString();

	Enumeration paramNames = request.getParameterNames();

	String mobile = "";
	String userId = "";
	String name = "";
	String certificateNumber = "";
	
	//测试
	String corpid = "wld341060039"; //wld341060039
	String corpsecret = "LXrFJjCwTIJgfFWLf1q_0pRRKJOOjtCzmyrhRxUBoP8";
	String passId = "yzy_szsyth";
	String passToken = "wNDowmsLwQlWZys7JzGHgE07Fzm4IG6P";
	String agentid = "1003478";
	String scope = "snsapi_base";
	String state = "abc123";
	String baseUrl = "http://19.15.0.128:8080";
	
	//正式
	//String corpid = "wl2bee594e73"; 
	//String corpsecret = "33wHTtjCzj8ewiQB67iTkEjrzqYstDlwlN3aww56z1o";
	//String passId = "yzy_szsyth";
	//String passToken = "HJzQDGZEVNXNJdYfABqxJflcFbHC9XCa";
	//String agentid = "1003202";
	//String scope = "snsapi_base";
	//String state = "abc123";
	//String baseUrl = "http://10.223.188.13:8081";
	
	String access_token = "";
	String returnDataUser = "";
	String redirectUrl = "";

	// 验证通过后跳转模块地址
	String toPageUrl = request.getParameter("toPageUrl");
	String module = request.getParameter("module");
	String appid = request.getParameter("appid");
	String billid = request.getParameter("billid");

	// 如果没有code
	if (StringUtils.isBlank(code)) {
		log.info("--------------yzy---第一次--------------");
		log.info("--------------toPageUrl=" + toPageUrl);
		log.info("--------------module=" + module);
		log.info("--------------appid=" + appid);
		log.info("--------------billid=" + billid);
		redirectUrl = request.getRequestURL().toString();
		if (redirectUrl.indexOf("?") > 0) {
			redirectUrl = redirectUrl + "&toPageUrl=" + toPageUrl + "&module=" + module + "&appid=" + appid + "&billid=" + billid;
		} else {
			redirectUrl = redirectUrl + "?toPageUrl=" + toPageUrl + "&module=" + module + "&appid=" + appid + "&billid=" + billid;
		}
		redirectUrl = URLEncoder.encode(redirectUrl, StandardCharsets.UTF_8.toString());
		log.info("--------------yzy---第一次--------------redirectUrl=" + redirectUrl);
		String url = String.format("https://open.weixin.qq.com/connect/oauth2/authorize?appid=%s&redirect_uri=%s&response_type=code&scope=snsapi_base&agentid=%s&state=STATE#wechat_redirect",
				corpid, redirectUrl, agentid);
		response.sendRedirect(url);
	} else {
		log.info("--------------yzy---第二次--------------");
		log.info("--------------toPageUrl=" + toPageUrl);
		log.info("--------------module=" + module);
		log.info("--------------appid=" + appid);
		log.info("--------------billid=" + billid);
		//获取access_token 
		log.info("--------------yzy---获取token--------------");
		String accessTokenUrl = baseUrl+"/ebus/yzyapi/cgi-bin/gettoken?corpid=" + corpid + "&corpsecret=" + corpsecret;
		access_token = getAccessToken(accessTokenUrl, passId, passToken);
		log.info("--------------yzy---获取token结束--------------");
		if (access_token != null) {
			log.info("--------------yzy---获取人员--------------");
			String getUserUrl = baseUrl+"/ebus/yzyapi/cgi-bin/user/getuserinfo?access_token=" + access_token + "&code=" + code;
			returnDataUser = getUserDataByCode(getUserUrl, passId, passToken);
			log.info("--------------yzy---获取人员结束--------------");
			try {
				log.info("--------------yzy---人员校验登录开始--------------");
				JSONObject jsonObject = JSON.parseObject(returnDataUser);
				if (jsonObject.getInteger("errcode") == 0) {
					String outkey = jsonObject.getString("UserId");
					if (login(outkey, request, response)) {
						String toPage = "/spa/coms/static4mobile/index.html#/menu-preview?id=appDefaultPage&checkAccess=1";
						log.info("--------------yzy---人员校验登录结束--------------");
						if(toPageUrl !=null && StringUtils.isNotBlank(toPageUrl) && !StringUtils.equals("null", toPageUrl)) {
							log.info("--------------yzy---跳转toPageUrl");
							toPage = toPageUrl;
						}else if (StringUtils.equals("meeting", module) && StringUtils.isNotBlank(appid) && StringUtils.isNotBlank(billid)) {
							log.info("--------------yzy---跳转meeting");
							toPage = "/mobilemode/mobile/view.html?appid=" + appid + "#&page_288?billid=" + billid;
						}
						log.info("--------------yzy---跳转地址："+toPage);
						response.sendRedirect(toPage);
						log.info("--------------yzy---人员校验登录跳转--------------");
					} else {
						throw new Exception("登录校验出错：" + outkey);
					}
				}
			} catch (Exception e) {
				e.printStackTrace();
			}
		}
	}
%>
<%!/**
		 * 获取token
		 * @param url
		 * @param passId
		 * @param passToken
		 * @return
		 * @throws Exception
		 */
	public String getAccessToken(String url, String passId, String passToken) throws Exception {
		String result = request(url, passId, passToken);
		JSONObject jsonObject = JSON.parseObject(result);
		System.out.println(jsonObject);
		if (jsonObject.getInteger("errcode") == 0) {
			return jsonObject.getString("access_token");
		} else {
			return null;
		}
	}

	/**
	 * config 签名ticket获取
	 * @param accessToken
	 * @return
	 * @throws Exception
	 */
	public String getUserDataByCode(String url, String passId, String passToken) throws Exception {
		String result = request(url, passId, passToken);
		JSONObject jsonObject = JSON.parseObject(result);
		System.out.println(jsonObject);
		if (jsonObject.getInteger("errcode") == 0) {
			return jsonObject.toString();
		} else {
			throw new Exception("调用人员接口getuserinfo出错：" + jsonObject.toString());
		}
	}

	/**
	 * 请求网关的方式，主要是需要
	 * @param apiPath
	 * @param params
	 * @return
	 * @throws Exception
	 */
	public String request(String apiPath, String passId, String passToken) throws Exception {
		// 调用网关的签名
		long now = System.currentTimeMillis();
		String timestamp = Long.toString(now / 1000L);
		String nonce = Long.toHexString(now) + "-" + Long.toHexString((long) Math.floor(Math.random() * 0xFFFFFF));
		String signature = toSHA256(timestamp + passToken + nonce + timestamp);

		CloseableHttpClient client = HttpClientBuilder.create().build();
		HttpPost httpPost = new HttpPost(apiPath);
		httpPost.setHeader("x-tif-paasid", passId);
		httpPost.setHeader("x-tif-signature", signature);
		httpPost.setHeader("x-tif-timestamp", timestamp);
		httpPost.setHeader("x-tif-nonce", nonce);
		httpPost.setHeader("Content-Type", "application/json");
		httpPost.setHeader("Cache-Control", "no-cache");

		CloseableHttpResponse response = client.execute(httpPost);

		return EntityUtils.toString(response.getEntity());
	}

	public String toSHA256(String str) throws Exception {
		MessageDigest messageDigest;
		String encodeStr = "";
		messageDigest = MessageDigest.getInstance("SHA-256");
		messageDigest.update(str.getBytes(StandardCharsets.UTF_8));
		encodeStr = byte2Hex(messageDigest.digest());
		return encodeStr;
	}

	public String byte2Hex(byte[] bytes) {
		StringBuilder result = new StringBuilder();
		String temp;
		for (byte aByte : bytes) {
			temp = Integer.toHexString(aByte & 0xFF);
			if (temp.length() == 1) {
				result.append("0");
			}
			result.append(temp);
		}
		return result.toString();
	}

	public boolean login(String outkey, HttpServletRequest request, HttpServletResponse response) {
		if (!"".equals(outkey)) {
			RecordSet rs = new RecordSet();
			rs.execute("select id from cus_fielddata where field8='" + outkey + "' and SCOPE='HrmCustomFieldByInfoType' and SCOPEID='-1'");
			if (rs.next()) {
				int userid = 0;
				userid = rs.getInt("id");
				User user = new UserManager().getUserByUserIdAndLoginType(userid, "1");
				if (user != null && !"".equals(user.getUID()) && !"".equals(user.getLoginid())) {
					request.getSession(true).setMaxInactiveInterval(1728000);
					request.getSession().setAttribute("weaver_user@bean", user);

					request.getSession(true).setAttribute("moniter", new OnLineMonitor("" + user.getUID(), user.getLoginip()));
					Util.setCookie(response, "loginfileweaver", "/main.jsp", 1728000);
					Util.setCookie(response, "loginidweaver", "" + user.getUID(), 1728000);
					Util.setCookie(response, "languageidweaver", "7", 1728000);

					Map logmessages = (Map) request.getSession().getServletContext().getAttribute("logmessages");
					if (logmessages == null) {
						logmessages = new WHashMap();
						logmessages.put("" + user.getUID(), "");
						request.getSession().getServletContext().setAttribute("logmessages", logmessages);
					}
					//登录日志
					weaver.systeminfo.SysMaintenanceLog log1 = new weaver.systeminfo.SysMaintenanceLog();
					log1.resetParameter();
					log1.setRelatedId(userid);
					log1.setRelatedName(user.getLastname());
					log1.setOperateType("6");
					log1.setOperateDesc("");
					log1.setOperateItem("60");
					log1.setOperateUserid(userid);
					log1.setClientAddress(request.getRemoteAddr());
					try {
						log1.setSysLogInfo();
					} catch (Exception e) {
					}
					return true;
				} else {
					return false;
				}

			} else {
				return false;
			}
		} else {
			return false;
		}
	}%>
<html>
<head>
<title></title>
</head>
<body>
	<%
		while (paramNames.hasMoreElements()) {
			String paramName = (String) paramNames.nextElement();
			String[] paramValues = request.getParameterValues(paramName);
	%>
	<p>
		name=<%=paramName%></p>
	<p>
		value=<%=JSON.toJSONString(paramValues)%></p>
	<%
		}
	%>
	<p>
		value=<%=JSON.toJSONString(paramNames)%></p>
	<p>
		code=<%=code%></p>
	<p>
		returnDataUser=<%=returnDataUser%></p>
	<p>
		access_token=<%=access_token%></p>
	<p>
		timestamp=<%=timestamp%></p>
	<p>
		nonce=<%=nonce%></p>
	<p>
		uid=<%=uid%></p>
	<p>
		uinfo=<%=uinfo%></p>
	<p>
		ext=<%=ext%></p>
	<p>
		mobile=<%=mobile%></p>
	<p>
		name=<%=name%></p>
	<p>
		redirectUrl=<%=redirectUrl%></p>
</body>
</html>
