package com.example.springboot.controller;

import com.example.springboot.common.BizException;
import com.example.springboot.common.Result;
import com.example.springboot.entity.AccessibilityScore;
import com.example.springboot.entity.Community;
import com.example.springboot.entity.CommunityStatsVO;
import com.example.springboot.entity.PageResult;
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
 *   分页查询：GET /api/community/page
 *   矩形框选：GET /api/community/bounds
 *   周边小区：GET /api/community/buffer
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

    // ==================== 分页 + 空间查询（新增） ====================

    // 分页条件查询小区
    @GetMapping("/page")
    public Result<PageResult<Community>> page(
            @RequestParam(defaultValue = "1") Integer page,
            @RequestParam(defaultValue = "10") Integer size,
            @RequestParam(required = false) String keyword,
            @RequestParam(required = false) Integer districtId,
            @RequestParam(required = false) Double priceMin,
            @RequestParam(required = false) Double priceMax,
            @RequestParam(required = false) Double minScore) {
        return Result.success(communitySpatialService.listCommunityPage(
                page, size, keyword, districtId, priceMin, priceMax, minScore));
    }

    // 矩形框选范围内小区查询
    @GetMapping("/bounds")
    public Result<List<Community>> bounds(@RequestParam Double minLng,
                                          @RequestParam Double maxLng,
                                          @RequestParam Double minLat,
                                          @RequestParam Double maxLat) {
        validateBounds(minLng, maxLng, minLat, maxLat);
        return Result.success(communitySpatialService.listCommunityByBounds(minLng, maxLng, minLat, maxLat));
    }

    // 指定点位周边N米范围内小区查询
    @GetMapping("/buffer")
    public Result<List<Community>> buffer(@RequestParam Double lng,
                                          @RequestParam Double lat,
                                          @RequestParam(defaultValue = "1000") Integer radius) {
        validateRadius(lng, lat, radius);
        return Result.success(communitySpatialService.listCommunityByPointBuffer(lng, lat, radius));
    }

    private void validateBounds(Double minLng, Double maxLng, Double minLat, Double maxLat) {
        if (minLng == null || maxLng == null || minLat == null || maxLat == null) {
            throw new BizException("经纬度范围参数不能为空");
        }
        if (minLng >= maxLng || minLat >= maxLat) {
            throw new BizException("经纬度范围不合法：min 必须小于 max");
        }
    }

    private void validateRadius(Double lng, Double lat, Integer radius) {
        if (lng == null || lat == null || radius == null) {
            throw new BizException("经纬度和缓冲区半径参数不能为空");
        }
        if (lng < -180 || lng > 180 || lat < -90 || lat > 90) {
            throw new BizException("经纬度不合法");
        }
        if (radius <= 0 || radius > 5000) {
            throw new BizException("缓冲区半径必须大于0且不超过5000米");
        }
    }

}
