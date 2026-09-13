package com.example.springboot.entity;

import lombok.Data;
import java.time.LocalDateTime;

/**
 * 操作日志实体，对应 operation_log 表
 * 记录管理员增删改、评价审核等关键操作，便于审计追溯
 */
@Data
public class OperationLog {
    private Integer id;
    /** 操作人id */
    private Integer operatorId;
    /** 操作人姓名 */
    private String operatorName;
    /** 操作类型：新增/修改/删除/评价审核 */
    private String actionType;
    /** 操作对象类型：community/facility/category/evaluation 等 */
    private String targetType;
    /** 操作对象id */
    private Integer targetId;
    /** 操作详情 */
    private String detail;
    private LocalDateTime createTime;
}
