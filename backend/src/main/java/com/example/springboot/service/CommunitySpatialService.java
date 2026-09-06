package com.example.springboot.service;

import com.example.springboot.entity.AccessibilityScore;
import com.example.springboot.entity.Community;
import com.example.springboot.entity.CommunityStatsVO;
import com.example.springboot.entity.SpatialCircleVO;

import java.util.List;

public interface CommunitySpatialService {
    // 查询全部小区列表
    List<Community> listAllCommunity();

    // 单个小区15分钟生活圈缓冲区分类统计
    List<CommunityStatsVO> getCommunity15MinStats(Integer communityId, Integer radiusM);

    // 单个小区计算可达性评分
    AccessibilityScore calcSingleScore(Integer communityId, Integer radiusM, Integer perCategoryCap);

    // 批量计算全部小区可达性评分
    List<AccessibilityScore> batchCalcAllCommunity(Integer radiusM, Integer perCategoryCap);

    /**
    * 获取小区15分钟生活圈缓冲区设施统计
    * @param communityId 小区id
    * @param bufferMeter 缓冲区半径（米，一般传入1000）
    * @return 空间分析VO集合
    */
    List<SpatialCircleVO> getCommunityCircleData(Long communityId, Integer bufferMeter);

}
