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
}
