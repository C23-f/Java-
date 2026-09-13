package com.example.springboot.service;
import com.example.springboot.entity.Evaluation;
import java.util.List;

public interface EvaluationService {
    int insert(Evaluation evaluation);
    boolean audit(Integer id, Integer status, String rejectReason, Integer auditorId);
    List<Evaluation> listEvaluation(Integer status);
}
