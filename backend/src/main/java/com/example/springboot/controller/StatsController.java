package com.example.springboot.controller;

import com.example.springboot.common.BizException;
import com.example.springboot.common.Result;
import com.example.springboot.mapper.StatsMapper;
import jakarta.annotation.Resource;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import java.util.List;
import java.util.Map;

/**
 * 统计图表 Controller：为前端 ECharts / 统计大屏提供聚合数据
 * 所有接口需登录访问（JwtInterceptor 默认校验）
 */
@RestController
@RequestMapping("/api/stats")
public class StatsController {

    @Resource
    private StatsMapper statsMapper;

    /** 各类设施数量统计（柱状图/饼图） */
    @GetMapping("/facilityByCategory")
    public Result<List<Map<String, Object>>> facilityByCategory() {
        return Result.success(statsMapper.facilityByCategory());
    }

    /** 可达性评分分布（按等级 优/良/中/差） */
    @GetMapping("/scoreDistribution")
    public Result<List<Map<String, Object>>> scoreDistribution() {
        return Result.success(statsMapper.scoreDistribution());
    }

    /** 小区房价分布（按价格区间分组） */
    @GetMapping("/priceDistribution")
    public Result<List<Map<String, Object>>> priceDistribution() {
        return Result.success(statsMapper.priceDistribution());
    }

    /** 可达性评分 Top N 设施排行 */
    @GetMapping("/topFacilities")
    public Result<List<Map<String, Object>>> topFacilities(
            @RequestParam(defaultValue = "8") Integer limit) {
        if (limit == null || limit < 1 || limit > 100) {
            throw new BizException("limit 参数不合法，有效范围 1~100");
        }
        return Result.success(statsMapper.topFacilities(limit));
    }

    /** 全区域汇总指标（统计大屏） */
    @GetMapping("/overview")
    public Result<Map<String, Object>> overview() {
        return Result.success(statsMapper.overview());
    }

    /** 视口密度统计：经纬度范围 + 面积 + 每平方公里设施密度 */
    @GetMapping("/density")
    public Result<Map<String, Object>> density(@RequestParam Double minLng,
                                               @RequestParam Double maxLng,
                                               @RequestParam Double minLat,
                                               @RequestParam Double maxLat) {
        validateBounds(minLng, maxLng, minLat, maxLat);
        return Result.success(statsMapper.density(minLng, maxLng, minLat, maxLat));
    }

    /** 经纬度范围合法性校验 */
    private void validateBounds(Double minLng, Double maxLng, Double minLat, Double maxLat) {
        if (minLng == null || maxLng == null || minLat == null || maxLat == null) {
            throw new BizException("经纬度范围参数不能为空");
        }
        if (minLng < -180 || maxLng > 180 || minLat < -90 || maxLat > 90) {
            throw new BizException("经纬度不合法");
        }
        if (minLng >= maxLng || minLat >= maxLat) {
            throw new BizException("经纬度范围不合法：min 必须小于 max");
        }
    }
}
