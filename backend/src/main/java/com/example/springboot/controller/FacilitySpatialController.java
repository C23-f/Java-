package com.example.springboot.controller;

import com.example.springboot.common.Result;
import com.example.springboot.entity.CommunityStatsVO;
import com.example.springboot.entity.Facility;
import com.example.springboot.service.FacilitySpatialService;
import org.springframework.web.bind.annotation.*;
import jakarta.annotation.Resource;
import java.util.List;

/**
 * 设施 Controller
 *
 * 查询接口（GET）公开访问，前端地图页面无需登录即可浏览：
 *   设施列表：GET /api/facility/list
 *   设施详情：GET /api/facility/{id}
 *   矩形框选：GET /api/facility/bounds
 *   点位缓冲区：GET /api/facility/buffer
 *   点位分类统计：GET /api/facility/pointStats
 *
 * 增删改接口（POST/PUT/DELETE）需登录，仅 admin/operator 可操作：
 *   新增设施：POST /api/facility
 *   修改设施：PUT /api/facility
 *   删除设施：DELETE /api/facility/{id}（逻辑删除，status置为0）
 */
@RestController
@RequestMapping("/api/facility")
public class FacilitySpatialController {

    @Resource
    private FacilitySpatialService facilitySpatialService;

    // 获取全部有效设施列表
    @GetMapping("/list")
    public Result<List<Facility>> listAll() {
        List<Facility> list = facilitySpatialService.listAll();
        return Result.success(list);
    }

    // 根据ID查询设施详情
    @GetMapping("/{id:\\d+}")
    public Result<Facility> getById(@PathVariable Integer id) {
        Facility facility = facilitySpatialService.getById(id);
        return Result.success(facility);
    }

    // 新增设施
    @PostMapping
    public Result<String> add(@RequestBody Facility facility) {
        facilitySpatialService.add(facility);
        return Result.success("新增成功");
    }

    // 修改设施
    @PutMapping
    public Result<String> edit(@RequestBody Facility facility) {
        facilitySpatialService.edit(facility);
        return Result.success("修改成功");
    }

    // 删除设施（逻辑删除）
    @DeleteMapping("/{id:\\d+}")
    public Result<String> remove(@PathVariable Integer id) {
        facilitySpatialService.remove(id);
        return Result.success("删除成功");
    }

    // 矩形框选范围内设施查询
    @GetMapping("/bounds")
    public Result<List<Facility>> listByBounds(@RequestParam Double minLng,
                                               @RequestParam Double maxLng,
                                               @RequestParam Double minLat,
                                               @RequestParam Double maxLat) {
        List<Facility> list = facilitySpatialService.listFacilityByBounds(minLng, maxLng, minLat, maxLat);
        return Result.success(list);
    }

    // 指定点位周边N米范围内设施查询
    @GetMapping("/buffer")
    public Result<List<Facility>> listByBuffer(@RequestParam Double lng,
                                               @RequestParam Double lat,
                                               @RequestParam(defaultValue = "1000") Integer radius) {
        List<Facility> list = facilitySpatialService.listFacilityByPointBuffer(lng, lat, radius);
        return Result.success(list);
    }

    @GetMapping("/pointStats")
    public Result<List<CommunityStatsVO>> getPointStats(
            @RequestParam Double longitude,
            @RequestParam Double latitude,
            @RequestParam(defaultValue = "1000") Integer radius) {
        List<CommunityStatsVO> stats = facilitySpatialService.getPointBufferStats(longitude, latitude, radius);
        return Result.success(stats);
    }

}
