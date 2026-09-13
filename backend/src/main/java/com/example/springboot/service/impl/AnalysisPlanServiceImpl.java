package com.example.springboot.service.impl;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.example.springboot.entity.AnalysisPlan;
import com.example.springboot.mapper.AnalysisPlanMapper;
import com.example.springboot.service.AnalysisPlanService;
import org.springframework.stereotype.Service;
import jakarta.annotation.Resource;
import java.util.List;
import com.example.springboot.mapper.AnalysisPlanCustomMapper;

@Service
public class AnalysisPlanServiceImpl implements AnalysisPlanService {
    @Resource
    private AnalysisPlanMapper analysisPlanMapper;
    @Resource
    private AnalysisPlanCustomMapper analysisPlanCustomMapper;

    @Override
    public int addPlan(AnalysisPlan analysisPlan) {
        return analysisPlanMapper.insert(analysisPlan);
    }

    @Override
    public List<AnalysisPlan> getPlanListByUserId(Integer userId) {
        return analysisPlanCustomMapper.getPlanListByUserId(userId);
    }

    @Override
    public AnalysisPlan getPlanById(Integer id) {
        return analysisPlanMapper.getPlanById(id);
    }

    // 修改方案
    @Override
    public int updatePlan(AnalysisPlan analysisPlan) {
        return analysisPlanMapper.updatePlan(analysisPlan);
    }

    // 删除方案
    @Override
    public int deletePlan(Integer id) {
        return analysisPlanMapper.deletePlan(id);
    }
}
