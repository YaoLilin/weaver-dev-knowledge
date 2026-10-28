<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.io.ByteArrayInputStream" %>
<%@ page import="java.io.DataInputStream" %>
<%@ page import="java.io.File" %>
<%@ page import="java.io.FileInputStream" %>
<%@ page import="java.io.InputStream" %>
<%@ page import="java.net.URL" %>
<%@ page import="java.net.URLDecoder" %>
<%@ page import="java.security.CodeSource" %>
<%@ page import="java.util.ArrayList" %>
<%@ page import="java.util.Collections" %>
<%@ page import="java.util.Comparator" %>
<%@ page import="java.util.Enumeration" %>
<%@ page import="java.util.LinkedHashMap" %>
<%@ page import="java.util.LinkedHashSet" %>
<%@ page import="java.util.List" %>
<%@ page import="java.util.Map" %>
<%@ page import="java.util.Set" %>
<%@ page import="java.util.jar.JarEntry" %>
<%@ page import="java.util.jar.JarFile" %>
<%--
    依赖缺失全量扫描页面（离线静态分析，不需要重启服务）。

    用途：不想重启服务 / 不想重载应用时，一次性找出「二次开发 jar 里引用了、但运行期
    classpath 上根本找不到」的类。做法是解析 class 文件的常量池，提取全部类型引用，
    再逐个做存在性检查——因此能发现那些「还没被执行到、所以还没报错」的隐患。

    与 RunArchivePushAction.jsp 的区别：
      · RunArchivePushAction.jsp 走的是「运行时行为」路线（加载类、创建对象、看是否抛错），
        只能暴露已经被走到的路径；
      · 本页走的是「静态引用」路线，穷举 jar 内所有 class 的全部外部类型引用，
        不需要类被加载、不需要重启，但会包含「引用到却永远走不到」的类（属于过度报告）。

    部署位置：ecology/jsp/secondDev/CheckMissingDeps.jsp
    访问方式：http://<ecology地址>/jsp/secondDev/CheckMissingDeps.jsp
              （不带参数 = 扫描【全部本项目 jar】，推荐；扫描对象见「一、扫描目标」）
              只扫某一个 jar：...?jar=weaver-seconddev-pde-archive-1.0.0.jar
    注意：本页面仅为临时诊断工具，排查完成后请从服务器删除。

    为什么要默认扫描「全部本项目 jar」：
      档案推送三个入口（ArchivePushAction 自动推送 / ArchiveAction#push 单条推送 /
      ArchiveAction#pushHistory 历史批量推送）最终都汇聚到同一个 ArchivePushServiceImpl，
      而其中的业务实现分散在三个 jar：
        · weaver-seconddev-YulinPolice-dev-*.jar  —— 元数据、打包、推送编排、表单 PDF 生成器
        · weaver-seconddev-pde-archive-*.jar     —— 表单文档获取、文档转换（永中 DCS）、表单 PDF 调用
        · seconddev-common-lib-yll.jar           —— common 模块产物（WorkflowFormPdfCreator 等）
      只扫入口类所在的那一个 jar，会漏掉另一个 jar 引用的依赖（例如
      cn.hutool.core.io.FileUtil、cn.hutool.core.thread.NamedThreadFactory，
      它们只出现在 pde-archive 侧）。

    为什么必须带上 seconddev- 前缀（2026-09-21 实测教训）：
      common 模块的 jar 名是 seconddev-common-lib-yll.jar，不以 weaver- 开头。真实 ecology 的
      610 个 jar 里，com.customization.yll.common.workflow.WorkflowFormPdfCreator 只存在于此；
      在补上该前缀之前，它引用的 com.itextpdf.text.* 从未出现在检测结果里，
      直到线上以 NoClassDefFoundError: com/itextpdf/text/DocumentException 炸出来才暴露。
      判定「某类是否被扫到」用：for j in <ecology>/WEB-INF/lib/*.jar; do
      unzip -l "$j" | grep -q "<类路径>" && echo "$j"; done

    为什么还要单独判断 classbean（2026-09-21 补充）：
      ecology/classbean/ 是 E9 下发「平台补丁类 + 二开类」的目录，里面放的是
      **散装 .class 文件**（本机 35508 个），**不是 jar**。因此「某个被引用的类到底存不存在」
      不能只看 WEB-INF/lib —— 它可能整个平台层都由 classbean 提供。
      本页对每一个「webapp 加载器加载失败」的引用，会再做两级复核：
        (a) 换类加载器再试（线程上下文 / 系统加载器，外加「平台参照类」的定义加载器）；
        (b) 在 <ecology>/classbean/ 下按「包名 → 目录」**逐文件**找 .class（不扫 jar！）。
      命中 (a) 或 (b) 的都不再计入「缺失」，而是单列一节说明，并标明是在哪命中的。

      实测（本机 610 个 jar）：weaver.conn.RecordSet 在**任何 jar 里都没有**，只存在于
      classbean，而它从未被报缺失 —— 说明 webapp 加载器本来就看得见 classbean。
      因此「文件在 classbean 里、却没有任何加载器能加载」这种情况一旦出现，就不是常规缺失，
      而是**加载器隔离**导致的真隐患，页面会单独高亮，不要照常规补 jar。

    定位扫描目标的坑（最容易误报「扫描目标不存在」）：
      Resin 的 DynamicClassLoader 会把 CodeSource 指向 jar **内部**的那个 class 文件，
      位置字符串是 /xxx/WEB-INF/lib/a.jar/com/x/Y.class（或 a.jar!/com/x/Y.class），
      它不是合法的文件路径。必须先截断到 .jar 为止；截断后若仍不存在，
      再按 jar 文件名去 WEB-INF/lib 候选目录里找。本页三条路线都试，并在「一、扫描目标」
      里把原始 URL、截断结果、候选目录逐个列出来，便于排查。
--%>

<%!
    /** 入口类：用它定位「要扫描哪个 jar」——所在 jar 即扫描目标 */
    private static final String ENTRY_CLASS = "com.customization.secdev.archive.action.ArchivePushAction";

    /** 单个 jar 允许扫描的最大 class 数，防止误扫到 classbean.jar 这类超大平台 jar 导致页面超时 */
    private static final int MAX_CLASSES_PER_ARCHIVE = 5000;

    /** 这些前缀的类由 JDK/Bootstrap 提供，一定存在，跳过检查以节省时间 */
    private static final String[] JDK_PREFIXES = { "java.", "jdk.", "sun.", "com.sun." };

    /** classbean 目录名：挂在 webapp 根下（<ecology>/classbean），里面是散装 .class 而非 jar。 */
    private static final String CLASSBEAN_DIR_NAME = "classbean";

    /**
     * 平台参照类。
     *
     * <p>这些类在本机 **只存在于 classbean**、任何 jar 里都没有，E9 靠它们干活。
     * 用「能加载它们的那个加载器」去补齐候选加载器，可以避免因为 JSP 自身的加载器
     * 视野偏窄而把「其实能加载」的类误报成缺失。</p>
     */
    private static final String[] PLATFORM_PROBE_CLASSES = {
            "weaver.conn.RecordSet",                      // 数据库访问
            "weaver.general.Util",                        // 平台工具类
            "weaver.soa.workflow.request.RequestInfo" };  // 流程请求对象

    /**
     * 本项目二次开发 jar 的文件名前缀。
     *
     * <p>默认扫描「全部本项目 jar」而不仅是入口类所在的那一个：档案推送的三个业务
     * （表单文档获取、文档转换、流程表单页面 PDF）都实现在
     * {@code weaver-seconddev-pde-archive-*.jar} 里，只扫入口 jar 会漏掉它们引用的依赖。</p>
     *
     * <p><b>{@code seconddev-} 前缀必须保留</b>：common 模块的产物叫
     * {@code seconddev-common-lib-yll.jar}，文件名不以 {@code weaver-} 开头。
     * 实测（2026-09-21，真实 ecology 的 610 个 jar）：
     * {@code com.customization.yll.common.workflow.WorkflowFormPdfCreator} 只存在于这个 jar，
     * 它引用的 {@code com.itextpdf.text.*} 曾因缺少本前缀而<b>整条漏报</b>，
     * 线上最终以 {@code NoClassDefFoundError: com/itextpdf/text/DocumentException} 炸出来。</p>
     */
    private static final String[] PROJECT_JAR_PREFIXES = {
            "weaver-seconddev-", "seconddev-", "pdes-eep-", "pde-file-" };

    /**
     * 关键业务链路类。
     *
     * <p>页面上会给每个缺失类标注「是否被这些类引用」——被引用即说明该缺失项
     * 落在归档推送的业务链路上，优先级高；没被引用则大概率是走不到的死代码。</p>
     */
    private static final String[] KEY_BIZ_CLASSES = {
            "com.customization.yll.wuling.archive.file.WorkflowFileManager",        // 表单文档获取
            "com.customization.yll.wuling.archive.file.ArchiveFileConvertor",       // 文档转换分发
            "com.customization.yll.wuling.archive.file.YozoDcsConvertManager",      // 永中 DCS 转换
            "com.customization.yll.wuling.archive.file.FileConvertor",              // 转换接口
            "com.customization.yll.common.workflow.WorkflowFormPdfCreator",         // 流程表单页面 PDF
            "com.customization.yll.wuling.archive.file.FileSignatureHandler",       // 契约锁签名
            "com.customization.yll.wuling.archive.file.QysSignatureDocDownloadManger",
            "com.customization.yll.wuling.archive.data.ArchiveDataManager",         // 归档数据读取
            "com.customization.yll.common.util.DocUtil",                            // 文档工具
            "com.customization.secdev.archive.manager.ArchiveMetadataManager",      // 元数据
            "com.customization.secdev.archive.manager.ArchiveMetadataXmlManager",   // meta.xml
            "com.customization.secdev.archive.manager.ArchivePackageManager",       // 打包装配
            "com.customization.secdev.archive.manager.ArchivePackageUploadManager", // 上传
            "com.customization.secdev.archive.manager.ArchiveTokenManager",         // 令牌
            "com.customization.secdev.archive.manager.ArchivePushResultRecordManager", // 结果记录
            "com.customization.secdev.archive.service.impl.ArchivePushServiceImpl", // 推送编排（三入口汇聚点）
            // 入口①：流程归档后自动推送
            "com.customization.secdev.archive.action.ArchivePushAction",
            // 入口②③：单条推送 / 历史批量推送
            "com.engine.interfaces.secdev.archive.web.ArchiveAction",
            // 批量推送专有：线程池（INSTANCE 初始化即 new NamedThreadFactory）
            "com.engine.interfaces.yll2.wuling.archive.service.ArchivePushTheadPoolService",
            "com.engine.interfaces.yll2.wuling.archive.service.AbstractHistoryArchivePushTask",
            "com.customization.secdev.archive.service.impl.ArchiveHistoryPushServiceImpl",
            "com.customization.secdev.archive.service.impl.ArchiveHistoryWorkflowServiceExtendImpl",
            "com.customization.secdev.archive.service.CurrentArchiveHistoryPushTask" };

    /** 关键业务类的简名映射（用于页面快速比对）。 */
    private static Map<String, String> keyBizShort() {
        Map<String, String> map = new LinkedHashMap<String, String>();
        for (int i = 0; i < KEY_BIZ_CLASSES.length; i++) {
            String cls = KEY_BIZ_CLASSES[i];
            map.put(cls, cls.substring(cls.lastIndexOf('.') + 1));
        }
        return map;
    }

    /**
     * 读取流的全部字节。
     *
     * @param in 输入流，方法内部负责关闭
     * @return 字节数组
     * @throws java.io.IOException 读取失败
     */
    private static byte[] readAllBytes(InputStream in) throws java.io.IOException {
        try {
            java.io.ByteArrayOutputStream buffer = new java.io.ByteArrayOutputStream(4096);
            byte[] chunk = new byte[4096];
            int len;
            while ((len = in.read(chunk)) > 0) {
                buffer.write(chunk, 0, len);
            }
            return buffer.toByteArray();
        } finally {
            try {
                in.close();
            } catch (Throwable ignored) {
            }
        }
    }

    /** 判断某个类名是否属于「一定存在」的 JDK 类，是则跳过存在性检查。 */
    private static boolean isJdkClass(String className) {
        for (int i = 0; i < JDK_PREFIXES.length; i++) {
            if (className.startsWith(JDK_PREFIXES[i])) {
                return true;
            }
        }
        return false;
    }

    /**
     * 判断一个内部形式的类型名（a/b/C）是否像合法的类名。
     * 用于过滤掉「描述符正则从普通字符串里误提取出来的」噪声。
     *
     * @param internalName 内部形式类型名（不含 L 和 ;）
     * @return 像类名返回 true
     */
    private static boolean looksLikeClassName(String internalName) {
        if (internalName == null || internalName.length() == 0) {
            return false;
        }
        // 必须带包分隔符，借此过滤掉 "Label;" 这类字符串常量误报
        if (internalName.indexOf('/') < 0) {
            return false;
        }
        for (int i = 0; i < internalName.length(); i++) {
            char c = internalName.charAt(i);
            boolean ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
                    || c == '_' || c == '$' || c == '/';
            if (!ok) {
                return false;
            }
        }
        // 包名的每一段都不能以数字开头
        String[] parts = internalName.split("/");
        for (int i = 0; i < parts.length; i++) {
            char first = parts[i].charAt(0);
            if (parts[i].length() == 0 || (first >= '0' && first <= '9')) {
                return false;
            }
        }
        return true;
    }

    /**
     * 把常量池 CONSTANT_Class 项里的名字规范成类名（点号形式）。
     * 该名字可能是普通内部形式（a/b/C），也可能是数组描述符（[La/b/C; 或 [[I）。
     *
     * @param raw 常量池里的原始名字
     * @return 类名（点号形式）；不是类类型（如基本类型数组）时返回 null
     */
    private static String normalizeClassRef(String raw) {
        if (raw == null || raw.length() == 0) {
            return null;
        }
        int i = 0;
        while (i < raw.length() && raw.charAt(i) == '[') {
            i++;
        }
        if (i >= raw.length()) {
            return null;
        }
        if (i > 0) {
            // 数组：只有引用类型数组才有对应类，如 [La/b/C; → a.b.C
            if (raw.charAt(i) == 'L' && raw.endsWith(";")) {
                String inner = raw.substring(i + 1, raw.length() - 1);
                return looksLikeClassName(inner) ? inner.replace('/', '.') : null;
            }
            return null;
        }
        return looksLikeClassName(raw) ? raw.replace('/', '.') : null;
    }

    /**
     * 从「描述符 / 泛型签名」字符串里提取 Lxxx; 形式的类型引用。
     *
     * <p>为什么要做这一步：方法签名、字段类型、泛型签名里的类型未必会生成
     * CONSTANT_Class 项（只有真正被字节码使用的类型才会），但它们在反射调用时同样需要被加载。</p>
     *
     * @param text 待扫描的常量池字符串
     * @param out  收集结果的集合
     */
    private static void extractDescriptorTypes(String text, Set<String> out) {
        if (text == null) {
            return;
        }
        int i = 0;
        int n = text.length();
        while (i < n) {
            if (text.charAt(i) != 'L') {
                i++;
                continue;
            }
            int end = text.indexOf(';', i);
            if (end < 0) {
                break;
            }
            String inner = text.substring(i + 1, end);
            if (looksLikeClassName(inner)) {
                out.add(inner.replace('/', '.'));
            }
            i = end + 1;
        }
    }

    /**
     * 解析一个 class 文件的常量池，收集它引用的所有类型名（点号形式）。
     *
     * <p>只解析到常量池结束，后面的字段/方法/属性表不需要 —— 所有类型引用都在常量池里。
     * 注意 CONSTANT_Long(5) 与 CONSTANT_Double(6) 会占据两个常量池槽位，
     * 解析时必须额外跳过一次，否则后续项全部错位。</p>
     *
     * @param data class 文件字节
     * @return 引用的类型名集合，解析失败返回空集合
     */
    private static Set<String> classRefsOf(byte[] data) {
        Set<String> refs = new LinkedHashSet<String>();
        if (data == null || data.length < 10) {
            return refs;
        }
        try {
            DataInputStream in = new DataInputStream(new ByteArrayInputStream(data));
            if (in.readInt() != 0xCAFEBABE) {
                return refs;
            }
            in.readUnsignedShort(); // minor_version
            in.readUnsignedShort(); // major_version
            int cpCount = in.readUnsignedShort();

            String[] utf8 = new String[cpCount];
            int[] classToNameIndex = new int[cpCount];
            List<Integer> classEntries = new ArrayList<Integer>();

            for (int i = 1; i < cpCount; i++) {
                int tag = in.readUnsignedByte();
                switch (tag) {
                    case 1: { // CONSTANT_Utf8
                        int len = in.readUnsignedShort();
                        byte[] buf = new byte[len];
                        in.readFully(buf);
                        utf8[i] = new String(buf, "UTF-8");
                        break;
                    }
                    case 7: { // CONSTANT_Class
                        classToNameIndex[i] = in.readUnsignedShort();
                        classEntries.add(Integer.valueOf(i));
                        break;
                    }
                    case 3: // Integer
                    case 4: // Float
                        in.skipBytes(4);
                        break;
                    case 5: // Long（占两槽）
                    case 6: // Double（占两槽）
                        in.skipBytes(8);
                        i++;
                        break;
                    case 8:  // String
                    case 16: // MethodType
                    case 19: // Module
                    case 20: // Package
                        in.skipBytes(2);
                        break;
                    case 9:  // Fieldref
                    case 10: // Methodref
                    case 11: // InterfaceMethodref
                    case 12: // NameAndType
                    case 17: // Dynamic
                    case 18: // InvokeDynamic
                        in.skipBytes(4);
                        break;
                    case 15: // MethodHandle
                        in.skipBytes(3);
                        break;
                    default:
                        // 出现未知 tag，说明解析会错位，放弃该 class
                        return refs;
                }
            }

            // (1) CONSTANT_Class 项：JVM 真正会解析的类引用
            for (int k = 0; k < classEntries.size(); k++) {
                int idx = classEntries.get(k).intValue();
                int nameIdx = classToNameIndex[idx];
                String normalized = (nameIdx > 0 && nameIdx < cpCount) ? normalizeClassRef(utf8[nameIdx]) : null;
                if (normalized != null) {
                    refs.add(normalized);
                }
            }
            // (2) 所有 UTF8 字符串里形如描述符的类型（方法签名 / 泛型签名等）
            for (int i = 1; i < cpCount; i++) {
                if (utf8[i] != null) {
                    extractDescriptorTypes(utf8[i], refs);
                }
            }
        } catch (Throwable t) {
            // 解析异常一律忽略该 class（不影响整体扫描）
        }
        return refs;
    }

    // ===== 定位「入口类所在 jar / 目录」 =====
    //
    // 这里不能直接拿 CodeSource.getLocation().getPath() 当文件路径用：Resin 的
    // DynamicClassLoader 会把 CodeSource 指到「jar 内部的那个 class 文件」上，拼出来的
    // 字符串形如：
    //     /weaver/Resin/file/weaver/ecology/WEB-INF/lib/xxx.jar/com/a/B.class
    // 或者带 jar URL 分隔符：
    //     file:/weaver/.../xxx.jar!/com/a/B.class
    // 直接 new File(...) 当然「不存在」。因此必须先把路径截断到 .jar 为止，
    // 并且再准备一条「按文件名去 WEB-INF/lib 里找」的兜底路线。

    /**
     * URL 文本 → 本地文件系统路径。
     *
     * @param urlText URL 的字符串形式（可能是 file: / jar:file: 形式）
     * @return 本地路径；非本地协议（http 等）返回 null
     */
    private static String urlToFilePath(String urlText) {
        if (urlText == null) {
            return null;
        }
        String s = urlText.trim();
        if (s.startsWith("jar:")) {
            s = s.substring(4);
        }
        if (s.startsWith("file:")) {
            s = s.substring(5);
            if (s.startsWith("//")) {
                // file://host/path 或 file:///path
                s = s.substring(2);
                int slash = s.indexOf('/');
                s = (slash >= 0) ? s.substring(slash) : ("/" + s);
            }
        } else if (s.indexOf("://") >= 0) {
            return null;
        }
        try {
            // 先把 '+' 保护起来，否则 URLDecoder 会把它当空格
            s = URLDecoder.decode(s.replace("+", "%2B"), "UTF-8");
        } catch (Throwable ignored) {
        }
        return s;
    }

    /**
     * 把「指向 jar 内某个 class 的路径」截断成 jar / 目录本身的路径。
     *
     * @param path 已经过 urlToFilePath 处理的路径
     * @return 归档路径；无法判断返回 null
     */
    private static String truncateToArchive(String path) {
        if (path == null || path.length() == 0) {
            return null;
        }
        // (1) 标准 jar URL：xxx.jar!/com/a/B.class
        int bang = path.indexOf("!/");
        if (bang > 0) {
            return path.substring(0, bang);
        }
        // (2) Resin 风格：xxx.jar/com/a/B.class —— 靠「.jar 后紧跟分隔符」定位
        String lower = path.toLowerCase();
        int from = 0;
        while (from < lower.length()) {
            int hit = lower.indexOf(".jar/", from);
            int hitAlt = lower.indexOf(".jar\\", from);
            if (hit < 0) {
                hit = hitAlt;
            } else if (hitAlt >= 0 && hitAlt < hit) {
                hit = hitAlt;
            }
            if (hit < 0) {
                break;
            }
            // 注意：不能要求 .jar 前是斜杠 —— 那里正是文件名本身（如 xxx-1.0.0.jar）
            if (hit > 0) {
                return path.substring(0, hit + 4);
            }
            from = hit + 1;
        }
        // (3) 本身就是一个 jar 文件
        if (lower.endsWith(".jar")) {
            return path;
        }
        // (4) 目录：去掉结尾的分隔符
        while (path.length() > 1 && (path.endsWith("/") || path.endsWith("\\"))) {
            path = path.substring(0, path.length() - 1);
        }
        return path;
    }

    /**
     * 当位置指向的是「目录下的某个 .class 文件」时，反推出 classpath 根目录。
     *
     * @param classFilePath .class 文件的本地路径
     * @param className     class 的全限定名
     * @return classpath 根目录；无法反推返回 null
     */
    private static String dirOfClassFile(String classFilePath, String className) {
        if (classFilePath == null || className == null) {
            return null;
        }
        String pkgPath = className.replace('.', '/') + ".class";
        if (!classFilePath.endsWith(pkgPath)) {
            return null;
        }
        String root = classFilePath.substring(0, classFilePath.length() - pkgPath.length());
        while (root.length() > 1 && (root.endsWith("/") || root.endsWith("\\"))) {
            root = root.substring(0, root.length() - 1);
        }
        return (root.length() == 0) ? null : root;
    }

    /**
     * 把一个「类位置 URL」换算成归档路径（jar 文件或 classpath 目录）。
     *
     * @param urlText   类位置的 URL 文本
     * @param className class 的全限定名
     * @return 归档路径；无法换算返回 null
     */
    private static String archivePathFromUrl(String urlText, String className) {
        String path = urlToFilePath(urlText);
        if (path == null) {
            return null;
        }
        // 必须先截断到 .jar：jar URL（xxx.jar!/com/a/B.class）也以 .class 结尾，
        // 若先按「目录形式的 .class」处理，会把 jar 路径错误地退成 "xxx.jar!"。
        String archive = truncateToArchive(path);
        if (archive != null && archive.toLowerCase().endsWith(".class")) {
            // 目录形式：退到 classpath 根（如 WEB-INF/classes）
            return dirOfClassFile(archive, className);
        }
        return archive;
    }

    /**
     * 汇总一个类的所有已知位置 URL，兼顾下列几种来源：
     * CodeSource、Class#getResource、ClassLoader#getResources（可枚举出同名类的多份副本）。
     *
     * @param clazz  目标类
     * @param loader 用来枚举资源的类加载器
     * @return URL 文本列表（已去重，按可信度排序）
     */
    private static List<String> locationUrlsOfClass(Class<?> clazz, ClassLoader loader) {
        List<String> urls = new ArrayList<String>();
        try {
            CodeSource codeSource = clazz.getProtectionDomain().getCodeSource();
            if (codeSource != null && codeSource.getLocation() != null) {
                urls.add(codeSource.getLocation().toString());
            }
        } catch (Throwable ignored) {
        }
        String resource = clazz.getName().replace('.', '/') + ".class";
        try {
            URL url = clazz.getResource("/" + resource);
            if (url != null && !urls.contains(url.toString())) {
                urls.add(url.toString());
            }
        } catch (Throwable ignored) {
        }
        try {
            Enumeration<URL> found = loader.getResources(resource);
            while (found != null && found.hasMoreElements()) {
                String text = String.valueOf(found.nextElement());
                if (!urls.contains(text)) {
                    urls.add(text);
                }
            }
        } catch (Throwable ignored) {
        }
        return urls;
    }

    /** 列出 lib 候选目录：入口 jar 所在目录 + webapp 的 WEB-INF/lib（去重）。 */
    private static List<File> libDirCandidates(File archive, String webLibRealPath) {
        List<File> dirs = new ArrayList<File>();
        if (archive != null) {
            File dir = archive.isDirectory() ? archive : archive.getParentFile();
            if (dir != null) {
                dirs.add(dir);
            }
        }
        if (webLibRealPath != null && webLibRealPath.length() > 0) {
            File dir = new File(webLibRealPath);
            if (!dirs.contains(dir)) {
                dirs.add(dir);
            }
        }
        return dirs;
    }

    /** 在候选目录里按文件名找 jar，找到返回该文件，否则返回 null。 */
    private static File findJarInLibDirs(String jarName, List<File> dirs) {
        for (int i = 0; i < dirs.size(); i++) {
            File candidate = new File(dirs.get(i), jarName);
            if (candidate.isFile()) {
                return candidate;
            }
        }
        return null;
    }

    /**
     * 收集候选目录下「本项目」的全部 jar。
     *
     * <p>判定依据是文件名前缀（{@link #PROJECT_JAR_PREFIXES}）。找不到任何匹配时，
     * 回退为入口类所在的那一个归档文件，保证页面至少还能扫到入口 jar。</p>
     *
     * @param dirs         候选 lib 目录
     * @param entryArchive 入口类所在归档，作为兜底
     * @return 待扫描的 jar 列表（可能为空）
     */
    private static List<File> projectJarsOf(List<File> dirs, File entryArchive) {
        List<File> result = new ArrayList<File>();
        for (int i = 0; i < dirs.size(); i++) {
            File[] files = dirs.get(i).listFiles();
            if (files == null) {
                continue;
            }
            for (int j = 0; j < files.length; j++) {
                File file = files[j];
                if (!file.isFile() || !file.getName().endsWith(".jar")) {
                    continue;
                }
                if (isProjectJar(file.getName()) && !result.contains(file)) {
                    result.add(file);
                }
            }
        }
        if (result.isEmpty() && entryArchive != null && entryArchive.isFile()) {
            result.add(entryArchive);
            return result;
        }
        if (entryArchive != null && entryArchive.isFile() && !result.contains(entryArchive)) {
            // 入口 jar 的文件名可能被改过，补进来，避免漏扫
            result.add(entryArchive);
        }
        Collections.sort(result, new Comparator<File>() {
            @Override
            public int compare(File left, File right) {
                return left.getName().compareTo(right.getName());
            }
        });
        return result;
    }

    /** 文件名是否匹配本项目 jar 前缀。 */
    private static boolean isProjectJar(String fileName) {
        for (int i = 0; i < PROJECT_JAR_PREFIXES.length; i++) {
            if (fileName.startsWith(PROJECT_JAR_PREFIXES[i])) {
                return true;
            }
        }
        return false;
    }

    /** 用容器 API 列出 /WEB-INF/lib 下的 jar 名（不依赖文件系统可见性）。 */
    private static Set<String> jarNamesFromContext(javax.servlet.ServletContext context, String webLibPath) {
        Set<String> names = new LinkedHashSet<String>();
        try {
            Set<String> paths = context.getResourcePaths("/WEB-INF/lib");
            if (paths != null) {
                for (String path : paths) {
                    if (path != null && path.toLowerCase().endsWith(".jar")) {
                        names.add(path.substring(path.lastIndexOf('/') + 1));
                    }
                }
            }
        } catch (Throwable ignored) {
        }
        if (names.isEmpty() && webLibPath != null && webLibPath.length() > 0) {
            File[] files = new File(webLibPath).listFiles();
            if (files != null) {
                for (int i = 0; i < files.length; i++) {
                    if (files[i].isFile() && files[i].getName().toLowerCase().endsWith(".jar")) {
                        names.add(files[i].getName());
                    }
                }
            }
        }
        return names;
    }

    /** 收集 jar 内全部 class 的「类名 → class 字节」。 */
    private static Map<String, byte[]> classesOfJar(File jarFile) throws Exception {
        Map<String, byte[]> result = new LinkedHashMap<String, byte[]>();
        JarFile jar = new JarFile(jarFile);
        try {
            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                String name = entry.getName();
                if (!name.endsWith(".class") || name.startsWith("META-INF/")) {
                    continue;
                }
                String className = name.substring(0, name.length() - 6).replace('/', '.');
                result.put(className, readAllBytes(jar.getInputStream(entry)));
            }
        } finally {
            try {
                jar.close();
            } catch (Throwable ignored) {
            }
        }
        return result;
    }

    /** 把 source 里的 class 并入 target，并记录每个类来自哪个 jar（先到先得）。 */
    private static void mergeClasses(Map<String, byte[]> target, Map<String, byte[]> source,
                                     String jarName, Map<String, String> homeJar) {
        for (Map.Entry<String, byte[]> entry : source.entrySet()) {
            if (!target.containsKey(entry.getKey())) {
                target.put(entry.getKey(), entry.getValue());
                homeJar.put(entry.getKey(), jarName);
            }
        }
    }

    /** 递归收集目录下全部 class 的「类名 → class 字节」。 */
    private static Map<String, byte[]> classesOfDir(File dir, File root) throws Exception {
        Map<String, byte[]> result = new LinkedHashMap<String, byte[]>();
        File[] children = dir.listFiles();
        if (children == null) {
            return result;
        }
        for (int i = 0; i < children.length; i++) {
            File child = children[i];
            if (child.isDirectory()) {
                result.putAll(classesOfDir(child, root));
            } else if (child.getName().endsWith(".class")) {
                String relative = child.getAbsolutePath().substring(root.getAbsolutePath().length() + 1);
                String className = relative.substring(0, relative.length() - 6)
                        .replace(File.separatorChar, '.');
                result.put(className, readAllBytes(new FileInputStream(child)));
            }
        }
        return result;
    }

    /** HTML 转义。 */
    private static String escapeHtml(String text) {
        if (text == null) {
            return "";
        }
        return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
    }

    /**
     * 把存在性检查抛出的异常归成一句人话 —— 用来区分两种完全不同的「缺失」。
     *
     * <p>为什么必须区分（已实测验证）：
     * <ul>
     *   <li>类文件真的不存在 → {@link ClassNotFoundException}；</li>
     *   <li>类文件存在、但它 extends/implements 的类型缺失 → {@link NoClassDefFoundError}，
     *       而且 <b>即使 initialize=false 也会抛</b>。此时报出的名字是「被检查的类」，
     *       真正要补的却是消息里那个父类/接口。若不看原因，会把「平台类存在」误判成「平台类缺失」。</li>
     * </ul>
     * 另外，方法体里的引用是惰性的：类能加载、对象能创建，只有执行到那一句才会抛 ——
     * 这正是「能 new 出 Action，一推送就报错」的原因。</p>
     *
     * @param t 检查时抛出的异常
     * @return 便于判读的原因文本
     */
    private static String describeFailure(Throwable t) {
        if (t == null) {
            return "(未知原因)";
        }
        String message = (t.getMessage() == null) ? "" : t.getMessage();
        if (t instanceof ClassNotFoundException) {
            return "ClassNotFoundException —— classpath 上确实没有这个类";
        }
        if (t instanceof NoClassDefFoundError) {
            String culprit = message;
            int slash = culprit.lastIndexOf('/');
            if (slash >= 0) {
                culprit = culprit.substring(slash + 1);
            }
            if (culprit.length() == 0) {
                culprit = "(消息为空)";
            }
            return "NoClassDefFoundError: " + message
                    + " —— 它的父类/接口或初始化依赖「" + culprit + "」缺失，真正要补的是后者";
        }
        return t.getClass().getName() + (message.length() == 0 ? "" : ": " + message);
    }

    /** 输出普通文本，带颜色 class。 */
    private static String span(String cssClass, String text) {
        return "<span class=\"" + cssClass + "\">" + escapeHtml(text) + "</span>";
    }

    // ===== classbean / 多类加载器 复核（2026-09-21 新增） =====
    //
    // 背景：某个类「webapp 加载器加载不到」并不等于「不存在」。两个很常见的例外：
    //   1) 它由另一个类加载器提供（E9 的平台补丁类就是通过 classbean 下发的）；
    //   2) 它确实在 ecology/classbean 目录里，只是当前加载器看不见。
    // 把这两种情况混进「缺失清单」，会让人去补一个根本不需要补的 jar。
    // 所以这里补两级复核，并把结果单列，不污染「真缺失」列表。

    /**
     * 收集除 webapp 加载器之外的候选类加载器（去重）。
     *
     * <p>候选来源：线程上下文加载器、系统加载器，以及<b>平台参照类</b>的定义加载器。
     * 每个加载器都连它的父链一起加入 —— 双亲委派意味着父加载器能加载的，
     * 子加载器同样能加载。</p>
     *
     * @param primary webapp 类加载器（已在第一轮试过，这里只登记不返回）
     * @return 候选加载器（webapp 加载器链条已排除）
     */
    private static List<ClassLoader> extraLoaders(ClassLoader primary) {
        Set<ClassLoader> seen = new LinkedHashSet<ClassLoader>();
        List<ClassLoader> primaryChain = new ArrayList<ClassLoader>();
        addLoaderChain(primaryChain, seen, primary);

        List<ClassLoader> result = new ArrayList<ClassLoader>();
        addLoaderChain(result, seen, Thread.currentThread().getContextClassLoader());
        addLoaderChain(result, seen, ClassLoader.getSystemClassLoader());

        // 平台参照类能由谁加载，那个加载器就一定看得见 classbean，把它一并作为候选。
        List<ClassLoader> probes = new ArrayList<ClassLoader>(primaryChain);
        probes.addAll(result);
        for (int i = 0; i < PLATFORM_PROBE_CLASSES.length; i++) {
            for (int k = 0; k < probes.size(); k++) {
                try {
                    Class<?> hit = Class.forName(PLATFORM_PROBE_CLASSES[i], false, probes.get(k));
                    addLoaderChain(result, seen, hit.getClassLoader());
                    break;
                } catch (Throwable ignored) {
                }
            }
        }
        return result;
    }

    /**
     * 把一个加载器连同它的父链加入列表（去重）。父链取值一律兜底 ——
     * 线程上下文加载器可能被业务代码换成任何实现，取 parent 也可能抛。
     */
    private static void addLoaderChain(List<ClassLoader> list, Set<ClassLoader> seen, ClassLoader start) {
        ClassLoader walk = start;
        int guard = 0;
        while (walk != null && guard++ < 12) {
            if (seen.add(walk)) {
                list.add(walk);
            }
            try {
                walk = walk.getParent();
            } catch (Throwable t) {
                walk = null;
            }
        }
    }

    /**
     * 用一组候选加载器逐个尝试解析类。
     *
     * @param className 全限定类名（点号）
     * @param loaders   候选加载器
     * @return 第一个解析成功的加载器；全部失败返回 null
     */
    private static ClassLoader resolveWith(String className, List<ClassLoader> loaders) {
        for (int i = 0; i < loaders.size(); i++) {
            try {
                Class.forName(className, false, loaders.get(i));
                return loaders.get(i);
            } catch (Throwable ignored) {
            }
        }
        return null;
    }

    /**
     * 定位 classbean 目录（{@code <ecology>/classbean}）。
     *
     * <p>里面是<b>散装 .class 文件</b>而不是 jar，所以只能按「包名 → 目录」逐文件判断，
     * 不能套用 jar 扫描那一套。三条路线都试，取到的目录可能不止一个。</p>
     *
     * @param context    当前 webapp 的 ServletContext
     * @param webLibPath {@code application.getRealPath("/WEB-INF/lib")} 的结果，可为 null
     * @return 候选根目录（可能不存在）
     */
    private static List<File> locateClassbeanRoots(javax.servlet.ServletContext context, String webLibPath) {
        List<File> roots = new ArrayList<File>();
        try {
            String real = context.getRealPath("/classbean");
            if (real != null && real.length() > 0) {
                addDirUniquely(roots, new File(real));
            }
        } catch (Throwable ignored) {
        }
        try {
            String webRoot = context.getRealPath("/");
            if (webRoot != null && webRoot.length() > 0) {
                addDirUniquely(roots, new File(webRoot, CLASSBEAN_DIR_NAME));
            }
        } catch (Throwable ignored) {
        }
        if (webLibPath != null && webLibPath.length() > 0) {
            // <ecology>/WEB-INF/lib → 上两级即 <ecology>
            File webInf = new File(webLibPath).getParentFile();
            File ecology = (webInf == null) ? null : webInf.getParentFile();
            if (ecology != null) {
                addDirUniquely(roots, new File(ecology, CLASSBEAN_DIR_NAME));
            }
        }
        return roots;
    }

    /** 去重加入一个目录候选（只按路径去重，不要求已存在）。 */
    private static void addDirUniquely(List<File> list, File dir) {
        if (dir != null && !list.contains(dir)) {
            list.add(dir);
        }
    }

    /**
     * 在 classbean 目录下按包名逐文件找 .class。
     *
     * @param className 全限定类名（点号）
     * @param roots     classbean 根目录候选（应已过滤为真实存在的目录）
     * @return 命中的文件；都没有返回 null
     */
    private static File findClassbeanFile(String className, List<File> roots) {
        String relative = className.replace('.', File.separatorChar) + ".class";
        for (int i = 0; i < roots.size(); i++) {
            File candidate = new File(roots.get(i), relative);
            if (candidate.isFile()) {
                return candidate;
            }
        }
        return null;
    }
