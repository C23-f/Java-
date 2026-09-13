package com.example.springboot.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.example.springboot.entity.AnalysisPlan;
import com.example.springboot.mapper.AnalysisPlanMapper;
import com.example.springboot.service.AnalysisPlanService;
import org.springframework.stereotype.Service;

@Service
public class AnalysisPlanServiceImpl extends ServiceImpl<AnalysisPlanMapper, AnalysisPlan>
        implements AnalysisPlanService {
}
