package com.example.springboot.common;

import lombok.Data;

/**
 * 统一返回结果类
 * 所有接口都返回这个格式：{ code, message, data }
 */
@Data
public class Result<T> {

    private Integer code;
    private String message;
    private T data;

    /** 成功返回，带数据 */
    public static <T> Result<T> success(T data) {
        Result<T> r = new Result<>();
        r.setCode(200);
        r.setMessage("成功");
        r.setData(data);
        return r;
    }

    public static <T> Result<T> error(String message) {
        Result<T> r = new Result<>();
        r.setCode(500);
        r.setMessage(message);
        return r;
    }
}
