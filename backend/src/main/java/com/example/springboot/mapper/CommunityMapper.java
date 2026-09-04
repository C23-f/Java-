package com.example.springboot.mapper;

import com.example.springboot.entity.AccessibilityScore;
import com.example.springboot.entity.Community;
import com.example.springboot.entity.CommunityStatsVO;
import org.apache.ibatis.annotations.Param;
import java.util.List;

public interface CommunityMapper {
    // 查询全部小区列表
    List<Community> selectAllCommunity();

    // 调用存储过程：获取15分钟缓冲区分类统计
    List<CommunityStatsVO> callStatsProc(@Param("communityId") Integer communityId, @Param("radiusM") Integer radiusM);

    // 调用存储过程：执行可达性评分计算
    AccessibilityScore callCalcScoreProc(@Param("communityId") Integer communityId,
                                         @Param("radiusM") Integer radiusM,
                                         @Param("perCategoryCap") Integer perCategoryCap);
}
