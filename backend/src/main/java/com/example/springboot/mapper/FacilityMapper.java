package com.example.springboot.mapper;

import com.example.springboot.entity.CommunityStatsVO;
import com.example.springboot.entity.Facility;
import org.apache.ibatis.annotations.Param;
import java.util.List;

public interface FacilityMapper {
    // 查询全部有效设施列表（status=1）
    List<Facility> selectAll();

    // 根据ID查询单个设施详情
    Facility selectById(@Param("facilityId") Integer facilityId);

    // 新增设施
    int insert(Facility facility);

    // 修改设施
    int update(Facility facility);

    // 根据ID删除设施（逻辑删除：status置为0）
    int deleteById(@Param("facilityId") Integer facilityId);

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

    // ==================== 分页 + 全局搜索 + 平均分联动（新增） ====================

    // 分页条件查询设施（keyword模糊名称 / categoryId分类 / districtId街道 / minScore评分下限）
    List<Facility> selectFacilityPage(@Param("offset") Integer offset,
                                      @Param("limit") Integer limit,
                                      @Param("keyword") String keyword,
                                      @Param("categoryId") Integer categoryId,
                                      @Param("districtId") Integer districtId,
                                      @Param("minScore") Double minScore);

    // 分页条件统计设施总数（条件与 selectFacilityPage 一致）
    Long countFacility(@Param("keyword") String keyword,
                       @Param("categoryId") Integer categoryId,
                       @Param("districtId") Integer districtId,
                       @Param("minScore") Double minScore);

    // 全局模糊搜索设施（按名称）
    List<Facility> searchFacilities(@Param("keyword") String keyword);

    // 审核通过后重算设施平均分（只统计已通过评价 status=1）
    int updateFacilityAvgScore(@Param("objectId") Integer objectId);
}
