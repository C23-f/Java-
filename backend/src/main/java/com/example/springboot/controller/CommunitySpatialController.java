package com.example.springboot.controller;

import com.example.springboot.common.Result;
import com.example.springboot.entity.AccessibilityScore;
import com.example.springboot.entity.Community;
import com.example.springboot.entity.CommunityStatsVO;
import com.example.springboot.service.CommunitySpatialService;
import org.springframework.web.bind.annotation.*;
import jakarta.annotation.Resource;
import java.util.List;

@RestController
@RequestMapping("/api/community")
public class CommunitySpatialController {

    @Resource
    private CommunitySpatialService communitySpatialService;

    // 获取全部小区列表
    @GetMapping("/list")
    public Result<List<Community>> listAll() {
        List<Community> list = communitySpatialService.listAllCommunity();
        return Result.success(list);
    }

    // 获取单个小区15分钟生活圈分类统计
    @GetMapping("/stats/{id}")
    public Result<List<CommunityStatsVO>> getStats(@PathVariable Integer id,
                                                   @RequestParam(defaultValue = "1000") Integer radius) {
        List<CommunityStatsVO> stats = communitySpatialService.getCommunity15MinStats(id, radius);
        return Result.success(stats);
    }

    // 计算单个小区可达性评分
    @GetMapping("/score/{id}")
    public Result<AccessibilityScore> calcScore(@PathVariable Integer id,
                                                @RequestParam(defaultValue = "1000") Integer radius,
                                                @RequestParam(defaultValue = "3") Integer perCategoryCap) {
        AccessibilityScore score = communitySpatialService.calcSingleScore(id, radius, perCategoryCap);
        return Result.success(score);
    }

    // 批量计算全部小区可达性评分
    @GetMapping("/score/batch")
    public Result<List<AccessibilityScore>> batchCalcScore(@RequestParam(defaultValue = "1000") Integer radius,
                                                           @RequestParam(defaultValue = "3") Integer perCategoryCap) {
        List<AccessibilityScore> list = communitySpatialService.batchCalcAllCommunity(radius, perCategoryCap);
        return Result.success(list);
    }
}
