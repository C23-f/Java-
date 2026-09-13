package com.example.springboot.service;

import com.example.springboot.entity.CommunityStatsVO;
import com.example.springboot.entity.Facility;
import com.example.springboot.entity.PageResult;
import java.util.List;

public interface FacilitySpatialService {
    // 查询全部有效设施列表
    List<Facility> listAll();

    // 根据ID查询设施详情
    Facility getById(Integer id);

    // 新增设施
    void add(Facility facility);

    // 修改设施
    void edit(Facility facility);

    // 删除设施（逻辑删除）
    void remove(Integer id);

    // 矩形框选范围内设施查询
    List<Facility> listFacilityByBounds(Double minLng, Double maxLng, Double minLat, Double maxLat);

    // 指定点位周边N米范围内设施查询
    List<Facility> listFacilityByPointBuffer(Double lng, Double lat, Integer radiusM);

    List<CommunityStatsVO> getPointBufferStats(Double longitude, Double latitude, Integer radius);

    // ==================== 分页 + 全局搜索（新增） ====================

    // 分页条件查询设施（keyword模糊名称 / categoryId分类 / districtId街道 / 评分下限）
    PageResult<Facility> listFacilityPage(Integer pageNum, Integer pageSize, String keyword,
                                          Integer categoryId, Integer districtId, Double minScore);

    // 全局模糊搜索设施（按名称）
    List<Facility> searchFacilities(String keyword);

}
