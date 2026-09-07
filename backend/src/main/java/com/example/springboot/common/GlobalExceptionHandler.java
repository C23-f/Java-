package com.example.springboot.common;

import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.BindException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

import java.sql.SQLException;
import java.util.stream.Collectors;

/**
 * 全局异常处理器
 * 用 @RestControllerAdvice 统一捕获所有 Controller 抛出的异常，
 * 统一包装成 Result 结构返回给前端，避免前端拿到一堆看不懂的堆栈信息。
 *
 * 生效范围：所有 @RestController 接口
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    /** 1. 业务异常：代码里主动 throw new BizException("提示信息") */
    @ExceptionHandler(BizException.class)
    public Result<?> handleBizException(BizException e) {
        return Result.error(e.getMessage());
    }

    /** 2. 参数校验异常：@RequestBody 里的 @Valid 校验不通过 */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public Result<?> handleValidException(MethodArgumentNotValidException e) {
        String msg = e.getBindingResult().getFieldErrors().stream()
                .map(FieldError::getDefaultMessage)
                .collect(Collectors.joining("；"));
        return Result.error("参数校验失败：" + msg);
    }

    /** 3. 表单参数校验异常（非 JSON body 场景） */
    @ExceptionHandler(BindException.class)
    public Result<?> handleBindException(BindException e) {
        String msg = e.getBindingResult().getFieldErrors().stream()
                .map(FieldError::getDefaultMessage)
                .collect(Collectors.joining("；"));
        return Result.error("参数校验失败：" + msg);
    }

    /** 4. 缺少必填参数：例如 @RequestParam 没传 */
    @ExceptionHandler(MissingServletRequestParameterException.class)
    public Result<?> handleMissingParam(MissingServletRequestParameterException e) {
        return Result.error("缺少必填参数：" + e.getParameterName());
    }

    /** 5. 参数类型不匹配：例如传了 id=abc 而接口要的是数字 */
    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public Result<?> handleTypeMismatch(MethodArgumentTypeMismatchException e) {
        return Result.error("参数 " + e.getName() + " 类型不正确，应为 " + e.getRequiredType().getSimpleName());
    }

    /** 6. JSON 请求体无法解析 */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public Result<?> handleNotReadable(HttpMessageNotReadableException e) {
        return Result.error("请求体格式错误，请检查 JSON 格式");
    }

    /** 6.1 请求方式不支持：例如用 GET 访问 POST 接口 */
    @ExceptionHandler(org.springframework.web.HttpRequestMethodNotSupportedException.class)
    public Result<?> handleMethodNotSupported(org.springframework.web.HttpRequestMethodNotSupportedException e) {
        return Result.error("请求方式不支持，请使用 " + String.join("/", e.getSupportedMethods()) + " 方式访问");
    }

    /** 7. 数据库唯一键冲突：重复插入 */
    @ExceptionHandler(DuplicateKeyException.class)
    public Result<?> handleDuplicateKey(DuplicateKeyException e) {
        return Result.error("数据已存在，请勿重复添加");
    }

    /** 8. SQL 执行异常 */
    @ExceptionHandler(SQLException.class)
    public Result<?> handleSqlException(SQLException e) {
        return Result.error("数据库操作失败：" + e.getMessage());
    }

    /** 9. 兜底异常：没被上面匹配到的所有异常都走这里 */
    @ExceptionHandler(Exception.class)
    public Result<?> handleException(Exception e) {
        // 开发阶段把异常信息打印到控制台，方便排查问题
        e.printStackTrace();
        return Result.error("系统异常，请稍后重试：" + e.getMessage());
    }
}
