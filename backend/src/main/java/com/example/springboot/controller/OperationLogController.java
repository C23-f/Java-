package com.example.springboot.controller;

import com.example.springboot.common.Result;
import com.example.springboot.entity.OperationLog;
import com.example.springboot.entity.PageResult;
import com.example.springboot.service.OperationLogService;
import jakarta.annotation.Resource;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 操作日志 Controller（仅管理员可访问，权限在 JwtInterceptor 校验）
 */
@RestController
@RequestMapping("/api/log")
public class OperationLogController {

    @Resource
    private OperationLogService operationLogService;

    /** 分页查询操作日志 GET /api/log/list */
    @GetMapping("/list")
    public Result<PageResult<OperationLog>> list(
            @RequestParam(defaultValue = "1") Integer page,
            @RequestParam(defaultValue = "10") Integer size,
            @RequestParam(required = false) Integer operatorId,
            @RequestParam(required = false) String actionType) {
        return Result.success(operationLogService.listLog(page, size, operatorId, actionType));
    }
}
