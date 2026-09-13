package com.example.springboot.service;
import com.example.springboot.entity.AnalysisPlan;
import java.util.List;

public interface AnalysisPlanService {
    int addPlan(AnalysisPlan analysisPlan);
    List<AnalysisPlan> getPlanListByUserId(Integer userId);
    AnalysisPlan getPlanById(Integer id);

    // 修改方案
    int updatePlan(AnalysisPlan analysisPlan);
    // 删除方案
    int deletePlan(Integer id);
}
