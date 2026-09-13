package com.example.springboot.service.impl;
import com.example.springboot.entity.Evaluation;
import com.example.springboot.entity.PageResult;
import com.example.springboot.mapper.EvaluationMapper;
import com.example.springboot.service.EvaluationService;
import com.example.springboot.service.OperationLogService;
import jakarta.annotation.Resource;
import org.springframework.stereotype.Service;
import java.util.List;
import java.util.Map;

@Service
public class EvaluationServiceImpl implements EvaluationService {
    @Resource
    private EvaluationMapper evaluationMapper;
    @Resource
    private OperationLogService operationLogService;

    @Override
    public int insert(Evaluation evaluation) {
        return evaluationMapper.insert(evaluation);
    }

    @Override
    public boolean audit(Integer id, Integer status, String rejectReason, Integer auditorId) {
        // 先查原评价，拿到评价对象类型和对象ID，用于审核后重算平均分
        Evaluation exist = evaluationMapper.selectById(id);
        if (exist == null) {
            return false;
        }
        boolean ok = evaluationMapper.auditEvaluation(id, status, rejectReason, auditorId) > 0;
        if (ok) {
            // 审核后统一重算对应小区/设施平均分（SQL只统计 status=1 的已通过评价，
            // 因此通过/驳回都会触发重算，保证平均分始终与已公开评价一致）
            evaluationMapper.updateAvgScoreByObject(exist.getObjectType(), exist.getObjectId());
            // 记录操作日志
            operationLogService.log("评价审核", "evaluation", id,
                    "评价ID=" + id + " 审核为" + (status != null && status == 1 ? "通过" : "驳回")
                            + (rejectReason != null && !rejectReason.isEmpty() ? "，理由：" + rejectReason : ""));
        }
        return ok;
    }

    @Override
    public List<Evaluation> listEvaluation(Integer status) {
        return evaluationMapper.selectEvaluationList(status);
    }

    @Override
    public Evaluation getById(Integer id) {
        return evaluationMapper.selectById(id);
    }

    @Override
    public boolean delete(Integer id) {
        return evaluationMapper.deleteById(id) > 0;
    }
    // 新增：查询本人评价列表
    @Override
    public List<Evaluation> myListEvaluation(Integer userId) {
        return evaluationMapper.selectMyEvaluationList(userId);
    }

    // 新增：评价统计图表接口
    @Override
    public Map<String, Object> getEvaluationStats() {
        return evaluationMapper.getEvaluationStats();
    }

    // 分页查询评价
    @Override
    public PageResult<Evaluation> listEvaluationPage(Integer status, Integer pageNum, Integer pageSize) {
        int page = (pageNum == null || pageNum < 1) ? 1 : pageNum;
        int size = (pageSize == null || pageSize < 1) ? 10 : pageSize;
        int offset = (page - 1) * size;
        Long total = evaluationMapper.countEvaluation(status);
        List<Evaluation> list = evaluationMapper.selectEvaluationPage(status, offset, size);
        return PageResult.of(total, list, page, size);
    }
}
