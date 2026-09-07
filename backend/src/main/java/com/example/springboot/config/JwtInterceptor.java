package com.example.springboot.config;

import com.example.springboot.common.JwtUtil;
import com.example.springboot.common.UserContext;
import com.example.springboot.entity.User;
import io.jsonwebtoken.Claims;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import java.io.IOException;
import java.util.List;

/**
 * 登录与权限校验拦截器
 * 拦截所有 /api/** 请求（登录接口除外），做两步校验：
 *   1. 令牌校验：解析 Authorization 请求头里的 JWT，失败返回 401
 *   2. 角色权限：根据路径和请求方式判断当前角色是否有权访问，无权返回 403
 */
@Component
public class JwtInterceptor implements HandlerInterceptor {

    /** 数据写操作（增删改）涉及的路径前缀，需 admin 或 operator 角色 */
    private static final List<String> DATA_WRITE_PREFIX =
            List.of("/api/community", "/api/facility", "/api/category");

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler)
            throws Exception {
        // CORS 预检请求直接放行
        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
            return true;
        }

        // ---------- 第一步：校验令牌 ----------
        String token = request.getHeader("Authorization");
        if (token != null && token.startsWith("Bearer ")) {
            token = token.substring(7);
        }
        if (token == null || token.isEmpty()) {
            return writeJson(response, 401, "未登录，请先登录");
        }

        try {
            Claims claims = JwtUtil.parseToken(token);
            User user = new User();
            user.setUserId(Integer.valueOf(claims.getSubject()));
            user.setUsername(claims.get("username", String.class));
            user.setRoleCode(claims.get("roleCode", String.class));
            UserContext.set(user);
        } catch (Exception e) {
            return writeJson(response, 401, "登录已过期，请重新登录");
        }

        // ---------- 第二步：角色权限校验 ----------
        String uri = request.getRequestURI();
        String method = request.getMethod();
        String roleCode = UserContext.get().getRoleCode();

        // 用户管理 / 角色管理：仅 admin（/api/user/info 除外，所有登录用户都可查自己）
        boolean adminPath = uri.startsWith("/api/role/")
                || (uri.startsWith("/api/user/") && !uri.endsWith("/info"));
        if (adminPath && !"admin".equals(roleCode)) {
            return writeJson(response, 403, "无权限操作，仅管理员可访问");
        }

        // 小区 / 设施 / 分类的增删改：admin 或 operator（viewer 只读）
        boolean dataWrite = "POST".equals(method) || "PUT".equals(method) || "DELETE".equals(method);
        if (dataWrite && DATA_WRITE_PREFIX.stream().anyMatch(uri::startsWith)
                && !("admin".equals(roleCode) || "operator".equals(roleCode))) {
            return writeJson(response, 403, "无权限操作，仅管理员或运营人员可访问");
        }

        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response,
                                Object handler, Exception ex) {
        // 请求结束清理 ThreadLocal，防止线程池复用导致数据串号
        UserContext.clear();
    }

    /** 以统一 Result 结构输出 401/403 */
    private boolean writeJson(HttpServletResponse response, int code, String message) throws IOException {
        response.setContentType("application/json;charset=UTF-8");
        response.getWriter().write(String.format("{\"code\":%d,\"message\":\"%s\",\"data\":null}", code, message));
        return false;
    }
}
