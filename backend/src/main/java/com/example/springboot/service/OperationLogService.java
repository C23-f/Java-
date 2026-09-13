package com.example.springboot.service;

import com.example.springboot.entity.OperationLog;
import com.example.springboot.entity.PageResult;

public interface OperationLogService {

    /**
     * 记录一条操作日志（自动从当前登录上下文取操作人；未登录时忽略）
     * @param actionType 操作类型：新增/修改/删除/评价审核
     * @param targetType 对象类型：community/facility/evaluation 等
     * @param targetId   对象ID
     * @param detail     操作详情描述
     */
    void log(String actionType, String targetType, Integer targetId, String detail);

    // 分页查询操作日志
    PageResult<OperationLog> listLog(Integer pageNum, Integer pageSize,
                                     Integer operatorId, String actionType);
}
