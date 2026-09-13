package com.example.springboot.service.impl;
import com.example.springboot.entity.Evaluation;
import com.example.springboot.mapper.EvaluationMapper;
import com.example.springboot.service.EvaluationService;
import jakarta.annotation.Resource;
import org.springframework.stereotype.Service;
import java.util.List;

@Service
public class EvaluationServiceImpl implements EvaluationService {
    @Resource
    private EvaluationMapper evaluationMapper;

    @Override
    public int insert(Evaluation evaluation) {
        return evaluationMapper.insert(evaluation);
    }

    @Override
    public boolean audit(Integer id, Integer status, String rejectReason, Integer auditorId) {
        return evaluationMapper.auditEvaluation(id, status, rejectReason, auditorId) > 0;
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
}




