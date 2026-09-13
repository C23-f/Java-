package com.example.springboot.controller;
import com.example.springboot.common.Result;
import com.example.springboot.entity.AnalysisPlan;
import com.example.springboot.service.AnalysisPlanService;
import jakarta.annotation.Resource;
import org.springframework.web.bind.annotation.*;
import java.util.List;
@RestController
@RequestMapping("/api")
public class AnalysisPlanController {
    @Resource
    private AnalysisPlanService analysisPlanService;
    // 新增分析方案
    @PostMapping("/plan")
    public Result<AnalysisPlan> savePlan(@RequestBody AnalysisPlan analysisPlan){
        int rows = analysisPlanService.addPlan(analysisPlan);
        if(rows > 0){
            return Result.success(analysisPlan);
        }else{
            return Result.error("保存方案失败");
        }
    }
    // 根据用户id获取方案列表
    @GetMapping("/plan/list/{userId}")
    public Result<List<AnalysisPlan>> getPlanList(@PathVariable Integer userId){
        List<AnalysisPlan> list = analysisPlanService.getPlanListByUserId(userId);
        return Result.success(list);
    }
    // 根据ID查询方案详情
    @GetMapping("/plan/{id}")
    public Result<AnalysisPlan> getPlanDetail(@PathVariable Integer id){
        AnalysisPlan plan = analysisPlanService.getPlanById(id);
        return Result.success(plan);
    }

    // 5. 修改方案
    @PutMapping("/plan/{id}")
    public Result<Integer> updatePlan(@PathVariable Integer id, @RequestBody AnalysisPlan analysisPlan){
        analysisPlan.setId(id);
        int rows = analysisPlanService.updatePlan(analysisPlan);
        if(rows > 0){
            return Result.success(rows);
        }else{
            return Result.error("修改失败，未找到该方案");
        }
    }

    // 6. 删除方案
    @DeleteMapping("/plan/{id}")
    public Result<Integer> deletePlan(@PathVariable Integer id){
        int rows = analysisPlanService.deletePlan(id);
        if(rows > 0){
            return Result.success(rows);
        }else{
            return Result.error("删除失败，未找到该方案");
        }
    }
}