%>

<%
    // ===== 一、定位扫描目标 =====
    ClassLoader webLoader = this.getClass().getClassLoader();

    Class<?> entryClass = null;
    Throwable entryError = null;
    try {
        entryClass = Class.forName(ENTRY_CLASS, false, webLoader);
    } catch (Throwable t) {
        entryError = t;
    }

    // 入口类的全部已知位置 URL + 由它们换算出的归档候选路径
    List<String> entryUrls = (entryClass == null)
            ? new ArrayList<String>()
            : locationUrlsOfClass(entryClass, webLoader);
    List<String> archiveCandidates = new ArrayList<String>();
    File entryArchive = null;
    for (int i = 0; i < entryUrls.size(); i++) {
        String candidate = archivePathFromUrl(entryUrls.get(i), ENTRY_CLASS);
        if (candidate == null || archiveCandidates.contains(candidate)) {
            continue;
        }
        archiveCandidates.add(candidate);
        File file = new File(candidate);
        if (file.isFile()) {
            // 命中真实存在的文件（jar），最可信，直接用
            entryArchive = file;
            break;
        }
        if (entryArchive == null) {
            // 先兜底记住，后面继续找更可信的
            entryArchive = file;
        }
    }

    // webapp 的 WEB-INF/lib 真实路径：它是普通磁盘目录，是最可靠的一路兜底
    String webLibPath = null;
    try {
        webLibPath = application.getRealPath("/WEB-INF/lib");
    } catch (Throwable ignored) {
    }
    List<File> libDirs = libDirCandidates(entryArchive, webLibPath);

    // 换算出来的路径若不存在（例如类是被动态装载的、位置不是文件系统路径），
    // 退一步：拿文件名去候选 lib 目录里找。
    boolean entryArchiveFoundByName = false;
    if (entryArchive != null && !entryArchive.exists() && entryArchive.getName().endsWith(".jar")) {
        File found = findJarInLibDirs(entryArchive.getName(), libDirs);
        if (found != null) {
            entryArchive = found;
            entryArchiveFoundByName = true;
        }
    }

    // 允许通过 ?jar=xxx.jar 切换到同目录下的其它 jar（只接受纯文件名，拒绝路径穿越）
    String requestedJar = request.getParameter("jar");
    String rejectedReason = null;
    if (requestedJar != null) {
        requestedJar = requestedJar.trim();
        if (requestedJar.length() == 0) {
            requestedJar = null;
        } else if (requestedJar.indexOf('/') >= 0 || requestedJar.indexOf('\\') >= 0
                || requestedJar.indexOf("..") >= 0) {
            rejectedReason = "参数只允许传同目录下的 jar 文件名，已忽略：" + requestedJar;
            requestedJar = null;
        }
    }

    // ===== 二、执行扫描 =====
    List<File> scanTargets = new ArrayList<File>();
    String targetNote;
    String targetError = null;
    if (requestedJar != null) {
        targetNote = "指定 jar（?jar=" + requestedJar + "）";
        File found = findJarInLibDirs(requestedJar, libDirs);
        if (found != null) {
            scanTargets.add(found);
        } else {
            targetError = "在候选目录里都没有找到指定的 jar：" + requestedJar;
        }
    } else {
        scanTargets = projectJarsOf(libDirs, entryArchive);
        targetNote = "自动识别：本项目全部 jar（前缀 " + String.join(" / ", PROJECT_JAR_PREFIXES) + "）";
    }

    Map<String, byte[]> scanClasses = new LinkedHashMap<String, byte[]>();
    // 类 → 它来自哪个 jar（用于缺失项归属定位）
    Map<String, String> classHomeJar = new LinkedHashMap<String, String>();
    List<String> scannedJars = new ArrayList<String>();
    List<String> skippedJars = new ArrayList<String>();
    String scanError = null;
    boolean scanSkipped = false;

    if (targetError != null) {
        scanError = targetError;
    } else if (scanTargets.isEmpty()) {
        scanError = "无法定位要扫描的文件：ArchivePushAction 的 class 来源为空，且候选目录下未找到任何本项目 jar。";
    } else {
        for (int i = 0; i < scanTargets.size(); i++) {
            File target = scanTargets.get(i);
            if (!target.exists()) {
                String miss = "扫描目标不存在：" + target.getAbsolutePath() + "（已按文件名在候选目录里查找，均未命中）";
                scanError = (scanError == null) ? miss : (scanError + "；" + miss);
                continue;
            }
            try {
                if (target.isDirectory()) {
                    mergeClasses(scanClasses, classesOfDir(target, target), target.getName(), classHomeJar);
                    scannedJars.add(target.getName() + "/");
                } else {
                    // 先看条目总数，避免误扫 classbean.jar 这类超大平台 jar 把页面拖死
                    int entryCount;
                    JarFile probe = new JarFile(target);
                    try {
                        entryCount = probe.size();
                    } finally {
                        probe.close();
                    }
                    if (entryCount > MAX_CLASSES_PER_ARCHIVE) {
                        scanSkipped = true;
                        skippedJars.add(target.getName() + "（条目 " + entryCount + "）");
                    } else {
                        mergeClasses(scanClasses, classesOfJar(target), target.getName(), classHomeJar);
                        scannedJars.add(target.getName());
                    }
                }
            } catch (Throwable t) {
                String msg = "读取 " + target.getName() + " 失败：" + t.getClass().getName() + ": " + t.getMessage();
                scanError = (scanError == null) ? msg : (scanError + "；" + msg);
            }
        }
        if (!scanTargets.isEmpty() && skippedJars.size() == scanTargets.size()) {
            scanError = "全部候选 jar 均因条目数超过上限 " + MAX_CLASSES_PER_ARCHIVE
                    + " 被跳过（本页只面向二次开发 jar）。";
        }
    }

    // 本 jar 内自有的类：作为「被引用方」不必检查（它们一定在同一个 jar 里）
    Set<String> ownClasses = new LinkedHashSet<String>(scanClasses.keySet());

    // 被引用类 → 引用它的本 jar 类集合
    Map<String, Set<String>> refToUsers = new LinkedHashMap<String, Set<String>>();
    int totalRefs = 0;

    for (Map.Entry<String, byte[]> entry : scanClasses.entrySet()) {
        Set<String> refs = classRefsOf(entry.getValue());
        for (String ref : refs) {
            if (ownClasses.contains(ref) || isJdkClass(ref)) {
                continue;
            }
            Set<String> users = refToUsers.get(ref);
            if (users == null) {
                users = new LinkedHashSet<String>();
                refToUsers.put(ref, users);
            }
            users.add(entry.getKey());
            totalRefs++;
        }
    }

    // ===== 三、逐个检查存在性 =====
    //
    // 三级判定（顺序不能换）：
    //   ① webapp 加载器能加载              → 真正可用，最好
    //   ② 其它加载器能加载 / 在 classbean 里 → 不计「缺失」，单列说明
    //   ③ 哪儿都没有                       → 真缺失
    // 第 ② 级是关键：classbean 是散装 .class 目录，必须逐文件找，不能扫 jar。

    // classbean 根目录（只保留真实存在的，用于逐文件查找）
    List<File> classbeanRoots = locateClassbeanRoots(application, webLibPath);
    List<File> classbeanDirs = new ArrayList<File>();
    for (int i = 0; i < classbeanRoots.size(); i++) {
        if (classbeanRoots.get(i).isDirectory()) {
            classbeanDirs.add(classbeanRoots.get(i));
        }
    }
    // webapp 加载器之外的候选加载器
    List<ClassLoader> otherLoaders = extraLoaders(webLoader);

    Map<String, Integer> missing = new LinkedHashMap<String, Integer>();
    Map<String, String> missingReason = new LinkedHashMap<String, String>();
    // 仅「其它加载器」可见（webapp 加载器看不见）
    Map<String, String> byOtherLoader = new LinkedHashMap<String, String>();
    // 有任何加载器都加载不了、但 classbean 磁盘上有文件
    Map<String, String> byClassbeanOnly = new LinkedHashMap<String, String>();
    int checkedCount = 0;
    int presentCount = 0;
    int otherLoaderCount = 0;
    int classbeanOnlyCount = 0;
    int absentCount = 0;      // 类文件真的没有
    int parentBrokenCount = 0; // 类文件在，但父类/接口缺

    List<String> refNames = new ArrayList<String>(refToUsers.keySet());
    Collections.sort(refNames);
    for (String ref : refNames) {
        checkedCount++;
        Throwable primaryError;
        try {
            Class.forName(ref, false, webLoader);
            presentCount++;
            continue;
        } catch (Throwable t) {
            primaryError = t;
        }
        // ② -a：换个类加载器再试
        ClassLoader hitLoader = resolveWith(ref, otherLoaders);
        if (hitLoader != null) {
            byOtherLoader.put(ref, String.valueOf(hitLoader));
            otherLoaderCount++;
            continue;
        }
        // ② -b：classbean 目录里逐文件找（不是扫 jar）
        File classbeanHit = findClassbeanFile(ref, classbeanDirs);
        if (classbeanHit != null) {
            byClassbeanOnly.put(ref, classbeanHit.getAbsolutePath());
            classbeanOnlyCount++;
            continue;
        }
        // ③ 真缺失
        missing.put(ref, Integer.valueOf(refToUsers.get(ref).size()));
        missingReason.put(ref, describeFailure(primaryError));
        if (primaryError instanceof ClassNotFoundException) {
            absentCount++;
        } else if (primaryError instanceof NoClassDefFoundError) {
            parentBrokenCount++;
        }
    }

    // 按包分组，便于阅读
    Map<String, List<String>> missingByPackage = new LinkedHashMap<String, List<String>>();
    for (String cls : missing.keySet()) {
        int dot = cls.lastIndexOf('.');
        String pkg = (dot > 0) ? cls.substring(0, dot) : "(默认包)";
        List<String> list = missingByPackage.get(pkg);
        if (list == null) {
            list = new ArrayList<String>();
            missingByPackage.put(pkg, list);
        }
        list.add(cls);
    }
