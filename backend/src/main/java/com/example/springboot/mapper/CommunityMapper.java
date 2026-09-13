package com.example.springboot.mapper;

import com.example.springboot.entity.AccessibilityScore;
import com.example.springboot.entity.Community;
import com.example.springboot.entity.CommunityStatsVO;
import com.example.springboot.entity.SpatialCircleVO;
import org.apache.ibatis.annotations.Param;
import java.util.List;

public interface CommunityMapper {
    // 查询全部小区列表
    List<Community> selectAllCommunity();

    // 根据ID查询单个小区详情
    Community selectById(@Param("communityId") Integer communityId);

    // 新增小区
    int insert(Community community);

    // 修改小区
    int update(Community community);

    // 根据ID删除小区（物理删除）
    int deleteById(@Param("communityId") Integer communityId);

    // 调用存储过程：获取15分钟缓冲区分类统计
    List<CommunityStatsVO> callStatsProc(@Param("communityId") Integer communityId, @Param("radiusM") Integer radiusM);

    // 调用存储过程：执行可达性评分计算
    AccessibilityScore callCalcScoreProc(@Param("communityId") Integer communityId,
                                        @Param("radiusM") Integer radiusM,
                                        @Param("perCategoryCap") Integer perCategoryCap);

    // 15分钟生活圈缓冲区统计，返回VO列表
    List<SpatialCircleVO> getCommunitySpatialCircle(
            @Param("communityId") Long communityId,
            @Param("bufferMeter") Integer bufferMeter
    );

    // ==================== 分页 + 空间查询 + 全局搜索（新增） ====================

    // 分页条件查询小区（keyword模糊名称 / districtId街道 / priceMin、priceMax房价区间 / minScore评分下限）
    List<Community> selectCommunityPage(@Param("offset") Integer offset,
                                        @Param("limit") Integer limit,
                                        @Param("keyword") String keyword,
                                        @Param("districtId") Integer districtId,
                                        @Param("priceMin") Double priceMin,
                                        @Param("priceMax") Double priceMax,
                                        @Param("minScore") Double minScore);

    // 分页条件统计小区总数（条件与 selectCommunityPage 一致）
    Long countCommunity(@Param("keyword") String keyword,
                        @Param("districtId") Integer districtId,
                        @Param("priceMin") Double priceMin,
                        @Param("priceMax") Double priceMax,
                        @Param("minScore") Double minScore);

    // 矩形框选范围内小区查询
    List<Community> selectCommunityByBounds(@Param("minLng") Double minLng,
                                            @Param("maxLng") Double maxLng,
                                            @Param("minLat") Double minLat,
                                            @Param("maxLat") Double maxLat);

    // 指定点位周边N米范围内小区查询
    List<Community> selectCommunityByPointBuffer(@Param("lng") Double lng,
                                                 @Param("lat") Double lat,
                                                 @Param("radiusM") Integer radiusM);

    // 全局模糊搜索小区（按名称）
    List<Community> searchCommunities(@Param("keyword") String keyword);

    // 审核通过后重算小区平均分（只统计已通过评价）
    int updateCommunityAvgScore(@Param("objectId") Integer objectId);
}
