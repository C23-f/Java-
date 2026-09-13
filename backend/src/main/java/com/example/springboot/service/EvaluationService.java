package com.example.springboot.service;
import com.example.springboot.entity.Evaluation;
import java.util.List;

public interface EvaluationService {
    int insert(Evaluation evaluation);
    boolean audit(Integer id, Integer status, String rejectReason, Integer auditorId);
    List<Evaluation> listEvaluation(Integer status);

    // 根据id查询评价详情
    Evaluation getById(Integer id);

    // 删除评价
    boolean delete(Integer id);

}
