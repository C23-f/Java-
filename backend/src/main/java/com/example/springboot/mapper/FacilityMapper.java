package com.example.springboot.mapper;

import com.example.springboot.entity.CommunityStatsVO;
import com.example.springboot.entity.Facility;
import org.apache.ibatis.annotations.Param;
import java.util.List;

public interface FacilityMapper {
    // 矩形框选范围内设施查询
    List<Facility> selectFacilityByBounds(@Param("minLng") Double minLng,
                                          @Param("maxLng") Double maxLng,
                                          @Param("minLat") Double minLat,
                                          @Param("maxLat") Double maxLat);

    // 指定点位周边N米范围内设施查询
    List<Facility> selectFacilityByPointBuffer(@Param("lng") Double lng,
                                               @Param("lat") Double lat,
                                               @Param("radiusM") Integer radiusM);

    // 指定点位周边N米范围设施分类统计
    List<CommunityStatsVO> selectPointBufferStats(
        @Param("longitude") Double longitude,
        @Param("latitude") Double latitude,
        @Param("radius") Integer radius
);

}
