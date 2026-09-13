package com.example.springboot.mapper;

import com.example.springboot.entity.OperationLog;
import org.apache.ibatis.annotations.Param;
import java.util.List;

public interface OperationLogMapper {

    int insert(OperationLog operationLog);

    // 分页查询操作日志（operatorId / actionType 可选筛选）
    List<OperationLog> selectLogPage(@Param("offset") Integer offset,
                                     @Param("limit") Integer limit,
                                     @Param("operatorId") Integer operatorId,
                                     @Param("actionType") String actionType);

    // 统计操作日志总数
    Long countLog(@Param("operatorId") Integer operatorId,
                  @Param("actionType") String actionType);
}
