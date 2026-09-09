package com.example.springboot.service;

import com.example.springboot.entity.CommunityStatsVO;
import com.example.springboot.entity.Facility;
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

}
