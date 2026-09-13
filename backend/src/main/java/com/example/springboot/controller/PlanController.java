package com.example.springboot.controller;

import com.example.springboot.common.Result;
import com.example.springboot.entity.AnalysisPlan;
import com.example.springboot.service.AnalysisPlanService;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import jakarta.annotation.Resource;

@RestController
@RequestMapping("/api/plan")
public class PlanController {

    @Resource
    private AnalysisPlanService analysisPlanService;

    @PostMapping("/save")
    public Result<?> save(@RequestBody AnalysisPlan plan){
        boolean ok = analysisPlanService.save(plan);
        return ok ? Result.success() : Result.error("保存方案失败");
    }
}
