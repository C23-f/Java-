package com.example.springboot.service.impl;

import com.example.springboot.common.UserContext;
import com.example.springboot.entity.OperationLog;
import com.example.springboot.entity.PageResult;
import com.example.springboot.entity.User;
import com.example.springboot.mapper.OperationLogMapper;
import com.example.springboot.service.OperationLogService;
import jakarta.annotation.Resource;
import org.springframework.stereotype.Service;
import java.util.List;

@Service
public class OperationLogServiceImpl implements OperationLogService {

    @Resource
    private OperationLogMapper operationLogMapper;

    @Override
    public void log(String actionType, String targetType, Integer targetId, String detail) {
        User current = UserContext.get();
        if (current == null || current.getUserId() == null) {
            // 未登录的公开操作不记录
            return;
        }
        OperationLog log = new OperationLog();
        log.setOperatorId(current.getUserId());
        log.setOperatorName(current.getUsername());
        log.setActionType(actionType);
        log.setTargetType(targetType);
        log.setTargetId(targetId);
        log.setDetail(detail);
        try {
            operationLogMapper.insert(log);
        } catch (Exception ignored) {
            // 日志写入失败不影响主业务
        }
    }

    @Override
    public PageResult<OperationLog> listLog(Integer pageNum, Integer pageSize,
                                            Integer operatorId, String actionType) {
        int page = (pageNum == null || pageNum < 1) ? 1 : pageNum;
        int size = (pageSize == null || pageSize < 1) ? 10 : pageSize;
        int offset = (page - 1) * size;
        Long total = operationLogMapper.countLog(operatorId, actionType);
        List<OperationLog> list = operationLogMapper.selectLogPage(offset, size, operatorId, actionType);
        return PageResult.of(total, list, page, size);
    }
}
