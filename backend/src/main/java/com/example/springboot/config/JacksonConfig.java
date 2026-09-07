package com.example.springboot.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.http.converter.HttpMessageConverter;
import org.springframework.http.converter.json.JacksonJsonHttpMessageConverter;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * Jackson 序列化配置
 * 让 JSON 接口响应头带上 charset=UTF-8 声明，
 * 避免 Windows PowerShell 5.1 等客户端因缺少 charset 而按错误编码解码中文导致乱码
 */
@Configuration
public class JacksonConfig implements WebMvcConfigurer {

    @Override
    public void extendMessageConverters(List<HttpMessageConverter<?>> converters) {
        for (HttpMessageConverter<?> converter : converters) {
            if (converter instanceof JacksonJsonHttpMessageConverter) {
                JacksonJsonHttpMessageConverter jackson = (JacksonJsonHttpMessageConverter) converter;
                jackson.setDefaultCharset(StandardCharsets.UTF_8);
                jackson.setSupportedMediaTypes(List.of(
                        new MediaType("application", "json", StandardCharsets.UTF_8),
                        new MediaType("application", "*+json", StandardCharsets.UTF_8)
                ));
            }
        }
    }
}
