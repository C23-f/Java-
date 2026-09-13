package com.example.springboot.service;
import com.example.springboot.entity.Evaluation;
import com.example.springboot.entity.PageResult;
import java.util.List;
import java.util.Map;

public interface EvaluationService {
    int insert(Evaluation evaluation);
    boolean audit(Integer id, Integer status, String rejectReason, Integer auditorId);
    List<Evaluation> listEvaluation(Integer status);

    // 根据id查询评价详情
    Evaluation getById(Integer id);

    // 删除评价
    boolean delete(Integer id);

    // 查询当前登录用户本人的评价
    List<Evaluation> myListEvaluation(Integer userId);
    // 评价数量统计（前端图表）
    Map<String,Object> getEvaluationStats();

    // 分页查询评价（status可选）
    PageResult<Evaluation> listEvaluationPage(Integer status, Integer pageNum, Integer pageSize);
}
