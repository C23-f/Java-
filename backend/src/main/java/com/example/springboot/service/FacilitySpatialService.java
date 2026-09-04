package com.example.springboot.service;

import com.example.springboot.entity.Facility;
import java.util.List;

public interface FacilitySpatialService {
    // 矩形框选范围内设施查询
    List<Facility> listFacilityByBounds(Double minLng, Double maxLng, Double minLat, Double maxLat);

    // 指定点位周边N米范围内设施查询
    List<Facility> listFacilityByPointBuffer(Double lng, Double lat, Integer radiusM);
}
