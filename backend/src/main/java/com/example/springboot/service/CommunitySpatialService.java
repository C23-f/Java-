package com.example.springboot.service;

import com.example.springboot.entity.AccessibilityScore;
import com.example.springboot.entity.Community;
import com.example.springboot.entity.CommunityStatsVO;
import com.example.springboot.entity.PageResult;
import com.example.springboot.entity.SpatialCircleVO;

import java.util.List;

public interface CommunitySpatialService {
    // 查询全部小区列表
    List<Community> listAllCommunity();

    // 根据ID查询小区详情
    Community getById(Integer id);

    // 新增小区
    void add(Community community);

    // 修改小区
    void edit(Community community);

    // 删除小区
    void remove(Integer id);

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

    // ==================== 分页 + 空间查询 + 全局搜索（新增） ====================

    // 分页条件查询小区（keyword模糊名称 / districtId街道 / 房价区间 / 评分下限）
    PageResult<Community> listCommunityPage(Integer pageNum, Integer pageSize, String keyword,
                                            Integer districtId, Double priceMin, Double priceMax, Double minScore);

    // 矩形框选范围内小区查询
    List<Community> listCommunityByBounds(Double minLng, Double maxLng, Double minLat, Double maxLat);

    // 指定点位周边N米范围内小区查询
    List<Community> listCommunityByPointBuffer(Double lng, Double lat, Integer radiusM);

    // 全局模糊搜索小区（按名称）
    List<Community> searchCommunities(String keyword);

}
