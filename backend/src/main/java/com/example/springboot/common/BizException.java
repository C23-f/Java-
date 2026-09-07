package com.example.springboot.common;

/**
 * 自定义业务异常
 * 业务逻辑中需要主动抛出错误时使用，例如：
 *     throw new BizException("该小区不存在");
 * 会被 GlobalExceptionHandler 统一捕获并返回给前端
 */
public class BizException extends RuntimeException {

    private final Integer code;

    public BizException(String message) {
        super(message);
        this.code = 500;
    }

    public BizException(Integer code, String message) {
        super(message);
        this.code = code;
    }

    public Integer getCode() {
        return code;
    }
}
