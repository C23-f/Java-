package com.example.springboot.mapper;

import org.apache.ibatis.annotations.Param;
import java.util.List;
import java.util.Map;

/**
 * 统计图表 Mapper：为前端 ECharts / 统计大屏提供聚合数据
 */
public interface StatsMapper {

    // 各类设施数量统计（柱状图/饼图）
    List<Map<String, Object>> facilityByCategory();

    // 可达性评分分布（按等级 优/良/中/差，取每小区最新一次评分）
    List<Map<String, Object>> scoreDistribution();

    // 小区房价分布（按价格区间分组）
    List<Map<String, Object>> priceDistribution();

    // 可达性评分 Top N 设施（按 avg_score 降序）
    List<Map<String, Object>> topFacilities(@Param("limit") Integer limit);

    // 全区域汇总指标（统计大屏）
    Map<String, Object> overview();

    // 视口密度统计（按经纬度范围）
    Map<String, Object> density(@Param("minLng") Double minLng,
                                @Param("maxLng") Double maxLng,
                                @Param("minLat") Double minLat,
                                @Param("maxLat") Double maxLat);
}
