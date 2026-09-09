package com.example.springboot.controller;

import com.example.springboot.common.Result;
import com.example.springboot.entity.AccessibilityScore;
import com.example.springboot.entity.Community;
import com.example.springboot.entity.CommunityStatsVO;
import com.example.springboot.service.CommunitySpatialService;
import org.springframework.web.bind.annotation.*;
import jakarta.annotation.Resource;
import java.util.List;

/**
 * 小区 Controller
 *
 * 查询接口（GET）公开访问，前端地图页面无需登录即可浏览：
 *   小区列表：GET /api/community/list
 *   小区详情：GET /api/community/{id}
 *   15分钟统计：GET /api/community/stats/{id}
 *   可达性评分：GET /api/community/score/{id}
 *   批量评分：GET /api/community/score/batch
 *   缓冲区统计：GET /api/community/circleStats
 *
 * 增删改接口（POST/PUT/DELETE）需登录，仅 admin/operator 可操作：
 *   新增小区：POST /api/community
 *   修改小区：PUT /api/community
 *   删除小区：DELETE /api/community/{id}
 */
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

    // 根据ID查询小区详情
    @GetMapping("/{id:\\d+}")
    public Result<Community> getById(@PathVariable Integer id) {
        Community community = communitySpatialService.getById(id);
        return Result.success(community);
    }

    // 新增小区
    @PostMapping
    public Result<String> add(@RequestBody Community community) {
        communitySpatialService.add(community);
        return Result.success("新增成功");
    }

    // 修改小区
    @PutMapping
    public Result<String> edit(@RequestBody Community community) {
        communitySpatialService.edit(community);
        return Result.success("修改成功");
    }

    // 删除小区
    @DeleteMapping("/{id:\\d+}")
    public Result<String> remove(@PathVariable Integer id) {
        communitySpatialService.remove(id);
        return Result.success("删除成功");
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

    /**
     * 15分钟生活圈缓冲区设施统计接口
    * @param communityId 小区id
    * @param bufferMeter 缓冲区半径，单位米，默认1000
    * @return 统一返回结果
    */
    @GetMapping("/circleStats")
    public Result<?> getCircleStats(
        @RequestParam Long communityId,
        @RequestParam(defaultValue = "1000") Integer bufferMeter
    ){
    return Result.success(communitySpatialService.getCommunityCircleData(communityId,bufferMeter));
    }

}