%>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>依赖缺失全量扫描</title>
    <style>
        body { font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif; font-size: 13px; color: #2C2C2A; margin: 24px; line-height: 1.7; }
        h1 { font-size: 18px; font-weight: 500; margin: 0 0 4px 0; }
        h2 { font-size: 15px; font-weight: 500; margin: 26px 0 8px 0; padding-bottom: 4px; border-bottom: 1px solid #D3D1C7; }
        table { border-collapse: collapse; width: 100%; margin: 8px 0; }
        th, td { border: 1px solid #D3D1C7; padding: 6px 10px; text-align: left; vertical-align: top; word-break: break-all; }
        th { background: #F1EFE8; font-weight: 500; }
        pre { background: #F1EFE8; border: 1px solid #D3D1C7; border-radius: 6px; padding: 10px; overflow-x: auto; font-size: 12px; white-space: pre-wrap; word-break: break-all; }
        .warn { background: #FAEEDA; border: 1px solid #EF9F27; border-radius: 6px; padding: 8px 12px; font-size: 12px; }
        .ok { color: #0F6E56; }
        .fail { color: #A32D2D; }
        .muted { color: #5F5E5A; font-size: 12px; }
        code { font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 12px; }
        a { color: #185FA5; }
    </style>
</head>
<body>

<h1>依赖缺失全量扫描</h1>
<p class="muted">
    入口类：<code><%= escapeHtml(ENTRY_CLASS) %></code>　扫描时间：<%= new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new java.util.Date()) %>
</p>

<div class="warn">
    本页面为临时诊断工具。<b>不会重启服务、不会重载应用</b>：它只读取磁盘上的 class 文件字节并解析常量池，
    再对每个类型引用做一次存在性检查。排查完成后请立即从服务器删除该 JSP 文件。
</div>

<h2>一、扫描目标</h2>
<table>
    <tr><th style="width:220px;">项目</th><th>值</th></tr>
    <tr><td>入口类是否可加载</td><td><%= entryClass != null
            ? span("ok", "是")
            : "<span class=\"fail\">否：" + escapeHtml(entryError == null ? "未知" : String.valueOf(entryError)) + "</span>" %></td></tr>
    <tr><td>入口类位置（原始 URL）</td><td><%
        if (entryUrls.isEmpty()) {
            out.print("<span class=\"muted\">-</span>");
        } else {
            for (int i = 0; i < entryUrls.size(); i++) {
                if (i > 0) {
                    out.print("<br>");
                }
                out.print("<code>" + escapeHtml(entryUrls.get(i)) + "</code>");
            }
        }
    %></td></tr>
    <tr><td>换算出的归档路径</td><td><%
        if (archiveCandidates.isEmpty()) {
            out.print("<span class=\"muted\">-</span>");
        } else {
            for (int i = 0; i < archiveCandidates.size(); i++) {
                if (i > 0) {
                    out.print("<br>");
                }
                File candidateFile = new File(archiveCandidates.get(i));
                out.print("<code>" + escapeHtml(archiveCandidates.get(i)) + "</code> "
                        + (candidateFile.exists()
                                ? span("ok", "存在")
                                : span("fail", "不存在")));
            }
        }
    %><br><span class="muted">Resin 会把 CodeSource 指到 jar 内部的 class 文件上（形如
        <code>xxx.jar/com/a/B.class</code> 或 <code>xxx.jar!/com/a/B.class</code>），
        本页会先把它截断到 <code>.jar</code> 为止再判断。</span></td></tr>
    <tr><td>解析结果是否来自文件名兜底</td><td><%= entryArchiveFoundByName
            ? span("ok", "是（按 jar 文件名在候选目录里找到的）")
            : "<span class=\"muted\">否（直接由路径换算得到）</span>" %></td></tr>
    <tr><td>候选 lib 目录</td><td><%
        if (libDirs.isEmpty()) {
            out.print("<span class=\"fail\">未能确定任何候选目录</span>");
        } else {
            for (int i = 0; i < libDirs.size(); i++) {
                if (i > 0) {
                    out.print("<br>");
                }
                out.print("<code>" + escapeHtml(libDirs.get(i).getAbsolutePath()) + "</code> "
                        + (libDirs.get(i).isDirectory()
                                ? span("ok", "是目录")
                                : span("fail", "不存在")));
            }
        }
    %><br><span class="muted">第一个来自入口类位置，其余来自
        <code>application.getRealPath("/WEB-INF/lib")</code>。
        <code>?jar=</code> 指定的 jar 会在这些目录里查找。</span></td></tr>
    <tr><td>classbean 目录<br><span class="muted">（散装 .class，非 jar）</span></td><td><%
        if (classbeanRoots.isEmpty()) {
            out.print("<span class=\"fail\">未能确定任何候选目录</span>");
        } else {
            for (int i = 0; i < classbeanRoots.size(); i++) {
                if (i > 0) {
                    out.print("<br>");
                }
                File cb = classbeanRoots.get(i);
                out.print("<code>" + escapeHtml(cb.getAbsolutePath()) + "</code> "
                        + (cb.isDirectory() ? span("ok", "是目录") : span("muted", "不存在")));
            }
        }
    %><br><span class="muted">E9 的平台补丁类与二开类放在这里，里面是<b>散装 .class 文件</b>
        （本机 35508 个），<b>不是 jar</b>。本页对「webapp 加载器加载不到」的引用会再来这里
        <b>逐文件</b>找一次 —— 命中的不计入缺失。
        实测 <code>weaver.conn.RecordSet</code> 在 610 个 jar 里一个都没有、只存在于 classbean，
        而它从未被报缺失，说明 webapp 加载器本来就看得见 classbean。</span></td></tr>
    <tr><td>本次扫描对象</td><td><code><%= escapeHtml(targetNote) %></code></td></tr>
    <tr><td>　　实际扫描的 jar</td><td><%
        if (scannedJars.isEmpty()) {
            out.print("<span class=\"fail\">（无 —— 没有扫到任何 jar）</span>");
        } else {
            for (int i = 0; i < scannedJars.size(); i++) {
                if (i > 0) {
                    out.print("<br>");
                }
                out.print("<code>" + escapeHtml(scannedJars.get(i)) + "</code>");
            }
        }
        if (!skippedJars.isEmpty()) {
            out.print("<br><span class=\"muted\">已跳过（条目数超上限）：");
            for (int i = 0; i < skippedJars.size(); i++) {
                if (i > 0) {
                    out.print("、");
                }
                out.print(escapeHtml(skippedJars.get(i)));
            }
            out.print("</span>");
        }
    %><br><span class="muted">默认扫描<b>全部本项目 jar</b>：三个推送入口的业务实现分散在
        主 jar、<code>weaver-seconddev-pde-archive-*.jar</code> 与
        <code>seconddev-common-lib-*.jar</code>（common 模块产物，文件名不以
        <code>weaver-</code> 开头，靠 <code>seconddev-</code> 前缀纳入）里，
        只扫入口 jar 会漏掉文档获取/转换/表单 PDF 所引用的依赖
        —— <code>com.itextpdf.text.*</code> 就是这样漏掉过一次。
        需要单个 jar 时用 <code>?jar=文件名</code>。</span></td></tr>
<%
    if (rejectedReason != null) {
%>
    <tr><td>参数被忽略</td><td><span class="fail"><%= escapeHtml(rejectedReason) %></span></td></tr>
<%
    }
%>
    <tr><td>本页的类加载器</td><td><code><%= escapeHtml(String.valueOf(webLoader)) %></code></td></tr>
</table>

<h2>二、扫描概况</h2>
<%
    if (scanError != null) {
%>
<p><span class="fail"><%= escapeHtml(scanError) %></span></p>
<%
    } else {
%>
<table>
    <tr><th style="width:300px;">项目</th><th>数量</th></tr>
    <tr><td>扫描到的 class 文件</td><td><%= scanClasses.size() %></td></tr>
    <tr><td>提取到的外部类型引用（去重后）</td><td><%= refToUsers.size() %></td></tr>
    <tr><td>引用次数合计</td><td><%= totalRefs %></td></tr>
    <tr><td>存在性检查次数</td><td><%= checkedCount %></td></tr>
    <tr><td>① webapp 类加载器能找到</td><td><%= presentCount %></td></tr>
    <tr><td>② 仅<b>其它</b>类加载器能找到
        <span class="muted">（webapp 加载器看不见，不计缺失）</span></td><td><%= otherLoaderCount %></td></tr>
    <tr><td>③ 仅在 <code>classbean</code> 目录里找到
        <span class="muted">（散装 .class，不计缺失）</span></td><td><%= classbeanOnlyCount %></td></tr>
    <tr><td><b>④ 哪儿都找不到（真缺失）</b>
        <span class="muted">（WEB-INF/lib 与 classbean 均已查过）</span></td><td><%= missing.isEmpty()
            ? span("ok", "0 —— 未发现缺失依赖")
            : "<span class=\"fail\">" + missing.size() + "</span>" %></td></tr>
    <tr><td>　└ 类文件真的不存在
        <span class="muted">（ClassNotFoundException）</span></td><td><%= absentCount %></td></tr>
    <tr><td>　└ 类文件在、父类/接口缺
        <span class="muted">（NoClassDefFoundError，真正缺的是消息里那个）</span></td><td><%= parentBrokenCount %></td></tr>
</table>
<%
    }
%>

<h2>三、缺失依赖清单</h2>
<%
    if (scanError != null) {
%>
<p class="muted">扫描未完成，无结果。</p>
<%
    } else if (missing.isEmpty()) {
%>
<p class="ok">本 jar 引用的所有外部类型，在运行期 classpath 上都能找到，未发现缺失依赖。</p>
<%
    } else {
%>
<p class="muted">
    下表每一行都是「被本 jar 的代码引用、但 <b>WEB-INF/lib 与 classbean 都找不到</b>」的类。
    <b>「被引用次数」和引用方可以帮助判断危险程度</b>：被核心业务类大量引用的，基本一定会踩到；
    只被个别边缘类引用的，可能永远走不到。
    <b>「失败原因」一列必须看</b>：<code>NoClassDefFoundError</code> 说明这个类的 class 文件是存在的，
    缺的是它消息里那个父类/接口 —— 别照着本列的名字去补 jar。
</p>
<table>
    <tr><th style="width:290px;">缺失的类</th><th style="width:70px;">次数</th><th style="width:130px;">关键业务</th><th style="width:230px;">失败原因</th><th>引用它的本项目类（最多列 6 个）</th></tr>
<%
        Map<String, String> bizShort = keyBizShort();
        for (Map.Entry<String, Integer> entry : missing.entrySet()) {
            String cls = entry.getKey();
            Set<String> users = refToUsers.get(cls);
            StringBuilder userText = new StringBuilder();
            int shown = 0;
            for (String user : users) {
                if (shown >= 6) {
                    userText.append("<br>... 共 ").append(users.size()).append(" 个引用方");
                    break;
                }
                if (shown > 0) {
                    userText.append("<br>");
                }
                userText.append(escapeHtml(user));
                shown++;
            }
            // 关键业务标注：引用方里是否命中 KEY_BIZ_CLASSES
            StringBuilder bizHit = new StringBuilder();
            for (String user : users) {
                String shortName = bizShort.get(user);
                if (shortName == null) {
                    continue;
                }
                if (bizHit.length() > 0) {
                    bizHit.append("<br>");
                }
                bizHit.append(escapeHtml(shortName));
            }
            String reason = missingReason.get(cls);
            boolean parentBroken = (reason != null) && reason.startsWith("NoClassDefFoundError");
            // 归属 jar：取第一个引用方（LinkedHashSet 顺序稳定）所在的 jar
            String firstUser = users.isEmpty() ? null : users.iterator().next();
            String homeJar = (firstUser == null) ? null : classHomeJar.get(firstUser);
%>
    <tr>
        <td><code><%= escapeHtml(cls) %></code><%
            if (homeJar != null) {
                out.print("<br><span class=\"muted\" style=\"font-size:11px;\">from " + escapeHtml(homeJar) + "</span>");
            }
        %></td>
        <td><%= entry.getValue() %></td>
        <td><%= bizHit.length() > 0
                ? "<span class=\"fail\"><b>★ 命中</b><br>" + bizHit.toString() + "</span>"
                : "<span class=\"muted\">—</span>" %></td>
        <td class="muted"><%= parentBroken
                ? "<span class=\"fail\">" + escapeHtml(reason) + "</span>"
                : escapeHtml(reason) %></td>
        <td class="muted"><%= userText.toString() %></td>
    </tr>
<%
        }
%>
</table>
<%
        // 根因归并：NoClassDefFoundError 的真正缺失项（同一个根因会被多个类重复报出）
        Map<String, Set<String>> rootCauses = new LinkedHashMap<String, Set<String>>();
        for (Map.Entry<String, String> reasonEntry : missingReason.entrySet()) {
            String reason = reasonEntry.getValue();
            if (reason == null || !reason.startsWith("NoClassDefFoundError")) {
                continue;
            }
            String culprit = reason;
            int colon = culprit.indexOf(": ");
            int dash = culprit.indexOf(" ——");
            if (colon >= 0 && dash > colon) {
                culprit = culprit.substring(colon + 2, dash).trim();
            }
            Set<String> affected = rootCauses.get(culprit);
            if (affected == null) {
                affected = new LinkedHashSet<String>();
                rootCauses.put(culprit, affected);
            }
            affected.add(reasonEntry.getKey());
        }
        if (!rootCauses.isEmpty()) {
%>
<p class="muted"><b>根因归并</b>：下面这几个才是 <code>NoClassDefFoundError</code> 的真正缺失项。
    <b>补它们，比照着上一张表的类名去补 jar 更直接</b> —— 上一张表里对应的类，class 文件其实是在的。</p>
<table>
    <tr><th style="width:340px;">真正缺失的类</th><th>因此加载失败的类</th></tr>
<%
            for (Map.Entry<String, Set<String>> rootEntry : rootCauses.entrySet()) {
                StringBuilder affectedText = new StringBuilder();
                for (String one : rootEntry.getValue()) {
                    if (affectedText.length() > 0) {
                        affectedText.append("<br>");
                    }
                    affectedText.append(escapeHtml(one));
                }
%>
    <tr>
        <td><code><%= escapeHtml(rootEntry.getKey()) %></code></td>
        <td class="muted"><%= affectedText.toString() %></td>
    </tr>
<%
            }
%>
</table>
<%
        }
    }
%>

<%
    // 三之二：不在 webapp 加载器视野内、但确实存在的引用 —— 不计缺失，单列出来
    if (scanError == null && (!byOtherLoader.isEmpty() || !byClassbeanOnly.isEmpty())) {
%>

<h2>三之二、不在 webapp 加载器视野内、但实际存在的引用</h2>
<p class="muted">
    下面这些类<b>不是缺失</b>：第一轮检查（webapp 类加载器）看不到它们，
    但换成其它类加载器、或到 <code>classbean</code> 目录里就找到了。
    它们已从「缺失清单」中剔除，<b>不需要补 jar</b>。
</p>
<table>
    <tr><th style="width:300px;">类</th><th style="width:110px;">命中方式</th>
        <th style="width:280px;">证据</th><th>引用方数</th></tr>
<%
        for (Map.Entry<String, String> olEntry : byOtherLoader.entrySet()) {
            Set<String> olUsers = refToUsers.get(olEntry.getKey());
%>
    <tr>
        <td><code><%= escapeHtml(olEntry.getKey()) %></code></td>
        <td><span class="ok">其它加载器</span></td>
        <td class="muted"><code><%= escapeHtml(olEntry.getValue()) %></code></td>
        <td><%= olUsers == null ? 0 : olUsers.size() %></td>
    </tr>
<%
        }
        for (Map.Entry<String, String> cbEntry : byClassbeanOnly.entrySet()) {
            Set<String> cbUsers = refToUsers.get(cbEntry.getKey());
%>
    <tr>
        <td><code><%= escapeHtml(cbEntry.getKey()) %></code></td>
        <td><span class="fail">仅 classbean</span></td>
        <td class="muted"><code><%= escapeHtml(cbEntry.getValue()) %></code></td>
        <td><%= cbUsers == null ? 0 : cbUsers.size() %></td>
    </tr>
<%
        }
%>
</table>
<%
        if (!byClassbeanOnly.isEmpty()) {
%>
<div class="warn">
    <b>「仅 classbean」这几项要特别当心</b>：它们的 <code>.class</code> 文件确实躺在
    <code>classbean</code> 目录里，但<b>当前所有候选加载器都加载不了它</b>。
    这通常意味着该目录没有被这个 webapp 的类加载器纳入 classpath（<b>加载器隔离</b>），
    运行期一旦真的用到它，照样会抛 <code>NoClassDefFoundError</code>。
    请先确认 <code>classbean</code> 是否配在了 <code>resin.conf</code> 或启动参数里；
    <b>不要直接往 WEB-INF/lib 丢一个同名 jar</b>，那样很容易和平台类产生版本冲突。
</div>
<%
        }
        if (!byOtherLoader.isEmpty()) {
%>
<p class="muted">
    「其它加载器」命中的项通常是平台自身的实现类，webapp 加载器看不见它们属于
    <b>正常的类加载器隔离</b>，运行期由对应加载器负责，一般无需处理。
    若其中某个类被关键业务类引用、你仍担心运行期取不到，可结合
    <code>RunArchivePushAction.jsp</code> 的执行结果一起看。
</p>
<%
        }
    }
%>

<h2>四、按包分组汇总</h2>
<%
    if (scanError != null || missing.isEmpty()) {
%>
<p class="muted">无数据。</p>
<%
    } else {
%>
<table>
    <tr><th style="width:60%">包名</th><th>缺失类数量</th></tr>
<%
        for (Map.Entry<String, List<String>> entry : missingByPackage.entrySet()) {
%>
    <tr>
        <td><code><%= escapeHtml(entry.getKey()) %></code></td>
        <td><%= entry.getValue().size() %></td>
    </tr>
<%
        }
%>
</table>
<p class="muted">提示：同一包集中缺失，通常意味着「少了一个整 jar」，比零散缺失更好处理。</p>
<%
    }
%>

<h2>五、结论与处置</h2>
<%
    if (scanError != null) {
%>
<p><span class="fail">扫描未完成：<%= escapeHtml(scanError) %></span></p>
<%
        if (scanSkipped) {
%>
<p class="muted">可直接用 <code>?jar=文件名</code> 指定要扫描的二次开发 jar，例如
    <code>CheckMissingDeps.jsp?jar=weaver-seconddev-pde-archive-1.0.0.jar</code>。</p>
<%
        }
    } else if (missing.isEmpty()) {
%>
<p class="ok">未发现缺失依赖：本 jar 引用的所有外部类型，在 WEB-INF/lib 的 jar 与
    <code>classbean</code> 目录里都能找到。</p>
<%
    } else {
%>
<p><b class="fail">共发现 <%= missing.size() %> 个缺失的类。</b>处理方式二选一：</p>
<ul>
    <li><b>补齐依赖 jar</b>：若这些类集中在同一个第三方库，把对应的 jar 放进
        <code>ecology/WEB-INF/lib/</code>（注意版本要与编译期一致，且需要重载应用才生效）。</li>
    <li><b>代码侧容错</b>：若该类只被个别非核心路径引用（例如可选的 Redis 支持），
        可在调用处用 <code>Class.forName(名称, false, 加载器)</code> 先探测、再决定是否调用，
        并 <code>catch (Throwable)</code> 兜底 —— 注意类缺失抛的是
        <code>NoClassDefFoundError</code>（Error），<code>catch (Exception)</code> 抓不到。</li>
</ul>
<p class="muted">
    <b>先看「关键业务」一列。</b>标了 <span class="fail">★ 命中</span> 的缺失类，引用方是归档推送
    业务链路上的类（表单文档获取 <code>WorkflowFileManager</code>、文档转换
    <code>ArchiveFileConvertor</code>/<code>YozoDcsConvertManager</code>、流程表单页面 PDF
    <code>WorkflowFormPdfCreator</code>、契约锁签名 <code>FileSignatureHandler</code> 等），
    这些一定会被踩到，必须补；
    标 <span class="muted">—</span> 的说明引用方都不在业务链路上，多半是走不到的死代码。
</p>
<p class="muted">
    <b>「缺失」是怎么判出来的（三级）</b>：① 先用 webapp 类加载器加载（<code>Class.forName</code>）；
    ② 加载不到就换线程上下文加载器 / 系统加载器 / 平台参照类所在加载器再试；
    ③ 还不行就到 <code>classbean</code> 目录里按「包名 → 目录」逐文件找 <code>.class</code>
    —— 该目录存的是散装 class、<b>不是 jar</b>，不能用扫 jar 的办法。
    三步都落空才计入缺失。因此本表每一行都是
    <b>WEB-INF/lib 与 classbean 双重复核后仍然找不到</b>的类；
    只在 classbean 或其它加载器里找到的，已移到「三之二」单独列出、不计缺失。
</p>
<p class="muted">
    注意：本页是<b>静态引用</b>分析，属于「宁可多报」——列出的类里，有一部分实际
    （如从未被调用的分支、仅备用的实现类）可能永远不会被加载。要判断是否真的会踩到，
    可结合 <code>RunArchivePushAction.jsp</code> 的运行时执行验证一起看。
</p>
<%
    }
%>

<h2>六、切换到其它 jar</h2>
<%
    // 先走 webapp 资源路径（不依赖真实目录是否可列），再用候选目录兜底
    List<String> names = new ArrayList<String>();
    Set<String> seenNames = new LinkedHashSet<String>();
    try {
        Set<String> resourcePaths = application.getResourcePaths("/WEB-INF/lib");
        if (resourcePaths != null) {
            for (String path : resourcePaths) {
                if (path != null && path.toLowerCase().endsWith(".jar")) {
                    int slash = path.lastIndexOf('/');
                    String name = (slash >= 0) ? path.substring(slash + 1) : path;
                    if (seenNames.add(name)) {
                        names.add(name);
                    }
                }
            }
        }
    } catch (Throwable ignored) {
    }
    for (int i = 0; i < libDirs.size(); i++) {
        File[] siblings = libDirs.get(i).listFiles();
        if (siblings == null) {
            continue;
        }
        for (int k = 0; k < siblings.length; k++) {
            if (siblings[k].isFile() && siblings[k].getName().toLowerCase().endsWith(".jar")) {
                if (seenNames.add(siblings[k].getName())) {
                    names.add(siblings[k].getName());
                }
            }
        }
    }
    Collections.sort(names);

    if (names.isEmpty()) {
%>
<p class="muted">未能列出任何 jar。候选目录：
    <code><%= escapeHtml(libDirs.isEmpty() ? "(无)" : libDirs.get(0).getAbsolutePath()) %></code>，
    可直接手工拼 URL：<code>CheckMissingDeps.jsp?jar=weaver-seconddev-YulinPolice-dev-1.0.0.jar</code></p>
<%
    } else {
%>
<p class="muted">共发现 <%= names.size() %> 个 jar，点击可只扫那一个。
    <b>带 ★ 的是本项目 jar</b>（默认已全扫），平台级 jar（条目数很大的）会被自动跳过。
    不带参数访问本页 = 扫描全部 ★ jar，这是推荐方式。</p>
<pre><%
        StringBuilder links = new StringBuilder();
        for (String name : names) {
            if (links.length() > 0) {
                links.append('\n');
            }
            links.append(isProjectJar(name) ? "★ " : "  ");
            links.append("<a href=\"CheckMissingDeps.jsp?jar=").append(escapeHtml(name)).append("\">")
                    .append(escapeHtml(name)).append("</a>");
        }
        out.print(links.toString());
%></pre>
<%
    }
%>

</body>
</html>
