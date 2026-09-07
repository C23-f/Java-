package com.example.springboot.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * 跨域配置（CORS）
 * 解决前端页面（不同端口/域名）调用后端接口时被浏览器拦截的问题，
 * 例如前端跑在 localhost:5173，后端跑在 localhost:8080，属于跨域。
 *
 * 生效范围：所有 /api/** 接口
 */
@Configuration
public class CorsConfig implements WebMvcConfigurer {

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")          // 允许跨域的路径
                .allowedOriginPatterns("*")      // 允许所有来源（开发阶段方便联调）
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS") // 允许的请求方式
                .allowedHeaders("*")             // 允许所有请求头（含 token 等自定义头）
                .allowCredentials(true)          // 允许携带 Cookie / 凭证
                .maxAge(3600);                   // 预检请求结果缓存 1 小时，减少 OPTIONS 请求
    }
}
